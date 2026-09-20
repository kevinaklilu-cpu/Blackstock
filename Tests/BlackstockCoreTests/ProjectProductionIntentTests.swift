import XCTest
@testable import BlackstockCore

final class ProjectProductionIntentTests: XCTestCase {
    func testClipIntentRemainsExplicitAcrossPersistence() throws {
        let record = ProjectProductionIntent(
            projectID: UUID(),
            sourceID: UUID(),
            kind: .clipFromOpportunity,
            createdAt: Date(timeIntervalSince1970: 1_790_000_000)
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(record)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(
            ProjectProductionIntent.self,
            from: data
        )

        XCTAssertEqual(decoded, record)
        XCTAssertTrue(decoded.isLinkFirstClip)
    }

    func testStandardProjectIsNotMisrepresentedAsClipIntent() {
        let record = ProjectProductionIntent(
            projectID: UUID(),
            sourceID: UUID(),
            kind: .standardProject,
            createdAt: Date()
        )

        XCTAssertFalse(record.isLinkFirstClip)
    }
}
