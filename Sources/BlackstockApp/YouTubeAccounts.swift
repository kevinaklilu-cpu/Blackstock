#if os(macOS)
import Foundation
import AppKit
import Network
import CryptoKit
import BlackstockCore

struct ConnectedYouTubeAccount: Codable, Identifiable, Equatable {
    let id: UUID
    var channelID: String
    var channelTitle: String
    var subscriberCount: Int
    var connectedAt: Date

    init(id: UUID = UUID(), channelID: String, channelTitle: String, subscriberCount: Int = 0, connectedAt: Date = Date()) {
        self.id = id
        self.channelID = channelID
        self.channelTitle = channelTitle
        self.subscriberCount = subscriberCount
        self.connectedAt = connectedAt
    }
}

private struct OAuthTokenSet: Codable {
    var accessToken: String
    var refreshToken: String
    var expiresAt: Date
    var scope: String
}

enum YouTubeAccountError: LocalizedError {
    case missingOAuthClient
    case authorizationCancelled
    case authorizationFailed(String)
    case invalidResponse
    case noChannel
    case missingToken
    case uploadFailed(String)

    var errorDescription: String? {
        switch self {
        case .missingOAuthClient: return "Dieser Blackstock-Build enthält noch keine Google OAuth Desktop Client-ID."
        case .authorizationCancelled: return "Die YouTube-Verbindung wurde abgebrochen."
        case .authorizationFailed(let message): return message
        case .invalidResponse: return "Google/YouTube hat eine unerwartete Antwort geliefert."
        case .noChannel: return "Für dieses Google-Konto wurde kein YouTube-Kanal gefunden."
        case .missingToken: return "Die gespeicherte YouTube-Anmeldung fehlt oder ist abgelaufen."
        case .uploadFailed(let message): return message
        }
    }
}

@MainActor
final class YouTubeAccountManager: ObservableObject {
    @Published private(set) var accounts: [ConnectedYouTubeAccount] = []
    @Published var isConnecting = false
    @Published var statusMessage: String?

    private let accountsKey = "blackstock.youtube.accounts"

    init() { loadAccounts() }

    var oauthConfigured: Bool { !oauthClientID.isEmpty }

    func connect() async -> ConnectedYouTubeAccount? {
        guard !oauthClientID.isEmpty else { statusMessage = YouTubeAccountError.missingOAuthClient.localizedDescription; return nil }
        isConnecting = true
        statusMessage = "YouTube wird sicher im Systembrowser verbunden …"
        defer { isConnecting = false }
        do {
            let token = try await authorize()
            let channel = try await fetchMyChannel(accessToken: token.accessToken)
            let existing = accounts.first { $0.channelID == channel.channelID }
            let account = ConnectedYouTubeAccount(id: existing?.id ?? UUID(), channelID: channel.channelID, channelTitle: channel.channelTitle, subscriberCount: channel.subscriberCount, connectedAt: existing?.connectedAt ?? Date())
            store(token: token, accountID: account.id)
            if let index = accounts.firstIndex(where: { $0.id == account.id }) { accounts[index] = account } else { accounts.append(account) }
            persistAccounts()
            statusMessage = "Verbunden mit \(account.channelTitle)."
            return account
        } catch {
            statusMessage = error.localizedDescription
            return nil
        }
    }

    func disconnect(_ account: ConnectedYouTubeAccount) {
        accounts.removeAll { $0.id == account.id }
        Keychain.write("", account: tokenKey(account.id))
        persistAccounts()
    }

    func accessToken(for account: ConnectedYouTubeAccount) async throws -> String {
        guard var token = readToken(account.id) else { throw YouTubeAccountError.missingToken }
        if token.expiresAt.timeIntervalSinceNow > 120 { return token.accessToken }
        guard !token.refreshToken.isEmpty else { throw YouTubeAccountError.missingToken }
        token = try await refresh(token)
        store(token: token, accountID: account.id)
        return token.accessToken
    }

    private var oauthClientID: String {
        let bundle = (Bundle.main.object(forInfoDictionaryKey: "GoogleOAuthClientID") as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !bundle.isEmpty { return bundle }
        return Keychain.read("google-oauth-client-id")
    }

    private var oauthClientSecret: String {
        let bundle = (Bundle.main.object(forInfoDictionaryKey: "GoogleOAuthClientSecret") as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !bundle.isEmpty { return bundle }
        return Keychain.read("google-oauth-client-secret")
    }

    func saveOAuthFallback(clientID: String, clientSecret: String) {
        Keychain.write(clientID.trimmingCharacters(in: .whitespacesAndNewlines), account: "google-oauth-client-id")
        Keychain.write(clientSecret.trimmingCharacters(in: .whitespacesAndNewlines), account: "google-oauth-client-secret")
        objectWillChange.send()
    }

    private func authorize() async throws -> OAuthTokenSet {
        let verifier = Self.randomURLSafeString(byteCount: 48)
        let challenge = Self.base64URL(Data(SHA256.hash(data: Data(verifier.utf8))))
        let state = Self.randomURLSafeString(byteCount: 24)
        let receiver = LoopbackOAuthReceiver(expectedState: state)
        let redirectURI = try await receiver.start()

        var components = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
        components.queryItems = [
            .init(name: "client_id", value: oauthClientID),
            .init(name: "redirect_uri", value: redirectURI.absoluteString),
            .init(name: "response_type", value: "code"),
            .init(name: "scope", value: "https://www.googleapis.com/auth/youtube.readonly https://www.googleapis.com/auth/youtube.upload"),
            .init(name: "access_type", value: "offline"),
            .init(name: "prompt", value: "consent select_account"),
            .init(name: "state", value: state),
            .init(name: "code_challenge", value: challenge),
            .init(name: "code_challenge_method", value: "S256")
        ]
        guard let authURL = components.url else { throw YouTubeAccountError.invalidResponse }
        NSWorkspace.shared.open(authURL)
        let code = try await receiver.waitForCode()
        return try await exchange(code: code, verifier: verifier, redirectURI: redirectURI)
    }

    private func exchange(code: String, verifier: String, redirectURI: URL) async throws -> OAuthTokenSet {
        var fields = [
            "client_id": oauthClientID,
            "code": code,
            "code_verifier": verifier,
            "grant_type": "authorization_code",
            "redirect_uri": redirectURI.absoluteString
        ]
        if !oauthClientSecret.isEmpty { fields["client_secret"] = oauthClientSecret }
        return try await tokenRequest(fields: fields, previousRefreshToken: nil)
    }

    private func refresh(_ current: OAuthTokenSet) async throws -> OAuthTokenSet {
        var fields = [
            "client_id": oauthClientID,
            "refresh_token": current.refreshToken,
            "grant_type": "refresh_token"
        ]
        if !oauthClientSecret.isEmpty { fields["client_secret"] = oauthClientSecret }
        return try await tokenRequest(fields: fields, previousRefreshToken: current.refreshToken)
    }

    private func tokenRequest(fields: [String: String], previousRefreshToken: String?) async throws -> OAuthTokenSet {
        var request = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = fields.map { "\(Self.formEncode($0.key))=\(Self.formEncode($0.value))" }.sorted().joined(separator: "&").data(using: .utf8)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw YouTubeAccountError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            let message = (try? JSONDecoder().decode(OAuthErrorResponse.self, from: data).error_description) ?? "Google OAuth Fehler \(http.statusCode)"
            throw YouTubeAccountError.authorizationFailed(message)
        }
        let decoded = try JSONDecoder().decode(OAuthTokenResponse.self, from: data)
        return OAuthTokenSet(accessToken: decoded.access_token, refreshToken: decoded.refresh_token ?? previousRefreshToken ?? "", expiresAt: Date().addingTimeInterval(TimeInterval(decoded.expires_in)), scope: decoded.scope ?? "")
    }

    private func fetchMyChannel(accessToken: String) async throws -> ConnectedYouTubeAccount {
        var components = URLComponents(string: "https://www.googleapis.com/youtube/v3/channels")!
        components.queryItems = [.init(name: "part", value: "snippet,statistics"), .init(name: "mine", value: "true")]
        var request = URLRequest(url: components.url!)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { throw YouTubeAccountError.invalidResponse }
        let decoded = try JSONDecoder().decode(MineChannelResponse.self, from: data)
        guard let channel = decoded.items.first else { throw YouTubeAccountError.noChannel }
        return ConnectedYouTubeAccount(channelID: channel.id, channelTitle: channel.snippet.title, subscriberCount: Int(channel.statistics.subscriberCount ?? "0") ?? 0)
    }

    private func loadAccounts() {
        guard let data = UserDefaults.standard.data(forKey: accountsKey), let saved = try? JSONDecoder().decode([ConnectedYouTubeAccount].self, from: data) else { accounts = []; return }
        accounts = saved
    }

    private func persistAccounts() {
        if let data = try? JSONEncoder().encode(accounts) { UserDefaults.standard.set(data, forKey: accountsKey) }
    }

    private func tokenKey(_ id: UUID) -> String { "youtube-oauth-token-\(id.uuidString)" }
    private func store(token: OAuthTokenSet, accountID: UUID) { if let data = try? JSONEncoder().encode(token), let value = String(data: data, encoding: .utf8) { Keychain.write(value, account: tokenKey(accountID)) } }
    private func readToken(_ id: UUID) -> OAuthTokenSet? { let value = Keychain.read(tokenKey(id)); guard let data = value.data(using: .utf8) else { return nil }; return try? JSONDecoder().decode(OAuthTokenSet.self, from: data) }

    private static func randomURLSafeString(byteCount: Int) -> String {
        var bytes = [UInt8](repeating: 0, count: byteCount)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return base64URL(Data(bytes))
    }
    private static func base64URL(_ data: Data) -> String { data.base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "") }
    private static func formEncode(_ value: String) -> String { value.addingPercentEncoding(withAllowedCharacters: CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))) ?? value }
}

final class LoopbackOAuthReceiver: @unchecked Sendable {
    private let expectedState: String
    private let queue = DispatchQueue(label: "blackstock.oauth.loopback")
    private var listener: NWListener?
    private var codeContinuation: CheckedContinuation<String, Error>?
    private var pendingResult: Result<String, Error>?

    init(expectedState: String) { self.expectedState = expectedState }

    func start() async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            do {
                let listener = try NWListener(using: .tcp, on: .any)
                self.listener = listener
                listener.stateUpdateHandler = { state in
                    switch state {
                    case .ready:
                        guard let port = listener.port, let url = URL(string: "http://127.0.0.1:\(port.rawValue)/oauth2callback") else { continuation.resume(throwing: YouTubeAccountError.invalidResponse); return }
                        continuation.resume(returning: url)
                    case .failed(let error): continuation.resume(throwing: error)
                    default: break
                    }
                }
                listener.newConnectionHandler = { [weak self] connection in self?.handle(connection) }
                listener.start(queue: queue)
            } catch { continuation.resume(throwing: error) }
        }
    }

    func waitForCode() async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                if let result = self.pendingResult { self.pendingResult = nil; continuation.resume(with: result) }
                else { self.codeContinuation = continuation }
            }
        }
    }

    private func finish(_ result: Result<String, Error>) {
        if let continuation = codeContinuation { codeContinuation = nil; continuation.resume(with: result) } else { pendingResult = result }
        listener?.cancel(); listener = nil
    }

    private func handle(_ connection: NWConnection) {
        connection.start(queue: queue)
        connection.receive(minimumIncompleteLength: 1, maximumLength: 32_768) { [weak self] data, _, _, _ in
            guard let self else { return }
            guard let data, let request = String(data: data, encoding: .utf8), let firstLine = request.components(separatedBy: "\r\n").first else {
                self.finish(.failure(YouTubeAccountError.invalidResponse)); return
            }
            let parts = firstLine.split(separator: " ")
            guard parts.count >= 2, let url = URL(string: "http://127.0.0.1\(parts[1])"), let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
                self.finish(.failure(YouTubeAccountError.invalidResponse)); return
            }
            let query = Dictionary(uniqueKeysWithValues: components.queryItems?.compactMap { item in item.value.map { (item.name, $0) } } ?? [])
            let body: String
            let result: Result<String, Error>
            if let error = query["error"] {
                body = "<html><body style='font-family:-apple-system;padding:48px'><h2>Blackstock</h2><p>Verbindung abgebrochen. Du kannst dieses Fenster schließen.</p></body></html>"
                result = .failure(error == "access_denied" ? YouTubeAccountError.authorizationCancelled : YouTubeAccountError.authorizationFailed(error))
            } else if query["state"] == self.expectedState, let code = query["code"] {
                body = "<html><body style='font-family:-apple-system;padding:48px'><h2>Blackstock ist verbunden.</h2><p>Du kannst dieses Fenster schließen und zu Blackstock zurückkehren.</p></body></html>"
                result = .success(code)
            } else {
                body = "<html><body style='font-family:-apple-system;padding:48px'><h2>Blackstock</h2><p>Die Anmeldung konnte nicht bestätigt werden.</p></body></html>"
                result = .failure(YouTubeAccountError.invalidResponse)
            }
            let response = "HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: \(body.utf8.count)\r\nConnection: close\r\n\r\n\(body)"
            connection.send(content: Data(response.utf8), completion: .contentProcessed { _ in connection.cancel(); self.finish(result) })
        }
    }
}

struct YouTubeUploadService {
    func upload(project: Project, account: ConnectedYouTubeAccount, accessToken: String, privacyStatus: String, progress: @escaping @Sendable (Double) -> Void) async throws -> String {
        guard let videoURL = project.renderedOutputURL else { throw YouTubeAccountError.uploadFailed("Es fehlt ein final gerendertes Video.") }
        let metadata: [String: Any] = [
            "snippet": ["title": project.publishTitle ?? project.title, "description": project.publishDescription ?? "", "tags": project.publishTags ?? []],
            "status": ["privacyStatus": privacyStatus, "selfDeclaredMadeForKids": false]
        ]
        let body = try JSONSerialization.data(withJSONObject: metadata)
        var initRequest = URLRequest(url: URL(string: "https://www.googleapis.com/upload/youtube/v3/videos?uploadType=resumable&part=snippet,status")!)
        initRequest.httpMethod = "POST"
        initRequest.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        initRequest.setValue("application/json; charset=UTF-8", forHTTPHeaderField: "Content-Type")
        initRequest.setValue("video/mp4", forHTTPHeaderField: "X-Upload-Content-Type")
        if let size = (try? FileManager.default.attributesOfItem(atPath: videoURL.path)[.size] as? NSNumber)?.int64Value { initRequest.setValue(String(size), forHTTPHeaderField: "X-Upload-Content-Length") }
        initRequest.httpBody = body
        let (_, initResponse) = try await URLSession.shared.data(for: initRequest)
        guard let initHTTP = initResponse as? HTTPURLResponse, (200..<300).contains(initHTTP.statusCode), let location = initHTTP.value(forHTTPHeaderField: "Location"), let uploadURL = URL(string: location) else { throw YouTubeAccountError.uploadFailed("YouTube konnte den Upload nicht initialisieren.") }

        var uploadRequest = URLRequest(url: uploadURL)
        uploadRequest.httpMethod = "PUT"
        uploadRequest.setValue("video/mp4", forHTTPHeaderField: "Content-Type")
        progress(0.1)
        let (uploadData, uploadResponse) = try await URLSession.shared.upload(for: uploadRequest, fromFile: videoURL)
        guard let uploadHTTP = uploadResponse as? HTTPURLResponse, (200..<300).contains(uploadHTTP.statusCode) else { throw YouTubeAccountError.uploadFailed("Der Video-Upload ist fehlgeschlagen.") }
        let uploaded = try JSONDecoder().decode(UploadedVideoResponse.self, from: uploadData)
        progress(0.9)
        if let thumbnail = project.thumbnailURL { try await setThumbnail(videoID: uploaded.id, fileURL: thumbnail, accessToken: accessToken) }
        progress(1)
        return uploaded.id
    }

    private func setThumbnail(videoID: String, fileURL: URL, accessToken: String) async throws {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        var components = URLComponents(string: "https://www.googleapis.com/upload/youtube/v3/thumbnails/set")!
        components.queryItems = [.init(name: "videoId", value: videoID), .init(name: "uploadType", value: "media")]
        var request = URLRequest(url: components.url!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue(fileURL.pathExtension.lowercased() == "jpg" || fileURL.pathExtension.lowercased() == "jpeg" ? "image/jpeg" : "image/png", forHTTPHeaderField: "Content-Type")
        request.httpBody = data
        let (_, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { throw YouTubeAccountError.uploadFailed("Video wurde hochgeladen, aber das Thumbnail konnte nicht gesetzt werden.") }
    }
}

private struct OAuthTokenResponse: Decodable { let access_token: String; let expires_in: Int; let refresh_token: String?; let scope: String? }
private struct OAuthErrorResponse: Decodable { let error_description: String? }
private struct MineChannelResponse: Decodable { let items: [MineChannelItem] }
private struct MineChannelItem: Decodable { let id: String; let snippet: MineChannelSnippet; let statistics: MineChannelStatistics }
private struct MineChannelSnippet: Decodable { let title: String }
private struct MineChannelStatistics: Decodable { let subscriberCount: String? }
private struct UploadedVideoResponse: Decodable { let id: String }
#endif
