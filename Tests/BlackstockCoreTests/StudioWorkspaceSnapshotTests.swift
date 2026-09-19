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



    func testLegacyUnversionedWorkspaceLoadsAndIsMarkedForMigration() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let projectID = UUID()
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
        let store = ProjectWorkspaceStore(rootURL: root)
        let directory = try store.projectDirectory(projectID: projectID)
        let primaryURL = directory
            .appendingPathComponent("studio-workspace.json")

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(snapshot).write(
            to: primaryURL,
            options: [.atomic]
        )

        let result = try store.loadWithRecovery(projectID: projectID)

        XCTAssertEqual(result.snapshot, snapshot)
        XCTAssertFalse(result.recoveredFromBackup)
        XCTAssertEqual(
            result.migratedFromSchemaVersion,
            WorkspaceSchema.legacyUnversioned
        )
    }

    func testSavingAfterLegacyLoadWritesCurrentSchemaEnvelope() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let projectID = UUID()
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
        let store = ProjectWorkspaceStore(rootURL: root)
        let directory = try store.projectDirectory(projectID: projectID)
        let primaryURL = directory
            .appendingPathComponent("studio-workspace.json")

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(snapshot).write(
            to: primaryURL,
            options: [.atomic]
        )

        let loaded = try store.loadWithRecovery(projectID: projectID)
        let migrated = try XCTUnwrap(loaded.snapshot)
        try store.save(migrated)

        let data = try Data(contentsOf: primaryURL)
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data)
                as? [String: Any]
        )
        XCTAssertEqual(
            object["schemaVersion"] as? Int,
            WorkspaceSchema.current
        )
        XCTAssertNotNil(object["snapshot"])
    }

    func testFutureWorkspaceSchemaHardStopsWithoutBackup() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let projectID = UUID()
        let store = ProjectWorkspaceStore(rootURL: root)
        let directory = try store.projectDirectory(projectID: projectID)
        let primaryURL = directory
            .appendingPathComponent("studio-workspace.json")
        let futureVersion = WorkspaceSchema.current + 1
        try Data(
            """
            {"schemaVersion":\(futureVersion),"snapshot":{}}
            """.utf8
        ).write(to: primaryURL, options: [.atomic])

        XCTAssertThrowsError(
            try store.loadWithRecovery(projectID: projectID)
        ) { error in
            XCTAssertEqual(
                error as? WorkspaceMigrationError,
                .unsupportedFutureSchemaVersion(futureVersion)
            )
        }
    }

    func testWorkspaceRecoversLastValidatedBackupAfterPrimaryCorruption() throws {
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
            trimEnd: 8,
            transcript: nil,
            captionURL: nil,
            renderArtifact: nil,
            updatedAt: Date(timeIntervalSince1970: 6)
        )

        try store.save(first)
        try store.save(second)

        let projectDirectory = root
            .appendingPathComponent(projectID.uuidString, isDirectory: true)
        let primaryURL = projectDirectory
            .appendingPathComponent("studio-workspace.json")
        let backupURL = projectDirectory
            .appendingPathComponent("studio-workspace.backup.json")

        XCTAssertTrue(FileManager.default.fileExists(atPath: backupURL.path))
        try Data("{broken-json".utf8).write(
            to: primaryURL,
            options: [.atomic]
        )

        let recovered = try store.loadWithRecovery(projectID: projectID)

        XCTAssertTrue(recovered.recoveredFromBackup)
        XCTAssertEqual(recovered.snapshot, first)
    }

    func testInvalidPrimaryIsNeverPromotedOverExistingValidatedBackup() throws {
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
            trimStart: 2,
            trimEnd: 9,
            transcript: nil,
            captionURL: nil,
            renderArtifact: nil,
            updatedAt: Date(timeIntervalSince1970: 6)
        )

        try store.save(first)
        try store.save(second)

        let projectDirectory = root
            .appendingPathComponent(projectID.uuidString, isDirectory: true)
        let primaryURL = projectDirectory
            .appendingPathComponent("studio-workspace.json")
        try Data("not-json".utf8).write(to: primaryURL, options: [.atomic])

        try store.save(second)

        let backupURL = projectDirectory
            .appendingPathComponent("studio-workspace.backup.json")
        let backupBefore = try Data(contentsOf: backupURL)

        try Data("still-not-json".utf8).write(
            to: primaryURL,
            options: [.atomic]
        )
        try store.save(second)

        let backupAfter = try Data(contentsOf: backupURL)
        XCTAssertEqual(backupAfter, backupBefore)
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
