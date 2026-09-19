import Foundation
import XCTest
@testable import BlackstockCore

final class PrivacyControlsTests: XCTestCase {
    func testGoogleRevokeRequestUsesOfficialHTTPSPostEndpoint() throws {
        let request = try GoogleOAuthRevoker.request(
            token: "refresh token"
        )
        XCTAssertEqual(
            request.url?.absoluteString,
            "https://oauth2.googleapis.com/revoke"
        )
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(
            request.value(forHTTPHeaderField: "Content-Type"),
            "application/x-www-form-urlencoded"
        )
        XCTAssertEqual(
            String(data: try XCTUnwrap(request.httpBody), encoding: .utf8),
            "token=refresh%20token"
        )
    }

    func testGoogleRevokeRejectsEmptyToken() {
        XCTAssertThrowsError(
            try GoogleOAuthRevoker.request(token: "   ")
        ) {
            XCTAssertEqual(
                $0 as? GoogleOAuthRevocationError,
                .emptyToken
            )
        }
    }

    func testPrivacyExportCopiesLocalDataAndNeverAddsKeychainSecrets() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: destination,
            withIntermediateDirectories: true
        )
        try Data("workspace".utf8).write(
            to: root.appendingPathComponent("workspace.json")
        )
        let defaults = try PropertyListSerialization.data(
            fromPropertyList: ["blackstock.firstRun.complete": true],
            format: .xml,
            options: 0
        )

        let report = try PrivacyDataExporter().export(
            applicationSupportRoot: root,
            userDefaultsPlist: defaults,
            destinationDirectory: destination,
            exportID: UUID(
                uuidString: "00000000-0000-0000-0000-000000000001"
            )!
        )

        XCTAssertTrue(report.copiedLocalData)
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: report.exportURL
                    .appendingPathComponent("LocalData/workspace.json")
                    .path
            )
        )
        let readme = try String(
            contentsOf: report.exportURL.appendingPathComponent("README.txt"),
            encoding: .utf8
        )
        XCTAssertTrue(readme.contains("Nicht enthalten"))
        XCTAssertTrue(readme.contains("OAuth Refresh Tokens"))
    }

    func testRetentionPurgesOnlyExpiredBlackstockPackages() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )

        let old = directory.appendingPathComponent("Blackstock-old.pkg")
        let fresh = directory.appendingPathComponent("Blackstock-new.pkg")
        let unrelated = directory.appendingPathComponent("Other.pkg")
        try Data().write(to: old)
        try Data().write(to: fresh)
        try Data().write(to: unrelated)

        let now = Date(timeIntervalSince1970: 2_000_000)
        try FileManager.default.setAttributes(
            [.modificationDate: now.addingTimeInterval(-90_000)],
            ofItemAtPath: old.path
        )
        try FileManager.default.setAttributes(
            [.modificationDate: now.addingTimeInterval(-60)],
            ofItemAtPath: fresh.path
        )
        try FileManager.default.setAttributes(
            [.modificationDate: now.addingTimeInterval(-90_000)],
            ofItemAtPath: unrelated.path
        )

        let removed = try PrivacyRetentionEnforcer()
            .purgeExpiredUpdatePackages(
                in: directory,
                now: now
            )

        XCTAssertEqual(removed, 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: old.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: fresh.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: unrelated.path))
    }

    func testCanonicalRetentionPolicyCoversAllPrivacyClasses() {
        let kinds = Set(
            PrivacyRetentionPolicy.canonical.map(\.retention)
        )
        XCTAssertTrue(kinds.contains(.untilExplicitDeletion))
        XCTAssertTrue(kinds.contains(.untilRevokedOrDeleted))
        XCTAssertTrue(kinds.contains(.sessionOnly))
        XCTAssertTrue(kinds.contains(.hours24))
        XCTAssertTrue(kinds.contains(.userControlled))
    }
}
