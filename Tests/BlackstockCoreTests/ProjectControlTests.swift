import XCTest
@testable import BlackstockCore

final class ProjectControlTests: XCTestCase {
    func testPausedProjectCannotAdvanceUntilResumed() {
        let now = Date(timeIntervalSince1970: 1_790_000_000)
        var project = BlackstockProject(
            title: "Clip",
            targetChannelID: "channel-1",
            stage: .production,
            strategyVersion: 1,
            createdAt: now,
            updatedAt: now
        )

        project.setPaused(
            true,
            at: now.addingTimeInterval(1)
        )
        XCTAssertTrue(project.isPaused)
        XCTAssertFalse(
            project.advance(
                to: .preview,
                at: now.addingTimeInterval(2)
            )
        )

        project.setPaused(
            false,
            at: now.addingTimeInterval(3)
        )
        XCTAssertFalse(project.isPaused)
        XCTAssertTrue(
            project.advance(
                to: .preview,
                at: now.addingTimeInterval(4)
            )
        )
    }

    func testPausedStateSurvivesPersistence() throws {
        let now = Date(timeIntervalSince1970: 1_790_000_000)
        var project = BlackstockProject(
            title: "Sport Clip",
            targetChannelID: "channel-1",
            strategyVersion: 2,
            createdAt: now,
            updatedAt: now
        )
        project.setPaused(
            true,
            at: now.addingTimeInterval(5)
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(project)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(
            BlackstockProject.self,
            from: data
        )

        XCTAssertEqual(decoded, project)
        XCTAssertTrue(decoded.isPaused)
    }
}
