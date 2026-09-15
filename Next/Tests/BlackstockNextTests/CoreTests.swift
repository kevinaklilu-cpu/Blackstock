import XCTest
@testable import BlackstockNext

final class CoreTests: XCTestCase {
    func testRightsPolicyNeverExportsUnconfirmedLocalSource() {
        let policy = RightsPolicy()
        XCTAssertEqual(policy.decision(for: .init(kind: .localLicensed, userConfirmedRights: false)), .analysisOnly(reason: "Lokaler Export erfordert eine bestätigte Nutzungsberechtigung."))
        XCTAssertEqual(policy.decision(for: .init(kind: .localOwned, userConfirmedRights: true)), .localExportAllowed)
        XCTAssertEqual(policy.decision(for: .init(kind: .youtubeReference, userConfirmedRights: false)), .youtubeNativeRemix)
    }

    func testClipRankingRewardsCompleteStandaloneMoments() {
        let strong = ClipCandidate(start: 10, end: 42, transcript: "Das ist ein vollständiger eigenständiger Moment mit klarer Aussage und Auflösung.", signals: .init(hook: 0.95, payoff: 0.92, contextIndependence: 0.94, informationDensity: 0.85, emotionalChange: 0.8, sentenceBoundaryQuality: 0.95, visualActivity: 0.75, silencePenalty: 0.08))
        let weak = ClipCandidate(start: 50, end: 82, transcript: "und dann", signals: .init(hook: 0.4, payoff: 0.2, contextIndependence: 0.15, informationDensity: 0.25, emotionalChange: 0.2, sentenceBoundaryQuality: 0.2, visualActivity: 0.4, silencePenalty: 0.6))
        let ranked = ClipIntelligenceEngine().rank([weak, strong], targetDuration: 20...60)
        XCTAssertEqual(ranked.first?.candidate.id, strong.id)
        XCTAssertGreaterThan(ranked.first?.score ?? 0, 75)
    }

    func testChannelDNAIsBoundToObservedChannelVideos() {
        let identity = ChannelIdentity(id: "abc", name: "Tech Kanal", description: "", primaryTopic: "Technik", language: "de")
        let videos = [
            ChannelVideoProfile(id: "1", title: "iPhone Kamera Test", description: "Apple Kamera Vergleich", publishedAt: Date(), viewCount: 100_000, likeCount: 5000, commentCount: 300, durationSeconds: 600, tags: ["iPhone", "Apple", "Kamera"]),
            ChannelVideoProfile(id: "2", title: "iPhone gegen Samsung", description: "Smartphone Vergleich", publishedAt: Date(), viewCount: 80_000, likeCount: 4000, commentCount: 250, durationSeconds: 720, tags: ["Smartphone", "Samsung", "Apple"])
        ]
        let dna = ChannelDNAEngine().build(identity: identity, videos: videos)
        XCTAssertEqual(dna.channelID, "abc")
        XCTAssertTrue(dna.topicKeywords.contains("iphone") || dna.topicKeywords.contains("apple"))
        XCTAssertEqual(dna.evidenceCount, 2)
    }

    func testCaptionEngineProducesReadableTwoLineCues() {
        let words = [
            TranscriptWord(text: "Das", start: 0, end: 0.3, confidence: 0.99),
            TranscriptWord(text: "ist", start: 0.31, end: 0.55, confidence: 0.99),
            TranscriptWord(text: "ein", start: 0.56, end: 0.8, confidence: 0.99),
            TranscriptWord(text: "professioneller", start: 0.81, end: 1.35, confidence: 0.99),
            TranscriptWord(text: "Caption-Test.", start: 1.36, end: 2.1, confidence: 0.99)
        ]
        let engine = CaptionEngine()
        let cues = engine.cues(from: words)
        XCTAssertFalse(cues.isEmpty)
        XCTAssertTrue(cues.allSatisfy { $0.text.split(separator: "\n").count <= 2 })
        XCTAssertTrue(engine.qualityReport(cues: cues, videoDuration: 3).blockingIssues.isEmpty)
    }

    func testMassMarketQualityPolicyAutofixesCaptionsInsteadOfBlocking() {
        let captionReport = CaptionQualityReport(score: 74, blockingIssues: ["Caption überschreitet zwei Zeilen."], warnings: [])
        let source = SourceProbe(duration: 30, naturalSize: .init(width: 1920, height: 1080), frameRate: 30, hasAudio: true)
        let decision = MassMarketQualityPolicy().decide(captions: captionReport, source: source, rights: .localExportAllowed)
        XCTAssertEqual(decision.action, .autoFix)
    }

    func testOnlyHardFailuresBlock() {
        let decision = MassMarketQualityPolicy().decide(captions: nil, source: nil, rights: .localExportAllowed)
        XCTAssertEqual(decision.action, .block)
    }
}
