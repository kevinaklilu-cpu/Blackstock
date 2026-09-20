import XCTest
@testable import BlackstockCore

final class SupplementalAudioMixTests: XCTestCase {
    func testMixSettingClampsVolume() {
        let id = UUID()

        XCTAssertEqual(
            SupplementalAudioMixSetting(
                captureID: id,
                enabled: true,
                volume: 2
            ).volume,
            1
        )

        XCTAssertEqual(
            SupplementalAudioMixSetting(
                captureID: id,
                enabled: true,
                volume: -1
            ).volume,
            0
        )
    }

    func testMixInputClampsVolume() {
        let input = SupplementalAudioMixInput(
            captureID: UUID(),
            fileURL: URL(fileURLWithPath: "/tmp/voice.m4a"),
            volume: 1.4
        )

        XCTAssertEqual(input.volume, 1)
    }

    func testWorkspaceRoundTripsSupplementalAudioMixSettings() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let projectID = UUID()
        let captureID = UUID()
        let capture = SupplementalCaptureAsset(
            id: captureID,
            projectID: projectID,
            kind: .microphone,
            fileURL: URL(fileURLWithPath: "/tmp/voice.m4a"),
            mimeType: "audio/mp4",
            rightsBasis: "Eigenes Material",
            rightsEvidence: "Eigene Mikrofonaufnahme",
            rightsConfirmed: true,
            createdAt: Date(timeIntervalSince1970: 4)
        )
        let setting = SupplementalAudioMixSetting(
            captureID: captureID,
            enabled: true,
            volume: 0.65
        )
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
            trimEnd: 0,
            transcript: nil,
            captionURL: nil,
            renderArtifact: nil,
            supplementalCaptures: [capture],
            supplementalAudioMixSettings: [setting],
            updatedAt: Date(timeIntervalSince1970: 5)
        )

        let store = ProjectWorkspaceStore(rootURL: root)
        try store.save(snapshot)

        let restored = try XCTUnwrap(
            store.load(projectID: projectID)
        )
        XCTAssertEqual(
            restored.supplementalAudioMixSettings,
            [setting]
        )
    }
}
