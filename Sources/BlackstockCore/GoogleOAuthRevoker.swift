import Foundation

public enum GoogleOAuthRevocationError: Error, Sendable, Equatable {
    case emptyToken
    case invalidResponse
    case providerRejected(Int)
}

public struct GoogleOAuthRevoker: Sendable {
    public init() {}

    public func revoke(
        token: String,
        session: URLSession = .shared
    ) async throws {
        let request = try Self.request(token: token)
        let (_, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw GoogleOAuthRevocationError.invalidResponse
        }
        guard 200..<300 ~= http.statusCode else {
            throw GoogleOAuthRevocationError.providerRejected(http.statusCode)
        }
    }

    public static func request(token: String) throws -> URLRequest {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw GoogleOAuthRevocationError.emptyToken
        }

        var request = URLRequest(
            url: URL(string: "https://oauth2.googleapis.com/revoke")!
        )
        request.httpMethod = "POST"
        request.setValue(
            "application/x-www-form-urlencoded",
            forHTTPHeaderField: "Content-Type"
        )
        let encoded = trimmed.addingPercentEncoding(
            withAllowedCharacters: .alphanumerics
        ) ?? trimmed
        request.httpBody = Data("token=\(encoded)".utf8)
        return request
    }
}
