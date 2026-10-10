import XCTest
@testable import BlackstockCore

final class ClipOutputProfileTests: XCTestCase {
    func testFocalPathTracksNearbyMovementAndAvoidsSweepingBetweenSubjects() throws {
        let path = [ReframeFocalSample(sourceSeconds: 10, focalX: 0.3, focalY: 0.4),
                    ReframeFocalSample(sourceSeconds: 12, focalX: 0.4, focalY: 0.4)]
        XCTAssertEqual(try XCTUnwrap(TrackedReframeComposer.focalSample(at: 11, path: path)).focalX, 0.35, accuracy: 0.001)
        XCTAssertEqual(TrackedReframeComposer.focalSample(at: 0, path: path), path.first)
        let cut = [path[0], ReframeFocalSample(sourceSeconds: 12, focalX: 0.8, focalY: 0.4)]
        XCTAssertEqual(TrackedReframeComposer.focalSample(at: 10.5, path: cut)?.focalX, 0.3)
        XCTAssertEqual(TrackedReframeComposer.focalSample(at: 11.5, path: cut)?.focalX, 0.8)
        XCTAssertNil(TrackedReframeComposer.focalSample(at: 1, path: []))
    }

    func testSustainedVisualActivityOutranksIsolatedIntroFlash() {
        let intro = (0..<12).map { VisualMomentSample(time: Double($0), activity: $0 == 4 ? 0.9 : 0.01) }
        let action = (50..<62).map { VisualMomentSample(time: Double($0), activity: 0.4) }
        let introScore = VisualMomentPlanner.activityScore(samples: intro, range: .init(startSeconds: 0, durationSeconds: 12), duration: 120)
        let actionScore = VisualMomentPlanner.activityScore(samples: action, range: .init(startSeconds: 50, durationSeconds: 12), duration: 120)
        XCTAssertGreaterThan(actionScore, introScore)
        XCTAssertLessThan(actionScore, 1)
    }

    func testShortAndVideoHaveDifferentContextWindows() {
        let samples = (0..<180).map { VisualMomentSample(time: Double($0), activity: (70...80).contains($0) ? 0.4 : 0.01) }
        let shorts = VisualMomentPlanner.ranges(samples: samples, duration: 180, maximumDuration: 90, profile: .short)
        let videos = VisualMomentPlanner.ranges(samples: samples, duration: 180, maximumDuration: 360, profile: .video)
        XCTAssertFalse(shorts.isEmpty)
        XCTAssertFalse(videos.isEmpty)
        XCTAssertLessThan(shorts[0].durationSeconds, videos[0].durationSeconds)
        XCTAssertGreaterThan(shorts[0].startSeconds, videos[0].startSeconds)
        XCTAssertTrue(ClipOutputProfile.short.fillsPortraitFrame)
    }
    func testYouTubeClassificationUsesRenderedGeometryAndDuration() {
        XCTAssertTrue(ClipOutputProfile.isYouTubeShort(width: 1080, height: 1920, duration: 179))
        XCTAssertTrue(ClipOutputProfile.isYouTubeShort(width: 1080, height: 1080, duration: 180))
        XCTAssertFalse(ClipOutputProfile.isYouTubeShort(width: 1920, height: 1080, duration: 20))
        XCTAssertFalse(ClipOutputProfile.isYouTubeShort(width: 1080, height: 1920, duration: 181))
        XCTAssertFalse(ClipOutputProfile.isYouTubeShort(width: 0, height: 0, duration: 10))
    }
    func testEditorialOptionsRemainDistinctAndPersist() throws {
        let json = #"{"title":"A complete football moment","description":"A specific description of the edited play.","tags":["football"],"alternativeTitles":["How this chance developed","The finish that changed the play"],"alternativeDescriptions":["A concise account of this play.","A detailed account of this play and its visible conclusion."]}"#
        let proposal = try XCTUnwrap(LocalClipEditorialAdvisor.publication(json: json))
        XCTAssertEqual(proposal.alternativeDescriptions.count, 2)
        let draft = PublicationEditorDraft(title: proposal.title, description: proposal.description, tags: "football", thumbnailURL: nil, thumbnailOptions: [], alternativeTitles: proposal.alternativeTitles, alternativeDescriptions: proposal.alternativeDescriptions)
        XCTAssertEqual(try JSONDecoder().decode(PublicationEditorDraft.self, from: JSONEncoder().encode(draft)), draft)
        let old = #"{"title":"Old title","description":"Old description","tags":"","thumbnailOptions":[]}"#.data(using: .utf8)!
        XCTAssertNil(try JSONDecoder().decode(PublicationEditorDraft.self, from: old).alternativeTitles)
    }
}
