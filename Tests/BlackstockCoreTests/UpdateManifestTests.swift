import CryptoKit
import XCTest
@testable import BlackstockCore

final class UpdateManifestTests: XCTestCase {
    private let sourceCommitSHA =
        String(repeating: "1", count: 40)
    func testValidSignedHTTPSManifestIsAccepted() throws {
        let privateKey = Curve25519.Signing.PrivateKey()
        let publishedAt = Date(timeIntervalSince1970: 1_700_000_000)
        var manifest = BlackstockUpdateManifest(
            version: "1.2.3",
            build: 42,
            packageURL: URL(string: "https://updates.example.com/Blackstock.pkg")!,
            sha256: String(repeating: "a", count: 64),
            sourceCommitSHA: sourceCommitSHA,
            publishedAt: publishedAt,
            signature: ""
        )
        let signature = try privateKey.signature(
            for: manifest.signedPayload
        )
        manifest = BlackstockUpdateManifest(
            version: manifest.version,
            build: manifest.build,
            packageURL: manifest.packageURL,
            sha256: manifest.sha256,
            sourceCommitSHA: sourceCommitSHA,
            publishedAt: manifest.publishedAt,
            signature: signature.base64EncodedString()
        )

        XCTAssertNoThrow(
            try UpdateManifestVerifier().verify(
                manifest,
                publicKeyBase64: privateKey.publicKey
                    .rawRepresentation
                    .base64EncodedString()
            )
        )
    }

    func testHTTPPackageURLIsRejectedEvenWithValidSignature() throws {
        let privateKey = Curve25519.Signing.PrivateKey()
        let publishedAt = Date(timeIntervalSince1970: 1_700_000_000)
        var manifest = BlackstockUpdateManifest(
            version: "1.2.3",
            build: 42,
            packageURL: URL(string: "http://updates.example.com/Blackstock.pkg")!,
            sha256: String(repeating: "b", count: 64),
            sourceCommitSHA: sourceCommitSHA,
            publishedAt: publishedAt,
            signature: ""
        )
        manifest = BlackstockUpdateManifest(
            version: manifest.version,
            build: manifest.build,
            packageURL: manifest.packageURL,
            sha256: manifest.sha256,
            sourceCommitSHA: sourceCommitSHA,
            publishedAt: manifest.publishedAt,
            signature: try privateKey.signature(
                for: manifest.signedPayload
            ).base64EncodedString()
        )

        XCTAssertThrowsError(
            try UpdateManifestVerifier().verify(
                manifest,
                publicKeyBase64: privateKey.publicKey
                    .rawRepresentation
                    .base64EncodedString()
            )
        ) {
            XCTAssertEqual(
                $0 as? UpdateManifestValidationError,
                .packageURLMustUseHTTPS
            )
        }
    }

    func testTamperedManifestSignatureIsRejected() throws {
        let privateKey = Curve25519.Signing.PrivateKey()
        let publishedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let unsigned = BlackstockUpdateManifest(
            version: "1.2.3",
            build: 42,
            packageURL: URL(string: "https://updates.example.com/Blackstock.pkg")!,
            sha256: String(repeating: "c", count: 64),
            sourceCommitSHA: sourceCommitSHA,
            publishedAt: publishedAt,
            signature: ""
        )
        let signature = try privateKey.signature(
            for: unsigned.signedPayload
        )
        let tampered = BlackstockUpdateManifest(
            version: "1.2.4",
            build: 42,
            packageURL: unsigned.packageURL,
            sha256: unsigned.sha256,
            sourceCommitSHA: sourceCommitSHA,
            publishedAt: publishedAt,
            signature: signature.base64EncodedString()
        )

        XCTAssertThrowsError(
            try UpdateManifestVerifier().verify(
                tampered,
                publicKeyBase64: privateKey.publicKey
                    .rawRepresentation
                    .base64EncodedString()
            )
        ) {
            XCTAssertEqual(
                $0 as? UpdateManifestValidationError,
                .invalidSignature
            )
        }
    }

    func testAvailabilityUsesSemanticVersionThenBuild() throws {
        let manifest = BlackstockUpdateManifest(
            version: "1.3.0",
            build: 1,
            packageURL: URL(string: "https://updates.example.com/Blackstock.pkg")!,
            sha256: String(repeating: "d", count: 64),
            sourceCommitSHA: sourceCommitSHA,
            publishedAt: Date(timeIntervalSince1970: 1_700_000_000),
            signature: "unused"
        )

        XCTAssertEqual(
            try UpdateManifestVerifier().availability(
                manifest: manifest,
                currentVersion: "1.2.9",
                currentBuild: 99
            ),
            .updateAvailable(manifest)
        )

        let sameVersion = BlackstockUpdateManifest(
            version: "1.2.9",
            build: 100,
            packageURL: manifest.packageURL,
            sha256: manifest.sha256,
            sourceCommitSHA: sourceCommitSHA,
            publishedAt: manifest.publishedAt,
            signature: "unused"
        )
        XCTAssertEqual(
            try UpdateManifestVerifier().availability(
                manifest: sameVersion,
                currentVersion: "1.2.9",
                currentBuild: 99
            ),
            .updateAvailable(sameVersion)
        )
    }
}
