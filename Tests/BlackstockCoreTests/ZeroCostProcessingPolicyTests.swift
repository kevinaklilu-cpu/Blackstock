import XCTest
@testable import BlackstockCore

final class ZeroCostProcessingPolicyTests: XCTestCase {
    func testDefaultPolicyNeverPermitsPaidProvider() {
        let policy = ZeroCostProcessingPolicy()
        XCTAssertFalse(policy.permits(BuiltInProcessingProviders.opusClipAPI))
        XCTAssertFalse(policy.permits(BuiltInProcessingProviders.localNative))
        XCTAssertFalse(policy.permits(BuiltInProcessingProviders.cloudflareWorkersAIFree))
    }

    func testUnimplementedLocalAndFreeProvidersDoNotAppearReady() {
        let route = ZeroCostProviderSelector().select(
            capability: .transcription,
            providers: [
                BuiltInProcessingProviders.cloudflareWorkersAIFree,
                BuiltInProcessingProviders.localNative
            ]
        )
        XCTAssertEqual(route.status, .freeQuotaUnavailable)
        XCTAssertNil(route.providerID)
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
