import CryptoKit
import XCTest
@testable import BlackstockCore

final class UpdatePackageIntegrityVerifierTests: XCTestCase {
    func testMatchingSHA256Passes() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("pkg")
        defer { try? FileManager.default.removeItem(at: url) }

        let data = Data("blackstock-update".utf8)
        try data.write(to: url)
        let expected = SHA256.hash(data: data)
            .map { String(format: "%02x", $0) }
            .joined()

        XCTAssertNoThrow(
            try UpdatePackageIntegrityVerifier().verify(
                fileURL: url,
                expectedSHA256: expected
            )
        )
    }

    func testTamperedPackageIsRejected() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("pkg")
        defer { try? FileManager.default.removeItem(at: url) }

        try Data("tampered".utf8).write(to: url)
        let expected = SHA256.hash(data: Data("expected".utf8))
            .map { String(format: "%02x", $0) }
            .joined()

        XCTAssertThrowsError(
            try UpdatePackageIntegrityVerifier().verify(
                fileURL: url,
                expectedSHA256: expected
            )
        ) { error in
            guard case .hashMismatch(let expectedHash, let actualHash)
                = error as? UpdatePackageIntegrityError else {
                return XCTFail("hashMismatch expected, got \(error)")
            }
            XCTAssertEqual(expectedHash, expected)
            XCTAssertNotEqual(actualHash, expected)
        }
    }

    func testMissingPackageIsRejected() {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("pkg")

        XCTAssertThrowsError(
            try UpdatePackageIntegrityVerifier().verify(
                fileURL: url,
                expectedSHA256: String(repeating: "a", count: 64)
            )
        ) {
            XCTAssertEqual(
                $0 as? UpdatePackageIntegrityError,
                .fileMissing
            )
        }
    }
}
