import XCTest
@testable import BlackstockCore

final class ChannelStrategyDraftTests: XCTestCase {
    func testCreatesCompleteVersionedStrategyFromExplicitDraft() throws {
        let draft = ChannelStrategyDraft(
            primaryTopic: " KI für Selbstständige ",
            contentPromise: "Praktische KI ohne Hype",
            audienceHypothesis: "Solo-Selbstständige mit wenig Zeit",
            pillarsText: "Automatisierung, Recherche\nProduktivität",
            adjacentTopicsText: "No-Code; Workflows",
            excludedTopicsText: "Krypto, Gaming",
            objective: .watchTime
        )

        let strategy = try draft.makeStrategy(
            channelID: "channel-A",
            contentLanguage: "de",
            version: 4,
            now: Date(timeIntervalSince1970: 100)
        )

        XCTAssertEqual(strategy.channelID, "channel-A")
        XCTAssertEqual(strategy.primaryTopic, "KI für Selbstständige")
        XCTAssertEqual(strategy.contentPromise, "Praktische KI ohne Hype")
        XCTAssertEqual(strategy.audienceHypothesis, "Solo-Selbstständige mit wenig Zeit")
        XCTAssertEqual(
            strategy.pillars,
            ["Automatisierung", "Recherche", "Produktivität"]
        )
        XCTAssertEqual(strategy.adjacentTopics, ["No-Code", "Workflows"])
        XCTAssertEqual(strategy.excludedTopics, ["Krypto", "Gaming"])
        XCTAssertEqual(strategy.objectives, [.watchTime])
        XCTAssertEqual(strategy.defaultContentLanguage, "de")
        XCTAssertEqual(strategy.researchLanguages, ["de", "en"])
        XCTAssertEqual(strategy.version, 4)
    }

    func testMissingStrategicEvidenceHardStops() {
        let base = ChannelStrategyDraft(
            primaryTopic: "Thema",
            contentPromise: "",
            audienceHypothesis: "Zielgruppe",
            pillarsText: "Säule",
            adjacentTopicsText: "",
            excludedTopicsText: "",
            objective: .balanced
        )

        XCTAssertThrowsError(
            try base.makeStrategy(
                channelID: "channel",
                contentLanguage: "de",
                version: 1
            )
        ) {
            XCTAssertEqual(
                $0 as? ChannelStrategyDraftError,
                .missingContentPromise
            )
        }
    }

    func testListParsingDropsEmptyValuesAndDuplicates() {
        XCTAssertEqual(
            ChannelStrategyDraft.list(
                from: "A, B; a\n C ,,"
            ),
            ["A", "B", "C"]
        )
    }
}
