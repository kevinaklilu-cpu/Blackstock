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
