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
            publishedAt: Date(timeIntervalSince1970: 1_789_123_456.123456)
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
            createdAt: Date(timeIntervalSince1970: 1_789_123_500.654321)
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


    func testVersionTwoEnvelopeWithISO8601DatesMigratesToCurrentSchema() throws {
        struct LegacyEnvelope<Value: Codable>: Codable {
            let schemaVersion: Int
            let value: Value
        }

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
        let envelope = LegacyEnvelope(
            schemaVersion: 2,
            value: record
        )
        try encoder.encode(envelope).write(
            to: url,
            options: [.atomic]
        )

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
    }

    func testVersionThreeUnixTimestampEnvelopeMigratesExactly() throws {
        struct LegacyEnvelope<Value: Codable>: Codable {
            let schemaVersion: Int
            let value: Value
        }

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
            publishedAt: Date(
                timeIntervalSince1970: 1_789_123_456.125
            )
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(date.timeIntervalSince1970)
        }
        let envelope = LegacyEnvelope(
            schemaVersion: 3,
            value: record
        )
        try encoder.encode(envelope).write(
            to: url,
            options: [.atomic]
        )

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
