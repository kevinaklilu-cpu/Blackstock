import XCTest
@testable import BlackstockCore

final class StudioWorkspaceSnapshotTests: XCTestCase {
    func testWorkspaceSnapshotRoundTripsAtomically() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let projectID = UUID()
        let store = ProjectWorkspaceStore(rootURL: root)
        let snapshot = StudioWorkspaceSnapshot(
            projectID: projectID,
            mediaAsset: nil,
            editGraph: EditGraph(createdAt: Date(timeIntervalSince1970: 1)),
            activityLedger: ActivityLedger(),
            storyboard: StoryboardPlan(
                projectID: projectID,
                updatedAt: Date(timeIntervalSince1970: 2)
            ),
            trimStart: 0,
            trimEnd: 10,
            transcript: nil,
            captionURL: nil,
            renderArtifact: nil,
            updatedAt: Date(timeIntervalSince1970: 3)
        )

        try store.save(snapshot)
        let restored = try XCTUnwrap(
            store.load(projectID: projectID)
        )

        XCTAssertEqual(restored, snapshot)
    }

    func testCorruptedPrimaryFallsBackToBackup() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let projectID = UUID()
        let store = ProjectWorkspaceStore(rootURL: root)
        let first = StudioWorkspaceSnapshot(
            projectID: projectID,
            mediaAsset: nil,
            editGraph: EditGraph(createdAt: Date(timeIntervalSince1970: 1)),
            activityLedger: ActivityLedger(),
            storyboard: StoryboardPlan(
                projectID: projectID,
                updatedAt: Date(timeIntervalSince1970: 2)
            ),
            trimStart: 0,
            trimEnd: 10,
            transcript: nil,
            captionURL: nil,
            renderArtifact: nil,
            updatedAt: Date(timeIntervalSince1970: 3)
        )
        let second = StudioWorkspaceSnapshot(
            projectID: projectID,
            mediaAsset: nil,
            editGraph: EditGraph(createdAt: Date(timeIntervalSince1970: 4)),
            activityLedger: ActivityLedger(),
            storyboard: StoryboardPlan(
                projectID: projectID,
                updatedAt: Date(timeIntervalSince1970: 5)
            ),
            trimStart: 1,
            trimEnd: 9,
            transcript: nil,
            captionURL: nil,
            renderArtifact: nil,
            updatedAt: Date(timeIntervalSince1970: 6)
        )

        try store.save(first)
        try store.save(second)

        let directory = try store.projectDirectory(projectID: projectID)
        let primary = directory.appendingPathComponent("studio-workspace.json")
        try Data("{not-json".utf8).write(to: primary, options: [.atomic])

        let recovered = try XCTUnwrap(
            store.loadResult(projectID: projectID)
        )

        XCTAssertEqual(recovered.source, .backup)
        XCTAssertEqual(recovered.snapshot, first)
    }

    func testLegacyRawSnapshotStillLoadsForMigration() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let projectID = UUID()
        let store = ProjectWorkspaceStore(rootURL: root)
        let snapshot = StudioWorkspaceSnapshot(
            projectID: projectID,
            mediaAsset: nil,
            editGraph: EditGraph(createdAt: Date(timeIntervalSince1970: 1)),
            activityLedger: ActivityLedger(),
            storyboard: StoryboardPlan(
                projectID: projectID,
                updatedAt: Date(timeIntervalSince1970: 2)
            ),
            trimStart: 0,
            trimEnd: 10,
            transcript: nil,
            captionURL: nil,
            renderArtifact: nil,
            updatedAt: Date(timeIntervalSince1970: 3)
        )

        let directory = try store.projectDirectory(projectID: projectID)
        let primary = directory.appendingPathComponent("studio-workspace.json")
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(snapshot).write(to: primary, options: [.atomic])

        let loaded = try XCTUnwrap(store.loadResult(projectID: projectID))
        XCTAssertEqual(loaded.source, .legacy)
        XCTAssertEqual(loaded.snapshot, snapshot)
    }

    func testImportedMediaIsCopiedIntoProjectWorkspace() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let source = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("mov")
        defer {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: source)
        }

        try Data("media".utf8).write(to: source)
        let projectID = UUID()
        let assetID = UUID()
        let destination = try ProjectWorkspaceStore(
            rootURL: root
        ).importMedia(
            sourceURL: source,
            projectID: projectID,
            assetID: assetID
        )

        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: destination.path
            )
        )
        XCTAssertTrue(
            destination.path.contains(projectID.uuidString)
        )
        XCTAssertNotEqual(destination, source)
    }
}
