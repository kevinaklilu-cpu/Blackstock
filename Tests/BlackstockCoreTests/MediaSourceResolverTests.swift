import XCTest
@testable import BlackstockCore

final class MediaSourceResolverTests: XCTestCase {
    func testLocalDownloaderResolvesWithoutProviderConfiguration() {
        let source = MediaSourceReference(provider: .youtube,
            pageURL: URL(string: "https://youtu.be/abc")!, externalID: "abc", discoveredAt: Date())
        let result = MediaSourceResolver().resolve(source, approvedProvider: nil,
            localYouTubeDownloaderAvailable: true)
        XCTAssertEqual(result.status, .ingestReady)
        XCTAssertEqual(result.ingestProviderID, "local-youtube-download")
    }

    func testYouTubeLinkIsPlaybackOnlyUntilApprovedIngestProviderExists() {
        let source = MediaSourceReference(
            provider: .youtube,
            pageURL: URL(string: "https://www.youtube.com/watch?v=abc")!,
            externalID: "abc",
            discoveredAt: Date()
        )

        let resolved = MediaSourceResolver().resolve(source, approvedProvider: nil)
        XCTAssertEqual(resolved.status, .providerApprovalRequired)
        XCTAssertNil(resolved.ingestProviderID)
    }

    func testVerifiedApprovedProviderCanResolveYouTubeLinkForIngest() {
        let source = MediaSourceReference(
            provider: .youtube,
            pageURL: URL(string: "https://www.youtube.com/watch?v=abc")!,
            externalID: "abc",
            discoveredAt: Date()
        )
        let provider = RemoteIngestProviderAuthorization(
            providerID: "partner-1",
            supportsYouTubeLinks: true,
            youtubeWrittenApprovalReference: "approval-ref",
            verifiedAt: Date()
        )

        let resolved = MediaSourceResolver().resolve(source, approvedProvider: provider)
        XCTAssertEqual(resolved.status, .ingestReady)
        XCTAssertEqual(resolved.ingestProviderID, "partner-1")
    }

    func testRightsClaimAloneDoesNotTurnUnapprovedYouTubeIngestOn() {
        let provider = RemoteIngestProviderAuthorization(
            providerID: "unverified",
            supportsYouTubeLinks: true,
            youtubeWrittenApprovalReference: nil,
            verifiedAt: Date()
        )
        XCTAssertFalse(provider.mayIngestYouTubeLinks)
    }
}
