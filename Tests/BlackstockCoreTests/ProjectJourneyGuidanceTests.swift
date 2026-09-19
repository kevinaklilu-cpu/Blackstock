import XCTest
@testable import BlackstockCore

final class ProjectJourneyGuidanceTests: XCTestCase {
    func testEveryCanonicalStageHasGuidance() {
        XCTAssertEqual(
            BlackstockStage.allCases.map(\.journeyGuidance.stage),
            BlackstockStage.allCases
        )
        XCTAssertTrue(
            BlackstockStage.allCases.allSatisfy {
                !$0.journeyGuidance.title.isEmpty
                && !$0.journeyGuidance.purpose.isEmpty
                && !$0.journeyGuidance.nextAction.isEmpty
            }
        )
    }

    func testImplementedProductionFlowPointsToStudio() {
        let studioStages: [BlackstockStage] = [
            .production,
            .preview,
            .storyboard,
            .editing,
            .packaging,
            .review,
            .publishing
        ]

        XCTAssertTrue(
            studioStages.allSatisfy {
                $0.journeyGuidance.recommendedSurface == .studio
            }
        )
    }

    func testDiscoveryDoesNotInventUnavailableProjectNavigation() {
        XCTAssertEqual(
            BlackstockStage.discovery.journeyGuidance
                .recommendedSurface,
            .none
        )
    }

    func testResearchAndAnalysisUseOverviewEvidenceSurface() {
        XCTAssertEqual(
            BlackstockStage.research.journeyGuidance
                .recommendedSurface,
            .overview
        )
        XCTAssertEqual(
            BlackstockStage.analysis.journeyGuidance
                .recommendedSurface,
            .overview
        )
    }

    func testPublishedGuidanceStaysInLearningOverview() {
        XCTAssertEqual(
            BlackstockStage.published.journeyGuidance
                .recommendedSurface,
            .overview
        )
    }

    func testCanonicalProgressPositionsMatchStageOrder() {
        XCTAssertEqual(
            BlackstockStage.discovery.canonicalProgressPosition,
            1
        )
        XCTAssertEqual(
            BlackstockStage.published.canonicalProgressPosition,
            BlackstockStage.canonicalProgressCount
        )
        XCTAssertEqual(
            BlackstockStage.canonicalProgressCount,
            BlackstockStage.allCases.count
        )
    }
}
