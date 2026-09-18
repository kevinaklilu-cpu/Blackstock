import XCTest
@testable import BlackstockCore

final class CanonicalMasterPromptTests: XCTestCase {
    func testCapabilityIsHiddenUnlessEveryRealityGatePasses() async {
        let now = Date()
        let failing = CapabilityRecord(
            capabilityId: "youtube.upload",
            provider: "YouTube",
            implementationVersion: "1",
            authorizationState: .authorized,
            policyState: .allowed,
            regionAvailability: .available,
            channelAvailability: .available,
            requiredScopes: ["youtube.upload"],
            dataAvailability: .available,
            qualityStatus: .pass,
            testStatus: .fail,
            lastVerifiedAt: now
        )
        let registry = CapabilityRegistry(records: [failing])
        XCTAssertFalse(await registry.isVisible("youtube.upload"))

        let passing = CapabilityRecord(
            capabilityId: "youtube.upload",
            provider: "YouTube",
            implementationVersion: "1",
            authorizationState: .authorized,
            policyState: .allowed,
            regionAvailability: .available,
            channelAvailability: .available,
            requiredScopes: ["youtube.upload"],
            dataAvailability: .available,
            qualityStatus: .pass,
            testStatus: .pass,
            lastVerifiedAt: now
        )
        await registry.upsert(passing)
        XCTAssertTrue(await registry.isVisible("youtube.upload"))
    }

    func testStrategyRevisionCreatesNewVersionWithoutMutatingHistory() {
        let original = ChannelStrategy(
            channelId: "channel",
            primaryTopic: "KI",
            topicDefinition: "Praktische KI",
            contentPromise: "Praktische KI-Workflows",
            topicPillars: ["Automatisierung"],
            defaultContentLanguage: "de",
            researchLanguages: ["de", "en"],
            regionProfile: "DE",
            strategicAudienceHypothesis: "Selbstständige",
            effectiveFrom: Date(timeIntervalSince1970: 100),
            version: 1
        )
        let revised = original.revised(effectiveFrom: Date(timeIntervalSince1970: 200)) {
            $0.primaryTopic = "KI für Selbstständige"
        }
        XCTAssertEqual(original.version, 1)
        XCTAssertEqual(original.primaryTopic, "KI")
        XCTAssertEqual(revised.version, 2)
        XCTAssertEqual(revised.primaryTopic, "KI für Selbstständige")
    }

    func testProductAndContentLanguagesRemainIndependent() {
        let language = ContentLanguageStrategy(
            sourceLanguage: "en",
            primaryOutputLanguage: "de",
            titleLanguage: "de",
            descriptionLanguage: "de",
            thumbnailTextLanguage: "de",
            captionLanguage: "de",
            audioLanguage: "de",
            chapterLanguage: "de",
            metadataLanguage: "de"
        )
        XCTAssertEqual(language.sourceLanguage, "en")
        XCTAssertEqual(language.primaryOutputLanguage, "de")
    }

    func testTemporalSemanticsDoNotEquatePublicationWithTrend() {
        XCTAssertNotEqual(TemporalSemantic.publishedInWindow, .externalTrendPeriod)
        XCTAssertNotEqual(TemporalSemantic.publishedInWindow, .observedInWindow)
    }

    func testSinceLastSuccessfulResearchStartsAtPersistedTimestamp() {
        let last = Date(timeIntervalSince1970: 1_000)
        let end = Date(timeIntervalSince1970: 2_000)
        let interval = ResearchTimeWindow.sinceLastSuccessfulResearch(last).interval(endingAt: end)
        XCTAssertEqual(interval.start, last)
        XCTAssertEqual(interval.end, end)
    }

    func testWrongChannelIsHardStop() {
        let context = PublicationPreflightContext(
            projectTargetChannelId: "A",
            workspaceChannelId: "B",
            authorizedUploadChannelId: "A",
            renderValidated: true,
            rightsValidated: true,
            authorizationAvailable: true,
            quotaAvailable: true,
            networkAvailable: true
        )
        XCTAssertThrowsError(try context.validate()) { error in
            XCTAssertEqual(error as? PublicationPreflightError, .wrongChannel)
        }
    }

    func testPublicationPreflightPassesOnlyWithAllDeterministicChecks() {
        let context = PublicationPreflightContext(
            projectTargetChannelId: "A",
            workspaceChannelId: "A",
            authorizedUploadChannelId: "A",
            renderValidated: true,
            rightsValidated: true,
            authorizationAvailable: true,
            quotaAvailable: true,
            networkAvailable: true
        )
        XCTAssertNoThrow(try context.validate())
    }

    func testRemoteHighImpactRequiresUserConfirmation() {
        XCTAssertFalse(ActionAuthorization(
            riskClass: .remoteHighImpact,
            deterministicChecksPassed: true,
            userConfirmed: false
        ).mayExecute)

        XCTAssertTrue(ActionAuthorization(
            riskClass: .remoteHighImpact,
            deterministicChecksPassed: true,
            userConfirmed: true
        ).mayExecute)
    }

    func testNoFakePauseOrResumeControls() {
        XCTAssertFalse(JobControl.cancelOnly.supportsPauseAction)
        XCTAssertFalse(JobControl.nonInterruptibleShortStep.supportsPauseAction)
        XCTAssertTrue(JobControl.pausable.supportsPauseAction)
        XCTAssertTrue(JobControl.resumable.supportsResumeAction)
    }

    func testRightsNeedCommercialPermissionAndEvidence() {
        let unusable = AssetRightsEntry(origin: "stock", commercialUseAllowed: true, evidence: [])
        XCTAssertFalse(unusable.isUsableForCommercialPublication(at: Date()))

        let usable = AssetRightsEntry(origin: "stock", commercialUseAllowed: true, evidence: ["license-receipt"])
        XCTAssertTrue(usable.isUsableForCommercialPublication(at: Date()))
    }

    func testExplorationPolicyNormalizesWeights() {
        let policy = ExplorationPolicy(coreWeight: 7, adjacentWeight: 2, explorationWeight: 1)
        XCTAssertEqual(policy.coreWeight + policy.adjacentWeight + policy.explorationWeight, 1, accuracy: 0.000001)
    }
}
