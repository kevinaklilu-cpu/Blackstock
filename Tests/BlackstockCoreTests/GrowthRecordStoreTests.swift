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
}
