import XCTest
@testable import BlackstockCore

final class ZeroCostProcessingPolicyTests: XCTestCase {
    func testDefaultPolicyNeverPermitsPaidProvider() {
        let policy = ZeroCostProcessingPolicy()
        XCTAssertFalse(policy.permits(BuiltInProcessingProviders.opusClipAPI))
        XCTAssertTrue(policy.permits(BuiltInProcessingProviders.localNative))
        XCTAssertFalse(policy.permits(BuiltInProcessingProviders.cloudflareWorkersAIFree))
    }

    func testImplementedLocalRenderWinsWithoutExternalCost() {
        let route = ZeroCostProviderSelector().select(
            capability: .rendering,
            providers: [
                BuiltInProcessingProviders.opusClipAPI,
                BuiltInProcessingProviders.localNative
            ]
        )
        XCTAssertEqual(route.status, .ready)
        XCTAssertEqual(route.providerID, "blackstock.local")
    }

    func testUnimplementedTranscriptionDoesNotAppearReady() {
        let route = ZeroCostProviderSelector().select(
            capability: .transcription,
            providers: [
                BuiltInProcessingProviders.cloudflareWorkersAIFree,
                BuiltInProcessingProviders.plannedLocalIntelligence
            ]
        )
        XCTAssertEqual(route.status, .freeQuotaUnavailable)
        XCTAssertNil(route.providerID)
    }

    func testImplementedLocalVisionReframingIsZeroCostAndRuntimeGated() {
        let unavailable = BuiltInProcessingProviders.localVision(
            available: false,
            lastVerifiedAt: Date()
        )
        let available = BuiltInProcessingProviders.localVision(
            available: true,
            lastVerifiedAt: Date()
        )

        XCTAssertFalse(ZeroCostProcessingPolicy().permits(unavailable))
        XCTAssertTrue(ZeroCostProcessingPolicy().permits(available))

        let route = ZeroCostProviderSelector().select(
            capability: .reframing,
            providers: [
                BuiltInProcessingProviders.opusClipAPI,
                available
            ]
        )
        XCTAssertEqual(route.status, .ready)
        XCTAssertEqual(route.providerID, "blackstock.local.vision")
    }

    func testLocalSpeechProviderIsRuntimeGated() {
        let unavailable = BuiltInProcessingProviders.localSpeech(
            available: false,
            lastVerifiedAt: Date()
        )
        let available = BuiltInProcessingProviders.localSpeech(
            available: true,
            lastVerifiedAt: Date()
        )

        XCTAssertFalse(ZeroCostProcessingPolicy().permits(unavailable))
        XCTAssertTrue(ZeroCostProcessingPolicy().permits(available))

        let route = ZeroCostProviderSelector().select(
            capability: .transcription,
            providers: [available]
        )
        XCTAssertEqual(route.status, .ready)
        XCTAssertEqual(route.providerID, "blackstock.local.speech")
    }

    func testFreeExternalProviderCanBeUsedWhenLocalCapabilityIsUnavailable() {
        let route = ZeroCostProviderSelector().select(
            capability: .youtubeDiscovery,
            providers: [BuiltInProcessingProviders.youtubeOfficial]
        )
        XCTAssertEqual(route.status, .ready)
        XCTAssertEqual(route.providerID, "youtube.official")
    }

    func testPaidProviderIsNotAutomaticFallback() {
        let route = ZeroCostProviderSelector().select(
            capability: .remoteVideoIngest,
            providers: [BuiltInProcessingProviders.opusClipAPI]
        )
        XCTAssertEqual(route.status, .externalProviderRequired)
        XCTAssertNil(route.providerID)
    }

    func testUnavailableFreeQuotaDoesNotFallThroughToPaid() {
        let exhausted = ProcessingProviderDescriptor(
            id: "free.exhausted",
            displayName: "Free exhausted",
            capabilities: [.remoteVideoIngest],
            costClass: .freeQuota,
            requiresPaymentMethod: false,
            freeQuotaDescription: "exhausted",
            available: false,
            lastVerifiedAt: Date()
        )

        let route = ZeroCostProviderSelector().select(
            capability: .remoteVideoIngest,
            providers: [exhausted, BuiltInProcessingProviders.opusClipAPI]
        )
        XCTAssertEqual(route.status, .freeQuotaUnavailable)
        XCTAssertNil(route.providerID)
    }
}
