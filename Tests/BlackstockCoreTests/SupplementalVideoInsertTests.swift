import XCTest
@testable import BlackstockCore

final class SupplementalVideoInsertTests: XCTestCase {
    func testPlannerClampsInsertToSourceAndOutput() {
        let id = UUID()
        let setting = SupplementalVideoInsertSetting(
            captureID: id,
            enabled: true,
            timelineStartSeconds: 8,
            sourceStartSeconds: 3,
            durationSeconds: 10
        )

        let plan = SupplementalVideoInsertPlanner().plan(
            setting: setting,
            sourceDurationSeconds: 9,
            outputDurationSeconds: 12
        )

        XCTAssertEqual(plan?.timelineStartSeconds, 8)
        XCTAssertEqual(plan?.sourceStartSeconds, 3)
        XCTAssertEqual(plan?.durationSeconds, 4)
    }

    func testDisabledInsertProducesNoPlan() {
        let setting = SupplementalVideoInsertSetting(
            captureID: UUID(),
            enabled: false,
            durationSeconds: 4
        )

        XCTAssertNil(
            SupplementalVideoInsertPlanner().plan(
                setting: setting,
                sourceDurationSeconds: 10,
                outputDurationSeconds: 10
            )
        )
    }

    func testZeroLengthWindowIsRejected() {
        let setting = SupplementalVideoInsertSetting(
            captureID: UUID(),
            enabled: true,
            timelineStartSeconds: 10,
            durationSeconds: 2
        )

        XCTAssertNil(
            SupplementalVideoInsertPlanner().plan(
                setting: setting,
                sourceDurationSeconds: 10,
                outputDurationSeconds: 10
            )
        )
    }

    func testWorkspaceRoundTripsVisualInsertSettings() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                UUID().uuidString,
                isDirectory: true
            )
        defer {
            try? FileManager.default.removeItem(at: root)
        }

        let projectID = UUID()
        let captureID = UUID()
        let capture = SupplementalCaptureAsset(
            id: captureID,
            projectID: projectID,
            kind: .screen,
            fileURL: URL(
                fileURLWithPath: "/tmp/screen.mp4"
            ),
            mimeType: "video/mp4",
            durationSeconds: 18,
            rightsBasis:
                "Arbeitsbereich-Nutzererklärung",
            rightsEvidence:
                "Eigene Bildschirmaufnahme",
            rightsConfirmed: true,
            createdAt: Date(timeIntervalSince1970: 4)
        )
        let setting = SupplementalVideoInsertSetting(
            captureID: captureID,
            enabled: true,
            timelineStartSeconds: 7,
            sourceStartSeconds: 2,
            durationSeconds: 5
        )
        let snapshot = StudioWorkspaceSnapshot(
            projectID: projectID,
            mediaAsset: nil,
            editGraph: EditGraph(
                createdAt: Date(timeIntervalSince1970: 1)
            ),
            activityLedger: ActivityLedger(),
            storyboard: StoryboardPlan(
                projectID: projectID,
                updatedAt: Date(timeIntervalSince1970: 2)
            ),
            trimStart: 0,
            trimEnd: 0,
            transcript: nil,
            captionURL: nil,
            renderArtifact: nil,
            supplementalCaptures: [capture],
            supplementalVideoInsertSettings: [setting],
            updatedAt: Date(timeIntervalSince1970: 5)
        )

        let store = ProjectWorkspaceStore(rootURL: root)
        try store.save(snapshot)

        let restored = try XCTUnwrap(
            store.load(projectID: projectID)
        )
        XCTAssertEqual(
            restored.supplementalVideoInsertSettings,
            [setting]
        )
        XCTAssertEqual(
            restored.supplementalCaptures?.first?.durationSeconds,
            18
        )
    }
}
