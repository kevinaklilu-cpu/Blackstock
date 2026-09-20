import CryptoKit
import Foundation

public enum ProductionUpdateURLPolicy {
    public static func allows(
        _ url: URL
    ) -> Bool {
        guard url.scheme?.lowercased() == "https",
              var host = url.host?.lowercased(),
              !host.isEmpty,
              url.user == nil,
              url.password == nil,
              url.fragment == nil else {
            return false
        }

        while host.hasSuffix(".") {
            host.removeLast()
        }
        guard !host.isEmpty else {
            return false
        }

        return host != "localhost"
            && host != "::1"
            && !host.hasPrefix("127.")
            && !host.hasSuffix(".local")
            && !host.hasSuffix(".invalid")
            && !host.hasSuffix(".example")
            && !host.hasSuffix(".test")
    }
}

public struct BlackstockUpdateManifest: Codable, Sendable, Equatable {
    public let version: String
    public let build: Int
    public let packageURL: URL
    public let sha256: String
    public let sourceCommitSHA: String
    public let publishedAt: Date
    public let signature: String

    public init(
        version: String,
        build: Int,
        packageURL: URL,
        sha256: String,
        sourceCommitSHA: String,
        publishedAt: Date,
        signature: String
    ) {
        self.version = version
        self.build = build
        self.packageURL = packageURL
        self.sha256 = sha256.lowercased()
        self.sourceCommitSHA = sourceCommitSHA.lowercased()
        self.publishedAt = publishedAt
        self.signature = signature
    }

    public var signedPayload: Data {
        let timestamp = ISO8601DateFormatter().string(from: publishedAt)
        return Data(
            [
                version,
                String(build),
                packageURL.absoluteString,
                sha256.lowercased(),
                sourceCommitSHA.lowercased(),
                timestamp
            ]
            .joined(separator: "\n")
            .utf8
        )
    }
}

public enum UpdateManifestValidationError: Error, Sendable, Equatable {
    case invalidVersion
    case invalidBuild
    case packageURLMustUseHTTPS
    case invalidSHA256
    case invalidSourceCommitSHA
    case invalidPublicKey
    case invalidSignatureEncoding
    case invalidSignature
}

public enum UpdateAvailability: Sendable, Equatable {
    case upToDate
    case updateAvailable(BlackstockUpdateManifest)
}

public struct UpdateManifestVerifier: Sendable {
    public init() {}

    public func verify(
        _ manifest: BlackstockUpdateManifest,
        publicKeyBase64: String
    ) throws {
        guard Self.parseVersion(manifest.version) != nil else {
            throw UpdateManifestValidationError.invalidVersion
        }
        guard manifest.build > 0 else {
            throw UpdateManifestValidationError.invalidBuild
        }
        guard ProductionUpdateURLPolicy.allows(
            manifest.packageURL
        ) else {
            throw UpdateManifestValidationError.packageURLMustUseHTTPS
        }
        guard manifest.sha256.count == 64,
              manifest.sha256.allSatisfy({ $0.isHexDigit }) else {
            throw UpdateManifestValidationError.invalidSHA256
        }
        guard manifest.sourceCommitSHA.count == 40,
              manifest.sourceCommitSHA.allSatisfy({ $0.isHexDigit }) else {
            throw UpdateManifestValidationError.invalidSourceCommitSHA
        }
        guard let publicKeyData = Data(base64Encoded: publicKeyBase64),
              let publicKey = try? Curve25519.Signing.PublicKey(
                rawRepresentation: publicKeyData
              ) else {
            throw UpdateManifestValidationError.invalidPublicKey
        }
        guard let signature = Data(base64Encoded: manifest.signature) else {
            throw UpdateManifestValidationError.invalidSignatureEncoding
        }
        guard publicKey.isValidSignature(
            signature,
            for: manifest.signedPayload
        ) else {
            throw UpdateManifestValidationError.invalidSignature
        }
    }

    public func availability(
        manifest: BlackstockUpdateManifest,
        currentVersion: String,
        currentBuild: Int
    ) throws -> UpdateAvailability {
        guard let remote = Self.parseVersion(manifest.version),
              let local = Self.parseVersion(currentVersion) else {
            throw UpdateManifestValidationError.invalidVersion
        }

        if remote > local {
            return .updateAvailable(manifest)
        }
        if remote == local && manifest.build > currentBuild {
            return .updateAvailable(manifest)
        }
        return .upToDate
    }

    static func parseVersion(_ value: String) -> [Int]? {
        let parts = value.split(separator: ".", omittingEmptySubsequences: false)
        guard !parts.isEmpty,
              parts.count <= 4 else {
            return nil
        }
        var numbers: [Int] = []
        for part in parts {
            guard !part.isEmpty,
                  part.allSatisfy({ $0.isNumber }),
                  let number = Int(part) else {
                return nil
            }
            numbers.append(number)
        }
        while numbers.count < 4 {
            numbers.append(0)
        }
        return numbers
    }
}

private extension Array where Element == Int {
    static func > (lhs: [Int], rhs: [Int]) -> Bool {
        for (left, right) in zip(lhs, rhs) {
            if left != right {
                return left > right
            }
        }
        return lhs.count > rhs.count
    }
}
