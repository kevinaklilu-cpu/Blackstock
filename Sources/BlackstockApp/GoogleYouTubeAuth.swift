#if os(macOS)
import Foundation
import AppKit
import Network
import CryptoKit
import BlackstockCore

struct YouTubeOAuthSession: Sendable {
    let channels: [ChannelSnapshot]
    let accessToken: String
    let refreshToken: String?
}

enum YouTubeOAuthError: LocalizedError {
    case missingClientID
    case browserCouldNotOpen
    case invalidCallback
    case stateMismatch
    case authorizationDenied(String)
    case tokenExchangeFailed(String)
    case noChannels

    var errorDescription: String? {
        switch self {
        case .missingClientID:
            return "Dieser Blackstock-Build enthält noch keine Google OAuth Client-ID."
        case .browserCouldNotOpen:
            return "Der Google-Login konnte nicht im Browser geöffnet werden."
        case .invalidCallback:
            return "Die Google-Anmeldung hat keine gültige Antwort geliefert."
        case .stateMismatch:
            return "Die Anmeldung wurde aus Sicherheitsgründen verworfen."
        case .authorizationDenied(let message):
            return message
        case .tokenExchangeFailed(let message):
            return message
        case .noChannels:
            return "Für dieses Google-Konto wurde kein YouTube-Kanal gefunden."
        }
    }
}

@MainActor
final class GoogleYouTubeAuth: ObservableObject {
    @Published private(set) var isConnecting = false
    @Published private(set) var statusMessage: String?

    static var configuredClientID: String {
        let bundled = (Bundle.main.object(forInfoDictionaryKey: "BlackstockGoogleOAuthClientID") as? String ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !bundled.isEmpty { return bundled }
        return Keychain.read("youtube-oauth-client-id").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func connect(clientID override: String? = nil) async throws -> YouTubeOAuthSession {
        let clientID = (override ?? Self.configuredClientID).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clientID.isEmpty else { throw YouTubeOAuthError.missingClientID }

        isConnecting = true
        statusMessage = "Google-Anmeldung wird geöffnet …"
        defer { isConnecting = false }

        let verifier = Self.randomURLSafeString(byteCount: 64)
        let challenge = Self.base64URL(Data(SHA256.hash(data: Data(verifier.utf8))))
        let state = Self.randomURLSafeString(byteCount: 24)
        let server = try LoopbackOAuthServer()
        let redirectURI = try await server.start()

        var components = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "redirect_uri", value: redirectURI.absoluteString),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: [
                "https://www.googleapis.com/auth/youtube.readonly",
                "https://www.googleapis.com/auth/youtube.upload",
                "https://www.googleapis.com/auth/yt-analytics.readonly"
            ].joined(separator: " ")),
            URLQueryItem(name: "access_type", value: "offline"),
            URLQueryItem(name: "prompt", value: "consent select_account"),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256")
        ]
        guard let authorizationURL = components.url, NSWorkspace.shared.open(authorizationURL) else {
            server.cancel()
            throw YouTubeOAuthError.browserCouldNotOpen
        }

        let callbackURL = try await server.waitForCallback()
        guard let callback = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false) else {
            throw YouTubeOAuthError.invalidCallback
        }
        let values = Dictionary(uniqueKeysWithValues: callback.queryItems?.compactMap { item in item.value.map { (item.name, $0) } } ?? [])
        if let error = values["error"] {
            throw YouTubeOAuthError.authorizationDenied(values["error_description"] ?? error)
        }
        guard values["state"] == state else { throw YouTubeOAuthError.stateMismatch }
        guard let code = values["code"], !code.isEmpty else { throw YouTubeOAuthError.invalidCallback }

        statusMessage = "YouTube-Kanäle werden verbunden …"
        let tokens = try await exchangeCode(code, verifier: verifier, clientID: clientID, redirectURI: redirectURI)
        let channels = try await fetchChannels(accessToken: tokens.accessToken)
        guard !channels.isEmpty else { throw YouTubeOAuthError.noChannels }

        for channel in channels {
            if let refresh = tokens.refreshToken, !refresh.isEmpty {
                Keychain.write(refresh, account: "youtube-refresh-\(channel.id)")
            }
            Keychain.write(tokens.accessToken, account: "youtube-access-\(channel.id)")
            Keychain.write("1", account: "youtube-connected-\(channel.id)")
        }
        Keychain.write(clientID, account: "youtube-oauth-client-id")
        statusMessage = channels.count == 1 ? "\(channels[0].title) verbunden" : "\(channels.count) YouTube-Kanäle verbunden"
        return YouTubeOAuthSession(channels: channels, accessToken: tokens.accessToken, refreshToken: tokens.refreshToken)
    }

    func disconnect(channelID: String) {
        Keychain.write("", account: "youtube-refresh-\(channelID)")
        Keychain.write("", account: "youtube-access-\(channelID)")
        Keychain.write("", account: "youtube-connected-\(channelID)")
    }

    static func isAuthenticated(channelID: String) -> Bool {
        !Keychain.read("youtube-connected-\(channelID)").isEmpty
    }

    private func exchangeCode(_ code: String, verifier: String, clientID: String, redirectURI: URL) async throws -> OAuthTokenResponse {
        var request = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Self.formEncoded([
            "client_id": clientID,
            "code": code,
            "code_verifier": verifier,
            "grant_type": "authorization_code",
            "redirect_uri": redirectURI.absoluteString
        ]).data(using: .utf8)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let message = (try? JSONDecoder().decode(OAuthErrorEnvelope.self, from: data).error_description) ?? "Google konnte den Autorisierungscode nicht in Tokens tauschen."
            throw YouTubeOAuthError.tokenExchangeFailed(message)
        }
        return try JSONDecoder().decode(OAuthTokenResponse.self, from: data)
    }

    private func fetchChannels(accessToken: String) async throws -> [ChannelSnapshot] {
        var components = URLComponents(string: "https://www.googleapis.com/youtube/v3/channels")!
        components.queryItems = [
            URLQueryItem(name: "part", value: "snippet,statistics"),
            URLQueryItem(name: "mine", value: "true"),
            URLQueryItem(name: "maxResults", value: "50")
        ]
        var request = URLRequest(url: components.url!)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw YouTubeOAuthError.tokenExchangeFailed("YouTube konnte die Kanäle dieses Kontos nicht laden.")
        }
        let result = try JSONDecoder().decode(AuthorizedChannelsResponse.self, from: data)
        return result.items.map {
            ChannelSnapshot(
                id: $0.id,
                title: $0.snippet.title,
                subscriberCount: Int($0.statistics.subscriberCount ?? "0") ?? 0,
                medianViews: 1,
                medianViewsPerHour: 1,
                recentTopics: []
            )
        }
    }

    private static func formEncoded(_ values: [String: String]) -> String {
        values.sorted { $0.key < $1.key }.map { key, value in
            let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
            let k = key.addingPercentEncoding(withAllowedCharacters: allowed) ?? key
            let v = value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
            return "\(k)=\(v)"
        }.joined(separator: "&")
    }

    private static func randomURLSafeString(byteCount: Int) -> String {
        var bytes = [UInt8](repeating: 0, count: byteCount)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return base64URL(Data(bytes))
    }

    private static func base64URL(_ data: Data) -> String {
        data.base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }
}

private struct OAuthTokenResponse: Decodable {
    let accessToken: String
    let refreshToken: String?
    let expiresIn: Int
    let tokenType: String

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
        case tokenType = "token_type"
    }
}

private struct OAuthErrorEnvelope: Decodable {
    let error: String?
    let error_description: String?
}

private struct AuthorizedChannelsResponse: Decodable { let items: [AuthorizedChannelItem] }
private struct AuthorizedChannelItem: Decodable { let id: String; let snippet: AuthorizedChannelSnippet; let statistics: AuthorizedChannelStatistics }
private struct AuthorizedChannelSnippet: Decodable { let title: String }
private struct AuthorizedChannelStatistics: Decodable { let subscriberCount: String? }

private final class LoopbackOAuthServer: @unchecked Sendable {
    private let listener: NWListener
    private let queue = DispatchQueue(label: "de.blackstock.oauth.loopback")
    private var callbackContinuation: CheckedContinuation<URL, Error>?
    private var pendingCallback: URL?

    init() throws {
        listener = try NWListener(using: .tcp, on: .any)
        listener.newConnectionHandler = { [weak self] connection in self?.handle(connection) }
    }

    func start() async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            listener.stateUpdateHandler = { [weak self] state in
                guard let self else { return }
                switch state {
                case .ready:
                    guard let port = self.listener.port, let url = URL(string: "http://127.0.0.1:\(port.rawValue)/callback") else {
                        continuation.resume(throwing: YouTubeOAuthError.invalidCallback)
                        self.listener.cancel()
                        return
                    }
                    self.listener.stateUpdateHandler = nil
                    continuation.resume(returning: url)
                case .failed(let error):
                    self.listener.stateUpdateHandler = nil
                    continuation.resume(throwing: error)
                case .cancelled:
                    break
                default:
                    break
                }
            }
            listener.start(queue: queue)
        }
    }

    func waitForCallback() async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            queue.async { [weak self] in
                guard let self else { continuation.resume(throwing: YouTubeOAuthError.invalidCallback); return }
                if let pending = self.pendingCallback {
                    self.pendingCallback = nil
                    continuation.resume(returning: pending)
                } else {
                    self.callbackContinuation = continuation
                }
            }
        }
    }

    func cancel() { listener.cancel() }

    private func handle(_ connection: NWConnection) {
        connection.start(queue: queue)
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [weak self] data, _, _, _ in
            guard let self, let data, let request = String(data: data, encoding: .utf8) else {
                connection.cancel(); return
            }
            let firstLine = request.components(separatedBy: "\r\n").first ?? ""
            let path = firstLine.split(separator: " ").dropFirst().first.map(String.init) ?? ""
            let callback = URL(string: "http://127.0.0.1\(path)")
            let html = """
            <!doctype html><html><head><meta charset="utf-8"><title>Blackstock</title></head>
            <body style="font-family:-apple-system;padding:48px;background:#0f0f0f;color:white"><h1>Blackstock ist verbunden.</h1><p>Du kannst dieses Fenster schließen und zu Blackstock zurückkehren.</p></body></html>
            """
            let response = "HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: \(html.utf8.count)\r\nConnection: close\r\n\r\n\(html)"
            connection.send(content: Data(response.utf8), completion: .contentProcessed { _ in connection.cancel() })
            if let callback { self.complete(callback) }
        }
    }

    private func complete(_ url: URL) {
        listener.cancel()
        if let continuation = callbackContinuation {
            callbackContinuation = nil
            continuation.resume(returning: url)
        } else {
            pendingCallback = url
        }
    }
}
#endif
