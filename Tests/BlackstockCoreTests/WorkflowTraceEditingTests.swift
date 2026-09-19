import XCTest
@testable import BlackstockCore

final class WorkflowTraceEditingTests: XCTestCase {
    func testStagesOnlyAdvanceInCanonicalOrder() {
        XCTAssertTrue(BlackstockStage.discovery.canTransition(to: .research))
        XCTAssertFalse(BlackstockStage.discovery.canTransition(to: .editing))
        XCTAssertTrue(BlackstockStage.review.canTransition(to: .publishing))
        XCTAssertTrue(BlackstockStage.publishing.canTransition(to: .published))
        XCTAssertNil(BlackstockStage.published.next)
    }

    func testStageGateFailsIfAnyRequiredCheckFails() {
        let gate = StageGate(stage: .publishing, checks: [
            "renderValidated": true,
            "rightsValidated": false,
            "targetChannelMatches": true
        ])
        XCTAssertFalse(gate.passes)
        XCTAssertEqual(gate.failingChecks, ["rightsValidated"])
    }

    func testRecommendationNeedsGroundedEvidence() {
        let evidenceID = UUID()
        let grounded = RecommendationTrace(
            title: "Chance",
            rationale: ["Aktuelles Signal passt zum Kanalthema"],
            limitations: [],
            evidenceIDs: [evidenceID],
            grounding: .grounded,
            createdAt: Date()
        )
        XCTAssertTrue(grounded.mayBePresentedAsRecommendation)

        let unsupported = RecommendationTrace(
            title: "Behauptung",
            rationale: ["Nicht belegt"],
            limitations: [],
            evidenceIDs: [],
            grounding: .insufficient,
            createdAt: Date()
        )
        XCTAssertFalse(unsupported.mayBePresentedAsRecommendation)
    }

    func testUnknownMediaCannotEnterProduction() {
        let asset = ProductionMediaAsset(
            displayName: "clip.mov",
            sourceURL: URL(fileURLWithPath: "/tmp/clip.mov"),
            durationSeconds: 30,
            authorization: .unknown,
            rightsEvidence: [],
            rightsAttestation: .init(confirmedByUser: false, attestedAt: Date()),
            importedAt: Date()
        )
        XCTAssertFalse(asset.mayEnterProduction)
    }

    func testAuthorizedMediaRequiresRightsEvidence() {
        let withoutEvidence = ProductionMediaAsset(
            displayName: "owned.mov",
            sourceURL: URL(fileURLWithPath: "/tmp/owned.mov"),
            durationSeconds: 30,
            authorization: .owned,
            rightsEvidence: [],
            rightsAttestation: .init(confirmedByUser: true, attestedAt: Date()),
            importedAt: Date()
        )
        XCTAssertFalse(withoutEvidence.mayEnterProduction)

        let withEvidence = ProductionMediaAsset(
            displayName: "owned.mov",
            sourceURL: URL(fileURLWithPath: "/tmp/owned.mov"),
            durationSeconds: 30,
            authorization: .owned,
            rightsEvidence: ["user-confirmed-owned"],
            rightsAttestation: .init(confirmedByUser: true, attestedAt: Date()),
            importedAt: Date()
        )
        XCTAssertTrue(withEvidence.mayEnterProduction)

        let notAttested = ProductionMediaAsset(
            displayName: "owned.mov",
            sourceURL: URL(fileURLWithPath: "/tmp/owned.mov"),
            durationSeconds: 30,
            authorization: .owned,
            rightsEvidence: ["user-says-owned"],
            rightsAttestation: .init(confirmedByUser: false, attestedAt: Date()),
            importedAt: Date()
        )
        XCTAssertFalse(notAttested.mayEnterProduction)
    }

    func testEditGraphUndoRedoIsNonDestructive() {
        var graph = EditGraph(createdAt: Date(timeIntervalSince1970: 1))
        let trim = EditOperation(
            type: .trim,
            timeRange: .init(startSeconds: 2, durationSeconds: 10),
            createdAt: Date(timeIntervalSince1970: 2)
        )
        let revision = graph.apply(trim, actor: .user)
        XCTAssertEqual(graph.currentOperations, [trim])

        XCTAssertNotNil(graph.undo())
        XCTAssertTrue(graph.currentOperations.isEmpty)

        XCTAssertNotNil(graph.redo(to: revision.id))
        XCTAssertEqual(graph.currentOperations, [trim])
    }

    func testAIActionsOnlyBecomeEditsAfterAcceptance() {
        var graph = EditGraph(createdAt: Date(timeIntervalSince1970: 1))
        let suggestion = EditOperation(
            type: .removeRange,
            timeRange: .init(startSeconds: 5, durationSeconds: 2),
            createdAt: Date(timeIntervalSince1970: 2)
        )

        XCTAssertTrue(graph.currentOperations.isEmpty)
        _ = graph.apply(suggestion, actor: .acceptedAIProposal)
        XCTAssertEqual(graph.currentOperations.count, 1)
        XCTAssertEqual(graph.head.actor, .acceptedAIProposal)
    }

    func testTimelineResolverCombinesTrimAndOverlappingRemoveRanges() {
        let operations = [
            EditOperation(
                type: .trim,
                timeRange: .init(
                    startSeconds: 10,
                    durationSeconds: 60
                ),
                createdAt: Date(timeIntervalSince1970: 1)
            ),
            EditOperation(
                type: .removeRange,
                timeRange: .init(
                    startSeconds: 20,
                    durationSeconds: 10
                ),
                createdAt: Date(timeIntervalSince1970: 2)
            ),
            EditOperation(
                type: .removeRange,
                timeRange: .init(
                    startSeconds: 25,
                    durationSeconds: 10
                ),
                createdAt: Date(timeIntervalSince1970: 3)
            ),
            EditOperation(
                type: .removeRange,
                timeRange: .init(
                    startSeconds: 60,
                    durationSeconds: 20
                ),
                createdAt: Date(timeIntervalSince1970: 4)
            )
        ]

        let plan = EditTimelineResolver().resolve(
            sourceDurationSeconds: 100,
            operations: operations
        )

        XCTAssertEqual(
            plan.sourceRanges,
            [
                EditTimeRange(
                    startSeconds: 10,
                    durationSeconds: 10
                ),
                EditTimeRange(
                    startSeconds: 35,
                    durationSeconds: 25
                )
            ]
        )
        XCTAssertEqual(plan.outputDurationSeconds, 35, accuracy: 0.001)
    }

    func testTimelineResolverDetectsEmptyEditResult() {
        let operations = [
            EditOperation(
                type: .trim,
                timeRange: .init(
                    startSeconds: 10,
                    durationSeconds: 20
                ),
                createdAt: Date(timeIntervalSince1970: 1)
            ),
            EditOperation(
                type: .removeRange,
                timeRange: .init(
                    startSeconds: 0,
                    durationSeconds: 100
                ),
                createdAt: Date(timeIntervalSince1970: 2)
            )
        ]

        let plan = EditTimelineResolver().resolve(
            sourceDurationSeconds: 100,
            operations: operations
        )

        XCTAssertFalse(plan.hasContent)
        XCTAssertTrue(plan.sourceRanges.isEmpty)
    }

    func testActivityLedgerPreservesCorrelationTrace() {
        let correlation = UUID()
        var ledger = ActivityLedger()
        ledger.append(.init(
            timestamp: Date(timeIntervalSince1970: 1),
            actor: .blackstock,
            stage: .research,
            action: "candidate-found",
            summary: "Quelle gefunden",
            relatedSourceIDs: ["video-1"],
            reversible: false,
            correlationID: correlation
        ))
        ledger.append(.init(
            timestamp: Date(timeIntervalSince1970: 2),
            actor: .user,
            stage: .production,
            action: "accepted",
            summary: "Vorschlag übernommen",
            relatedSourceIDs: ["video-1"],
            reversible: true,
            correlationID: correlation
        ))
        XCTAssertEqual(ledger.events(correlationID: correlation).count, 2)
    }

    func testJobControlsDoNotFakePause() {
        XCTAssertFalse(JobControl.cancelOnly.supportsPause)
        XCTAssertFalse(JobControl.nonInterruptibleShortStep.supportsPause)
        XCTAssertTrue(JobControl.pausable.supportsPause)
        XCTAssertTrue(JobControl.resumable.supportsResume)
    }
}
