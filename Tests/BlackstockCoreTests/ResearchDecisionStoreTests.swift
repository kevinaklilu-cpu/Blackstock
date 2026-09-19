import XCTest
@testable import BlackstockCore

final class ResearchDecisionStoreTests: XCTestCase {
    func testResearchAndAnalysisRoundTripPerProject() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let projectID = UUID()
        let source = MediaSourceReference(
            provider: .youtube,
            pageURL: URL(string: "https://www.youtube.com/watch?v=abc")!,
            externalID: "abc",
            discoveredAt: Date(timeIntervalSince1970: 10)
        )
        let research = ResearchEvidenceRecord(
            projectID: projectID,
            opportunityID: "opp",
            source: source,
            researchQuestion: "Was ist hier wirklich relevant?",
            providerFacts: ["1000 Views", "Abruf 12:00"],
            creatorNotes: "Das Thema passt zur Zielgruppe.",
            createdAt: Date(timeIntervalSince1970: 20)
        )
        let analysis = AnalysisDecisionRecord(
            projectID: projectID,
            decision: .pursue,
            rationale: "Passt zur Strategie und hat belegte Nachfrage.",
            riskOrUnknown: "Langzeit-Retention ist noch unbekannt.",
            createdAt: Date(timeIntervalSince1970: 30)
        )

        let store = ResearchDecisionStore(rootURL: root)
        try store.saveResearch(research)
        try store.saveAnalysis(analysis)

        XCTAssertEqual(
            try store.loadResearch(projectID: projectID),
            research
        )
        XCTAssertEqual(
            try store.loadAnalysis(projectID: projectID),
            analysis
        )
    }

    func testResearchCompletenessRequiresQuestionFactsAndCreatorNotes() {
        let source = MediaSourceReference(
            provider: .youtube,
            pageURL: URL(string: "https://www.youtube.com/watch?v=abc")!,
            externalID: "abc",
            discoveredAt: Date()
        )
        let record = ResearchEvidenceRecord(
            projectID: UUID(),
            opportunityID: "opp",
            source: source,
            researchQuestion: "Frage",
            providerFacts: [],
            creatorNotes: "Notiz",
            createdAt: Date()
        )
        XCTAssertFalse(record.isComplete)
    }

    func testAnalysisCompletenessRequiresRationaleAndExplicitUnknown() {
        XCTAssertFalse(
            AnalysisDecisionRecord(
                projectID: UUID(),
                decision: .pursue,
                rationale: "Begründung",
                riskOrUnknown: " ",
                createdAt: Date()
            ).isComplete
        )
    }
}
