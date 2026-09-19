import Foundation

public struct OAuthClientBindingPolicy: Sendable {
    public init() {}

    public func requiresCredentialInvalidation(
        previousClientID: String,
        nextClientID: String
    ) -> Bool {
        normalize(previousClientID) != normalize(nextClientID)
    }

    private func normalize(_ value: String) -> String {
        value.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
    }
}
