#if os(macOS)
import XCTest
@testable import BlackstockCore

final class StoryAudioAndCaptionTests: XCTestCase {
    func testCaptionsFollowTheAudibleSource() throws {
        let id = UUID()
        let lead = LocalTranscript(localeIdentifier: "de-DE", text: "Anfang falsch Ende", segments: [
            .init(startSeconds: 0, durationSeconds: 1, text: "Anfang", confidence: 1),
            .init(startSeconds: 3, durationSeconds: 1, text: "falsch", confidence: 1),
            .init(startSeconds: 7, durationSeconds: 1, text: "Ende", confidence: 1)
        ], onDevice: true, createdAt: Date())
        var setting = SupplementalVideoInsertSetting(captureID: id, enabled: true)
        var scene = MatchedStoryScene(outputStart: 2, sourceStart: 20, duration: 3, explanation: "Test")
        scene.spokenSegments = [.init(start: 20.5, duration: 1, text: "Zusatzstimme", confidence: 1)]
        setting.matchedScenes = [scene]
        let input = SupplementalVideoInsertInput(captureID: id, fileURL: URL(fileURLWithPath: "/tmp/test"),
            timelineStartSeconds: 2, sourceStartSeconds: 20, durationSeconds: 3, usesOriginalAudio: true)
        let result = try XCTUnwrap(StoryTranscriptComposer.compose(lead: lead, inputs: [input], settings: [setting]))
        XCTAssertEqual(result.segments.map(\.text), ["Anfang", "Zusatzstimme", "Ende"])
        XCTAssertEqual(result.segments[1].startSeconds, 2.5, accuracy: 0.001)
        let unknown = try XCTUnwrap(StoryTranscriptComposer.compose(lead: lead, inputs: [input], settings: []))
        XCTAssertEqual(unknown.segments.map(\.text), ["Anfang", "Ende"])
    }

    func testOriginalAudioSurvivesSceneDistribution() {
        let input = SupplementalVideoInsertInput(captureID: UUID(), fileURL: URL(fileURLWithPath: "/tmp/test"),
            timelineStartSeconds: 0, sourceStartSeconds: 0, durationSeconds: 24, usesOriginalAudio: true)
        let scenes = StoryMontagePlanner.distribute([input], outputDuration: 40, shotDuration: 12)
        XCTAssertEqual(scenes.count, 2)
        XCTAssertTrue(scenes.allSatisfy(\.usesOriginalAudio))
    }
}
#endif
