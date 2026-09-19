import CryptoKit
import Foundation

public enum UpdatePackageIntegrityError: Error, Sendable, Equatable {
    case fileMissing
    case invalidExpectedSHA256
    case hashMismatch(expected: String, actual: String)
}

public struct UpdatePackageIntegrityVerifier: Sendable {
    public init() {}

    public func verify(
        fileURL: URL,
        expectedSHA256: String
    ) throws {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            throw UpdatePackageIntegrityError.fileMissing
        }

        let expected = expectedSHA256.lowercased()
        guard expected.count == 64,
              expected.allSatisfy({ $0.isHexDigit }) else {
            throw UpdatePackageIntegrityError.invalidExpectedSHA256
        }

        let data = try Data(contentsOf: fileURL, options: .mappedIfSafe)
        let digest = SHA256.hash(data: data)
        let actual = digest.map {
            String(format: "%02x", $0)
        }.joined()

        guard actual == expected else {
            throw UpdatePackageIntegrityError.hashMismatch(
                expected: expected,
                actual: actual
            )
        }
    }
}
