import XCTest
@testable import BlackstockCore

final class GrowthRecordStoreTests: XCTestCase {
    func testPublishedRecordAndLearningRoundTripAtomically() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "blackstock-growth-(UUID().uuidString)",
                isDirectory: true
            )
        defer { try? FileManager.default.removeItem(at: root) }

        let store = GrowthRecordStore(rootURL: root)
        let projectID = UUID()
        let record = PublishedVideoRecord(
            projectID: projectID,
            experimentID: nil,
            targetChannelID: "channel-A",
            youtubeVideoID: "video-A",
            publishedAt: Date(timeIntervalSince1970: 100)
        )
        try store.save(record: record)

        let loadedRecord = try store.loadRecord(
            projectID: projectID
        )
        XCTAssertEqual(loadedRecord, record)

        let learning = GrowthLearningRecord(
            publishedVideoID: record.id,
            experimentID: nil,
            observationIDs: [],
            facts: ["Fakt"],
            nextQuestion: "Frage?",
            createdAt: Date(timeIntervalSince1970: 200)
        )
        try store.save(
            learning: learning,
            projectID: projectID
        )

        XCTAssertEqual(
            try store.loadLearning(projectID: projectID),
            learning
        )
    }

    func testMissingGrowthFilesReturnNil() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "blackstock-growth-(UUID().uuidString)",
                isDirectory: true
            )
        defer { try? FileManager.default.removeItem(at: root) }

        let store = GrowthRecordStore(rootURL: root)
        let projectID = UUID()

        XCTAssertNil(
            try store.loadRecord(projectID: projectID)
        )
        XCTAssertNil(
            try store.loadLearning(projectID: projectID)
        )
    }
    func testLegacyPublishedRecordIsMigratedToVersionedEnvelope() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let projectID = UUID()
        let store = GrowthRecordStore(rootURL: root)
        let directory = try store.projectDirectory(projectID: projectID)
        let url = directory.appendingPathComponent("published-video.json")
        let record = PublishedVideoRecord(
            projectID: projectID,
            experimentID: nil,
            targetChannelID: "channel-A",
            youtubeVideoID: "video-A",
            publishedAt: Date(timeIntervalSince1970: 100)
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(record).write(to: url, options: [.atomic])

        XCTAssertEqual(
            try store.loadRecord(projectID: projectID),
            record
        )

        let data = try Data(contentsOf: url)
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data)
                as? [String: Any]
        )
        XCTAssertEqual(
            object["schemaVersion"] as? Int,
            GrowthRecordStoreSchema.current
        )
        XCTAssertNotNil(object["value"])
    }


    func testPublishedRecordRecoversLastValidatedBackupAfterPrimaryCorruption() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let projectID = UUID()
        let store = GrowthRecordStore(rootURL: root)
        let first = PublishedVideoRecord(
            projectID: projectID,
            experimentID: nil,
            targetChannelID: "channel-A",
            youtubeVideoID: "video-A",
            publishedAt: Date(timeIntervalSince1970: 100)
        )
        let second = PublishedVideoRecord(
            projectID: projectID,
            experimentID: nil,
            targetChannelID: "channel-A",
            youtubeVideoID: "video-B",
            publishedAt: Date(timeIntervalSince1970: 200)
        )

        try store.save(record: first)
        try store.save(record: second)

        let directory = try store.projectDirectory(projectID: projectID)
        let primaryURL = directory.appendingPathComponent(
            "published-video.json"
        )
        let backupURL = directory.appendingPathComponent(
            "published-video.backup.json"
        )
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: backupURL.path)
        )

        try Data("broken".utf8).write(
            to: primaryURL,
            options: [.atomic]
        )

        let recovered = try store.loadRecordWithRecovery(
            projectID: projectID
        )
        XCTAssertTrue(recovered.recoveredFromBackup)
        XCTAssertEqual(recovered.value, first)
    }

    func testGrowthLearningRecoversLastValidatedBackupAfterPrimaryCorruption() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let projectID = UUID()
        let publishedVideoID = UUID()
        let store = GrowthRecordStore(rootURL: root)
        let first = GrowthLearningRecord(
            publishedVideoID: publishedVideoID,
            experimentID: nil,
            observationIDs: [],
            facts: ["Erster Fakt"],
            nextQuestion: "Erste Frage?",
            createdAt: Date(timeIntervalSince1970: 100)
        )
        let second = GrowthLearningRecord(
            publishedVideoID: publishedVideoID,
            experimentID: nil,
            observationIDs: [],
            facts: ["Zweiter Fakt"],
            nextQuestion: "Zweite Frage?",
            createdAt: Date(timeIntervalSince1970: 200)
        )

        try store.save(learning: first, projectID: projectID)
        try store.save(learning: second, projectID: projectID)

        let directory = try store.projectDirectory(projectID: projectID)
        let primaryURL = directory.appendingPathComponent(
            "growth-learning.json"
        )
        let backupURL = directory.appendingPathComponent(
            "growth-learning.backup.json"
        )
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: backupURL.path)
        )

        try Data("broken".utf8).write(
            to: primaryURL,
            options: [.atomic]
        )

        let recovered = try store.loadLearningWithRecovery(
            projectID: projectID
        )
        XCTAssertTrue(recovered.recoveredFromBackup)
        XCTAssertEqual(recovered.value, first)
    }

    func testInvalidGrowthPrimaryNeverOverwritesValidatedBackup() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let projectID = UUID()
        let store = GrowthRecordStore(rootURL: root)
        let first = PublishedVideoRecord(
            projectID: projectID,
            experimentID: nil,
            targetChannelID: "channel-A",
            youtubeVideoID: "video-A",
            publishedAt: Date(timeIntervalSince1970: 100)
        )
        let second = PublishedVideoRecord(
            projectID: projectID,
            experimentID: nil,
            targetChannelID: "channel-A",
            youtubeVideoID: "video-B",
            publishedAt: Date(timeIntervalSince1970: 200)
        )

        try store.save(record: first)
        try store.save(record: second)

        let directory = try store.projectDirectory(projectID: projectID)
        let primaryURL = directory.appendingPathComponent(
            "published-video.json"
        )
        let backupURL = directory.appendingPathComponent(
            "published-video.backup.json"
        )
        let backupBefore = try Data(contentsOf: backupURL)

        try Data("not-json".utf8).write(
            to: primaryURL,
            options: [.atomic]
        )
        try store.save(record: second)

        XCTAssertEqual(
            try Data(contentsOf: backupURL),
            backupBefore
        )
    }

    func testFutureGrowthSchemaHardStops() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let projectID = UUID()
        let store = GrowthRecordStore(rootURL: root)
        let directory = try store.projectDirectory(projectID: projectID)
        let url = directory.appendingPathComponent("published-video.json")
        let futureVersion = GrowthRecordStoreSchema.current + 1

        try Data(
            """
            {"schemaVersion":\(futureVersion),"value":{}}
            """.utf8
        ).write(to: url, options: [.atomic])

        XCTAssertThrowsError(
            try store.loadRecord(projectID: projectID)
        ) { error in
            XCTAssertEqual(
                error as? GrowthRecordStoreError,
                .unsupportedFutureSchemaVersion(futureVersion)
            )
        }
    }


}
