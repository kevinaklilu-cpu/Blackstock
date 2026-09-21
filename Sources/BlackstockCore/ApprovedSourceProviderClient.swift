import Foundation

public struct ApprovedSourceProviderRequest:
    Codable,
    Sendable,
    Equatable {
    public let sourceURL: URL
    public let externalID: String?
    public let provider: String

    public init(
        sourceURL: URL,
        externalID: String?,
        provider: String
    ) {
        self.sourceURL = sourceURL
        self.externalID = externalID
        self.provider = provider
    }
}

public struct ApprovedSourceProviderResponse:
    Codable,
    Sendable,
    Equatable {
    public let mediaURL: URL
    public let expiresAt: Date?

    public init(
        mediaURL: URL,
        expiresAt: Date?
    ) {
        self.mediaURL = mediaURL
        self.expiresAt = expiresAt
    }
}

public enum ApprovedSourceProviderError:
    Error,
    LocalizedError,
    Equatable {
    case invalidResponse
    case rejected(Int)
    case insecureMediaURL

    public var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Der Source Provider hat keine gültige Medienquelle geliefert."
        case .rejected(let status):
            return "Der Source Provider hat die Anfrage abgelehnt (HTTP \(status))."
        case .insecureMediaURL:
            return "Der Source Provider hat keine sichere HTTPS-Medienquelle geliefert."
        }
    }
}

public struct ApprovedSourceProviderClient: Sendable {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func resolve(
        source: MediaSourceReference,
        endpointURL: URL,
        bearerToken: String?
    ) async throws -> ApprovedSourceProviderResponse {
        guard endpointURL.scheme?.lowercased() == "https" else {
            throw ApprovedSourceProviderError.invalidResponse
        }

        var request = URLRequest(url: endpointURL)
        request.httpMethod = "POST"
        request.setValue(
            "application/json",
            forHTTPHeaderField: "Content-Type"
        )
        request.setValue(
            "application/json",
            forHTTPHeaderField: "Accept"
        )

        let token = bearerToken?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let token, !token.isEmpty {
            request.setValue(
                "Bearer " + token,
                forHTTPHeaderField: "Authorization"
            )
        }

        request.httpBody = try JSONEncoder().encode(
            ApprovedSourceProviderRequest(
                sourceURL: source.pageURL,
                externalID: source.externalID,
                provider: source.provider.rawValue
            )
        )

        let (data, response) = try await session.data(
            for: request
        )
        guard let http = response as? HTTPURLResponse else {
            throw ApprovedSourceProviderError.invalidResponse
        }
        guard (200...299).contains(http.statusCode) else {
            throw ApprovedSourceProviderError.rejected(
                http.statusCode
            )
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let resolved = try decoder.decode(
            ApprovedSourceProviderResponse.self,
            from: data
        )
        guard resolved.mediaURL.scheme?.lowercased()
                == "https" else {
            throw ApprovedSourceProviderError.insecureMediaURL
        }
        return resolved
    }
}
