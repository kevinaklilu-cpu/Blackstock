import XCTest
@testable import BlackstockCore

final class ChannelStrategyDraftTests: XCTestCase {
    func testDraftRequiresExplicitCoreStrategyInputs() {
        let base = ChannelStrategyDraft(
            primaryTopic: "KI für Selbstständige",
            topicDefinition: "Praktische KI-Automatisierung im Arbeitsalltag",
            contentPromise: "Jedes Video zeigt einen konkret umsetzbaren Workflow.",
            pillars: ["Automatisierung"],
            audienceHypothesis: "Solo-Selbstständige mit wenig technischer Zeit"
        )

        XCTAssertNoThrow(try base.validate())

        var missingPromise = base
        missingPromise.contentPromise = " "
        XCTAssertThrowsError(try missingPromise.validate()) {
            XCTAssertEqual(
                $0 as? ChannelStrategyDraftValidationError,
                .missingContentPromise
            )
        }

        var missingAudience = base
        missingAudience.audienceHypothesis = ""
        XCTAssertThrowsError(try missingAudience.validate()) {
            XCTAssertEqual(
                $0 as? ChannelStrategyDraftValidationError,
                .missingAudienceHypothesis
            )
        }

        var missingPillars = base
        missingPillars.pillars = [" ", "\n"]
        XCTAssertThrowsError(try missingPillars.validate()) {
            XCTAssertEqual(
                $0 as? ChannelStrategyDraftValidationError,
                .missingPillars
            )
        }
    }

    func testStrategyIsBuiltOnlyFromExplicitNormalizedDraftFacts() throws {
        let draft = ChannelStrategyDraft(
            primaryTopic: "  KI für Selbstständige ",
            topicDefinition: " Praktische Automatisierung ",
            contentPromise: " Konkrete Workflows ohne Hype ",
            pillars: [" Automatisierung ", "Tools", "tools"],
            adjacentTopics: ["Produktivität", ""],
            excludedTopics: ["Reine News"],
            audienceHypothesis: " Solo-Selbstständige ",
            objective: .watchTime
        )

        let strategy = try draft.makeStrategy(
            channelID: "channel-A",
            defaultContentLanguage: "de",
            researchLanguages: ["de", "en", "de"],
            effectiveFrom: Date(timeIntervalSince1970: 100),
            version: 3
        )

        XCTAssertEqual(strategy.primaryTopic, "KI für Selbstständige")
        XCTAssertEqual(strategy.topicDefinition, "Praktische Automatisierung")
        XCTAssertEqual(strategy.contentPromise, "Konkrete Workflows ohne Hype")
        XCTAssertEqual(strategy.pillars, ["Automatisierung", "Tools"])
        XCTAssertEqual(strategy.adjacentTopics, ["Produktivität"])
        XCTAssertEqual(strategy.excludedTopics, ["Reine News"])
        XCTAssertEqual(strategy.audienceHypothesis, "Solo-Selbstständige")
        XCTAssertEqual(strategy.objectives, [.watchTime])
        XCTAssertEqual(strategy.researchLanguages, ["de", "en"])
        XCTAssertEqual(strategy.version, 3)
    }

    func testParseListAcceptsCommaSemicolonAndLineBreaks() {
        XCTAssertEqual(
            ChannelStrategyDraft.parseList(
                "Automatisierung, Tools; Prozesse\nPraxis"
            ),
            ["Automatisierung", "Tools", "Prozesse", "Praxis"]
        )
    }
}
