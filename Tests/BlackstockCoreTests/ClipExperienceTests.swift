import XCTest
import CoreGraphics
@testable import BlackstockCore

final class ClipExperienceTests: XCTestCase {
    private func transcript(_ text: String) -> LocalTranscript {
        .init(localeIdentifier: "de-DE", text: text, segments: [], onDevice: true, createdAt: Date())
    }

    func testEditorialModelCannotInventSourceRanges() {
        let candidates = (0..<3).map { index in
            LocalClipCandidate(sourceRange: .init(startSeconds: Double(index * 30), durationSeconds: 20), transcriptPreview: "Measured moment", wordCount: 10, averageConfidence: 1, segmentIDs: [])
        }
        let ordered = LocalClipEditorialAdvisor.orderedCandidates(candidates, json: "[2,0]")
        XCTAssertEqual(ordered?.map(\.id), [candidates[2].id, candidates[0].id, candidates[1].id])
        XCTAssertNil(LocalClipEditorialAdvisor.orderedCandidates(candidates, json: "[100]"))
        XCTAssertNil(LocalClipEditorialAdvisor.orderedCandidates(candidates, json: "[1,1]"))
        XCTAssertNil(LocalClipEditorialAdvisor.orderedCandidates(candidates, json: "not JSON"))
    }

    func testEditorialPublicationRejectsMalformedModelOutput() {
        XCTAssertNil(LocalClipEditorialAdvisor.publication(json: "{}"))
        XCTAssertNil(LocalClipEditorialAdvisor.publication(json: "not JSON"))
        let valid = #"{"title":"Warum Kameras Strom sparen","description":"Dieser Ausschnitt erklärt den geringeren Stromverbrauch der Kamera.","tags":["Kamera","kamera","Energie"],"alternativeTitles":["So arbeitet die Kamera"]}"#
        XCTAssertEqual(LocalClipEditorialAdvisor.publication(json: valid)?.tags, ["Kamera", "Energie"])
    }

    func testPublicationChangesWithSelectedMoment() {
        let first = StoryPublicationDraft.forClip(transcript: transcript("Warum spart diese Kamera so viel Energie? Drei Sensoren reduzieren den Stromverbrauch."), sourceURL: nil, start: 10, duration: 28, isShort: true)
        let second = StoryPublicationDraft.forClip(transcript: transcript("Diese Pflanzen wachsen auch ohne Sonnenlicht. Die Wurzeln brauchen regelmäßig frisches Wasser."), sourceURL: nil, start: 140, duration: 71, isShort: false)
        XCTAssertNotEqual(first.title, second.title)
        XCTAssertTrue(first.title.contains("Kamera"))
        XCTAssertFalse(second.description.contains("Kamera"))
        XCTAssertTrue(second.description.contains("Pflanzen"))
        XCTAssertFalse(second.description.contains("Video · Ausschnitt"))
        XCTAssertLessThanOrEqual(first.title.count, 90)
    }

    func testMissingTranscriptDoesNotInventTitleOrTags() {
        let draft = StoryPublicationDraft.forClip(transcript: nil, sourceURL: nil, start: 0, duration: 20, isShort: true)
        XCTAssertTrue(draft.title.contains("ergänzen"))
        XCTAssertTrue(draft.tags.isEmpty)
    }

    func testOffCentreFaceIsCentredInPortraitCrop() throws {
        let crop = try XCTUnwrap(ReframeCropPlan.make(sourceWidth: 1920, sourceHeight: 1080,
            spec: .init(aspectRatio: .portrait9x16, focalX: 0.3, focalY: 0.5)))
        XCTAssertEqual(crop.cropX + crop.cropWidth / 2, 1920 * 0.3, accuracy: 0.001)
    }

    func testFullFrameModeKeepsEveryCornerVisible() throws {
        let plan = try XCTUnwrap(ReframeTransformPlan.make(naturalSize: CGSize(width: 1920, height: 1080), preferredTransform: .identity,
            spec: .init(aspectRatio: .portrait9x16, preserveFullFrame: true), renderSize: CGSize(width: 1080, height: 1920)))
        let rect = CGRect(x: 0, y: 0, width: 1920, height: 1080).applying(plan.transform)
        XCTAssertGreaterThanOrEqual(rect.minX, 0)
        XCTAssertGreaterThanOrEqual(rect.minY, 0)
        XCTAssertLessThanOrEqual(rect.maxX, 1080.001)
        XCTAssertLessThanOrEqual(rect.maxY, 1920.001)
    }

    func testMomentLengthsFollowSpeechAndLaterMomentsRemainEligible() {
        let segments: [TranscriptSegment] = [
            .init(startSeconds: 0, durationSeconds: 8, text: "Eine Einführung mit einigen Worten", confidence: 0.7),
            .init(startSeconds: 8, durationSeconds: 8, text: "und einem vollständigen Ende.", confidence: 0.7),
            .init(startSeconds: 100, durationSeconds: 12, text: "Warum diese 3 Fehler niemals passieren sollten", confidence: 0.99),
            .init(startSeconds: 112, durationSeconds: 14, text: "und wie du sie überraschend einfach vermeidest!", confidence: 0.99)
        ]
        let source = LocalTranscript(localeIdentifier: "de-DE", text: segments.map(\.text).joined(separator: " "), segments: segments, onDevice: true, createdAt: Date())
        let moments = LocalClipCandidateGenerator().generate(transcript: source, sourceDurationSeconds: 150, minimumDurationSeconds: 12, maximumCandidates: 10)
        XCTAssertEqual(moments.count, 2)
        XCTAssertNotEqual(moments[0].sourceRange.durationSeconds, moments[1].sourceRange.durationSeconds)
        XCTAssertTrue(moments.allSatisfy { $0.sourceRange.durationSeconds < 45 })
        let best = LocalClipCandidateGenerator().generate(transcript: source, sourceDurationSeconds: 150, minimumDurationSeconds: 12, maximumCandidates: 1)
        XCTAssertGreaterThan(best.first?.sourceRange.startSeconds ?? 0, 90)
    }
}
