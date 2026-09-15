import Foundation
import AppKit
import Network
import CryptoKit

struct GoogleOAuthCredentials: Codable, Hashable {
    let clientID: String
    let clientSecret: String

    static func current(keychain: KeychainStore = KeychainStore()) -> GoogleOAuthCredentials? {
        if let stored = keychain.load(StoredOAuthCredentials.self, account: "google-oauth-client"), !stored.clientID.isEmpty {
            return .init(clientID: stored.clientID, clientSecret: stored.clientSecret)
        }
        let env = ProcessInfo.processInfo.environment
        let id = (Bundle.main.object(forInfoDictionaryKey: "BlackstockGoogleClientID") as? String) ?? env["BLACKSTOCK_GOOGLE_CLIENT_ID"]
        let secret = (Bundle.main.object(forInfoDictionaryKey: "BlackstockGoogleClientSecret") as? String) ?? env["BLACKSTOCK_GOOGLE_CLIENT_SECRET"]
        guard let id, !id.isEmpty, !id.hasPrefix("__BLACKSTOCK") else { return nil }
        return .init(clientID: id, clientSecret: secret ?? "")
    }

    static func decodeGoogleClientJSON(_ data: Data) throws -> GoogleOAuthCredentials {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let client = (root["installed"] as? [String: Any]) ?? (root["web"] as? [String: Any]),
              let id = client["client_id"] as? String, !id.isEmpty else {
            throw YouTubeUploadError(message: "Keine gültige Google-OAuth-Client-ID gefunden.")
        }
        return .init(clientID: id, clientSecret: client["client_secret"] as? String ?? "")
    }
}

private final class OAuthLoopbackReceiver {
    private var listener: NWListener?
    private var continuation: CheckedContinuation<String, Error>?
    private var expectedState = ""
    private let queue = DispatchQueue(label: "de.blackstock.oauth.loopback")

    func start(state: String) async throws -> URL {
        expectedState = state
        let listener = try NWListener(using: .tcp, on: .any)
        self.listener = listener
        return try await withCheckedThrowingContinuation { continuation in
            var resumed = false
            listener.stateUpdateHandler = { status in
                switch status {
                case .ready:
                    guard !resumed, let port = listener.port else { return }
                    resumed = true
                    continuation.resume(returning: URL(string: "http://127.0.0.1:\(port.rawValue)/oauth2callback")!)
                case .failed(let error):
                    guard !resumed else { return }
                    resumed = true
                    continuation.resume(throwing: error)
                default: break
                }
            }
            listener.newConnectionHandler = { [weak self] connection in self?.handle(connection) }
            listener.start(queue: self.queue)
        }
    }

    func waitForCode() async throws -> String {
        try await withCheckedThrowingContinuation { continuation = $0 }
    }

    private func handle(_ connection: NWConnection) {
        connection.start(queue: queue)
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, _, _ in
            guard let self else { return }
            defer { connection.cancel() }
            guard let data, let request = String(data: data, encoding: .utf8), let line = request.components(separatedBy: "\r\n").first else {
                self.finish(.failure(YouTubeUploadError(message: "Ungültige OAuth-Antwort."))); return
            }
            let parts = line.split(separator: " ")
            guard parts.count >= 2, let components = URLComponents(string: "http://localhost" + String(parts[1])) else {
                self.finish(.failure(YouTubeUploadError(message: "OAuth-Rückgabe konnte nicht gelesen werden."))); return
            }
            let values = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") })
            if let error = values["error"] {
                self.respond(connection, ok: false)
                self.finish(.failure(YouTubeUploadError(message: "Google-Anmeldung: \(error)"))); return
            }
            guard values["state"] == expectedState, let code = values["code"], !code.isEmpty else {
                self.respond(connection, ok: false)
                self.finish(.failure(YouTubeUploadError(message: "OAuth-State oder Code ungültig."))); return
            }
            self.respond(connection, ok: true)
            self.finish(.success(code))
        }
    }

    private func respond(_ connection: NWConnection, ok: Bool) {
        let body = "<html><body style='font-family:-apple-system;padding:40px'><h2>\(ok ? "Blackstock ist verbunden." : "Verbindung fehlgeschlagen.")</h2><p>Du kannst dieses Fenster schließen und zu Blackstock zurückkehren.</p></body></html>"
        let payload = Data(body.utf8)
        let header = "HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: \(payload.count)\r\nConnection: close\r\n\r\n"
        connection.send(content: Data(header.utf8) + payload, completion: .contentProcessed { _ in })
    }

    private func finish(_ result: Result<String, Error>) {
        guard let continuation else { return }
        self.continuation = nil
        listener?.cancel(); listener = nil
        continuation.resume(with: result)
    }
}

@MainActor
final class GoogleOAuthService: ObservableObject {
    static let scopes = [
        "https://www.googleapis.com/auth/youtube.readonly",
        "https://www.googleapis.com/auth/youtube.upload",
        "https://www.googleapis.com/auth/youtube",
        "https://www.googleapis.com/auth/yt-analytics.readonly"
    ]

    @Published private(set) var tokens: OAuthTokenSet?
    private let keychain: KeychainStore
    private let session: URLSession
    private let tokenAccount = "google-oauth-token"

    init(keychain: KeychainStore = KeychainStore(), session: URLSession = .shared) {
        self.keychain = keychain
        self.session = session
        tokens = keychain.load(OAuthTokenSet.self, account: tokenAccount)
    }

    var connected: Bool { tokens != nil }

    func importCredentials(_ data: Data) throws {
        let credentials = try GoogleOAuthCredentials.decodeGoogleClientJSON(data)
        try keychain.save(StoredOAuthCredentials(clientID: credentials.clientID, clientSecret: credentials.clientSecret), account: "google-oauth-client")
    }

    func connect(credentials: GoogleOAuthCredentials) async throws {
        let verifier = Self.random(length: 64)
        let challenge = Data(SHA256.hash(data: Data(verifier.utf8))).urlSafeBase64
        let state = Self.random(length: 30)
        let receiver = OAuthLoopbackReceiver()
        let redirect = try await receiver.start(state: state)
        var components = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
        components.queryItems = [
            .init(name: "client_id", value: credentials.clientID), .init(name: "redirect_uri", value: redirect.absoluteString),
            .init(name: "response_type", value: "code"), .init(name: "scope", value: Self.scopes.joined(separator: " ")),
            .init(name: "access_type", value: "offline"), .init(name: "prompt", value: "consent"), .init(name: "state", value: state),
            .init(name: "code_challenge", value: challenge), .init(name: "code_challenge_method", value: "S256")
        ]
        guard let url = components.url else { throw YouTubeUploadError(message: "Google-Anmeldelink konnte nicht erstellt werden.") }
        NSWorkspace.shared.open(url)
        let code = try await receiver.waitForCode()
        let token = try await exchange(code: code, verifier: verifier, redirect: redirect, credentials: credentials)
        try keychain.save(token, account: tokenAccount)
        tokens = token
    }

    func disconnect() { keychain.delete(account: tokenAccount); tokens = nil }

    func accessToken(credentials: GoogleOAuthCredentials) async throws -> String {
        guard var token = tokens else { throw YouTubeUploadError(message: "YouTube ist nicht verbunden.") }
        if !token.needsRefresh { return token.accessToken }
        guard let refresh = token.refreshToken, !refresh.isEmpty else { disconnect(); throw YouTubeUploadError(message: "Google-Anmeldung abgelaufen. Bitte neu verbinden.") }
        var items = [URLQueryItem(name: "client_id", value: credentials.clientID), URLQueryItem(name: "refresh_token", value: refresh), URLQueryItem(name: "grant_type", value: "refresh_token")]
        if !credentials.clientSecret.isEmpty { items.append(.init(name: "client_secret", value: credentials.clientSecret)) }
        let object = try await tokenRequest(items)
        guard let access = object["access_token"] as? String else { throw YouTubeUploadError(message: "Zugriffstoken konnte nicht erneuert werden.") }
        token.accessToken = access
        token.expiresAt = Date().addingTimeInterval((object["expires_in"] as? NSNumber)?.doubleValue ?? 3600)
        token.scope = object["scope"] as? String ?? token.scope
        try keychain.save(token, account: tokenAccount); tokens = token
        return access
    }

    private func exchange(code: String, verifier: String, redirect: URL, credentials: GoogleOAuthCredentials) async throws -> OAuthTokenSet {
        var items = [URLQueryItem(name: "code", value: code), URLQueryItem(name: "client_id", value: credentials.clientID), URLQueryItem(name: "redirect_uri", value: redirect.absoluteString), URLQueryItem(name: "grant_type", value: "authorization_code"), URLQueryItem(name: "code_verifier", value: verifier)]
        if !credentials.clientSecret.isEmpty { items.append(.init(name: "client_secret", value: credentials.clientSecret)) }
        let object = try await tokenRequest(items)
        guard let access = object["access_token"] as? String else { throw YouTubeUploadError(message: "Google hat kein Zugriffstoken geliefert.") }
        return .init(accessToken: access, refreshToken: object["refresh_token"] as? String, expiresAt: Date().addingTimeInterval((object["expires_in"] as? NSNumber)?.doubleValue ?? 3600), scope: object["scope"] as? String ?? Self.scopes.joined(separator: " "))
    }

    private func tokenRequest(_ items: [URLQueryItem]) async throws -> [String: Any] {
        var components = URLComponents(); components.queryItems = items
        var request = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
        request.httpMethod = "POST"; request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data((components.percentEncodedQuery ?? "").utf8)
        let (data, response) = try await session.data(for: request)
        try Self.requireSuccess(response, data: data)
        return try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
    }

    static func requireSuccess(_ response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            let message = (root?["error"] as? [String: Any])?["message"] as? String ?? root?["error_description"] as? String ?? "Google/YouTube-Anfrage fehlgeschlagen."
            throw YouTubeUploadError(message: message)
        }
    }

    private static func random(length: Int) -> String { String((0..<length).map { _ in "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~".randomElement()! }) }
}

private extension Data {
    var urlSafeBase64: String { base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "") }
}
