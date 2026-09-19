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
    func testImportedPackagingAssetsAreCopiedIntoDurableProjectFolders() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let thumbnailSource = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("png")
        let captionSource = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("vtt")
        defer {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: thumbnailSource)
            try? FileManager.default.removeItem(at: captionSource)
        }

        try Data("image".utf8).write(to: thumbnailSource)
        try Data("WEBVTT".utf8).write(to: captionSource)

        let projectID = UUID()
        let store = ProjectWorkspaceStore(rootURL: root)
        let thumbnail = try store.importPackagingAsset(
            sourceURL: thumbnailSource,
            projectID: projectID,
            assetID: UUID(),
            kind: .thumbnail
        )
        let caption = try store.importPackagingAsset(
            sourceURL: captionSource,
            projectID: projectID,
            assetID: UUID(),
            kind: .caption
        )

        XCTAssertTrue(FileManager.default.fileExists(atPath: thumbnail.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: caption.path))
        XCTAssertTrue(thumbnail.path.contains("Thumbnails"))
        XCTAssertTrue(caption.path.contains("Captions"))
        XCTAssertTrue(thumbnail.path.contains(projectID.uuidString))
        XCTAssertTrue(caption.path.contains(projectID.uuidString))
        XCTAssertNotEqual(thumbnail, thumbnailSource)
        XCTAssertNotEqual(caption, captionSource)
    }


    func testPublishPreparationRoundTripsInProjectWorkspace() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let projectID = UUID()
        let renderID = UUID()
        let package = PublishPackage(
            projectID: projectID,
            targetChannelID: "channel-A",
            renderArtifactID: renderID,
            metadata: YouTubeUploadMetadata(
                title: "Video",
                description: "Beschreibung",
                privacyStatus: .privateVideo,
                selfDeclaredMadeForKids: false
            ),
            thumbnail: nil,
            captions: []
        )
        let review = CreatorQualityReview(
            projectID: projectID,
            stage: .review,
            evidence: [],
            findings: [],
            reviewedAt: Date(timeIntervalSince1970: 4)
        )
        let snapshot = PublishPreparationSnapshot(
            package: package,
            qualityReview: review,
            packagingVariants: PackagingVariantSet(),
            savedAt: Date(timeIntervalSince1970: 5)
        )
        let store = ProjectWorkspaceStore(rootURL: root)

        try store.savePublishPreparation(snapshot)
        let restored = try XCTUnwrap(
            store.loadPublishPreparation(projectID: projectID)
        )

        XCTAssertEqual(restored, snapshot)
    }

}
