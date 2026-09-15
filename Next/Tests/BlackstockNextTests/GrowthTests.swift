import XCTest
@testable import BlackstockNext

final class GrowthTests: XCTestCase {
    func testOutlierOpportunityNeedsChannelFitNotJustViews() {
        let strongFit = MarketVideoSignal(id: "a", title: "A", channelID: "x", channelMedianViews: 20_000, currentViews: 200_000, ageHours: 24, relevanceToChannel: 0.9, saturation: 0.2)
        let weakFit = MarketVideoSignal(id: "b", title: "B", channelID: "y", channelMedianViews: 20_000, currentViews: 600_000, ageHours: 24, relevanceToChannel: 0.05, saturation: 0.2)
        let engine = OpportunityEngine()
        XCTAssertGreaterThan(engine.assess(strongFit).score, engine.assess(weakFit).score)
    }

    func testPackagingPenalizesDuplicatedTitleAndThumbnailPromise() {
        let concept = PackagingConcept(angle: .curiosity, title: "Das iPhone Problem", thumbnailPromise: "Das iPhone Problem", viewerPromise: "Wir zeigen, welches konkrete Problem im Alltag wirklich relevant ist.")
        let result = PackagingQualityEngine().evaluate(concept)
        XCTAssertTrue(result.issues.contains { $0.contains("wiederholen") })
        XCTAssertLessThan(result.score, 100)
    }

    func testMarketReadinessDoesNotCallBrokenProductReady() {
        let result = MarketReadinessGate().evaluate(crashFreeRate: 0.98, exportSuccessRate: 0.95, taskCompletionRate: 0.7, uploadResumeVerified: false, captionPassRateAfterAutoFix: 0.8, blindEditPreferenceRate: 0.4)
        XCTAssertEqual(result.state, .blocked)
        XCTAssertFalse(result.blockers.isEmpty)
    }

    func testMarketReadinessCanPassOnlyWithMeasuredQuality() {
        let result = MarketReadinessGate().evaluate(crashFreeRate: 0.999, exportSuccessRate: 0.995, taskCompletionRate: 0.95, uploadResumeVerified: true, captionPassRateAfterAutoFix: 0.98, blindEditPreferenceRate: 0.61)
        XCTAssertEqual(result.state, .ready)
        XCTAssertTrue(result.blockers.isEmpty)
    }
}
