import XCTest
@testable import BlackstockCore

final class LocalDataCleanerTests: XCTestCase {
    func testDeletesEntireLocalDataDirectoryRecursively() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let projects = root
            .appendingPathComponent("Projects", isDirectory: true)
        let growth = root
            .appendingPathComponent("Growth", isDirectory: true)

        try FileManager.default.createDirectory(
            at: projects,
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: growth,
            withIntermediateDirectories: true
        )
        try Data("project".utf8).write(
            to: projects.appendingPathComponent("workspace.json")
        )
        try Data("growth".utf8).write(
            to: growth.appendingPathComponent("learning.json")
        )

        let report = try LocalDataCleaner()
            .deleteDirectoryIfPresent(root)

        XCTAssertTrue(report.rootExisted)
        XCTAssertEqual(report.fileCount, 2)
        XCTAssertGreaterThanOrEqual(report.directoryCount, 3)
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: root.path)
        )
    }

    func testMissingDirectoryIsANoOp() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)

        let report = try LocalDataCleaner()
            .deleteDirectoryIfPresent(root)

        XCTAssertFalse(report.rootExisted)
        XCTAssertEqual(report.fileCount, 0)
        XCTAssertEqual(report.directoryCount, 0)
    }

    func testRejectsNonFileURL() {
        XCTAssertThrowsError(
            try LocalDataCleaner().deleteDirectoryIfPresent(
                URL(string: "https://example.com/blackstock")!
            )
        ) {
            XCTAssertEqual(
                $0 as? LocalDataDeletionError,
                .nonFileURL
            )
        }
    }
}
