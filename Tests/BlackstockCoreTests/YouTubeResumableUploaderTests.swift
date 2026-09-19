import XCTest
@testable import BlackstockCore

final class YouTubeResumableUploaderTests: XCTestCase {
    func testResumeStatus308ReturnsNextOffset() throws {
        let status = try YouTubeResumableUploader.resumableSessionStatus(
            statusCode: 308,
            rangeHeader: "bytes=0-1048575",
            responseData: Data()
        )

        XCTAssertEqual(
            status,
            .incomplete(nextOffset: 1_048_576)
        )
    }

    func testResumeStatus308WithoutRangeRestartsAtZero() throws {
        let status = try YouTubeResumableUploader.resumableSessionStatus(
            statusCode: 308,
            rangeHeader: nil,
            responseData: Data()
        )

        XCTAssertEqual(
            status,
            .incomplete(nextOffset: 0)
        )
    }

    func testSuccessfulStatusWithVideoIDReconcilesRemoteCompletion() throws {
        let status = try YouTubeResumableUploader.resumableSessionStatus(
            statusCode: 200,
            rangeHeader: nil,
            responseData: Data(#"{"id":"video-123"}"#.utf8)
        )

        XCTAssertEqual(
            status,
            .completed(videoID: "video-123")
        )
    }

    func testSuccessfulStatusWithoutVideoIDIsNotTreatedAsComplete() {
        XCTAssertThrowsError(
            try YouTubeResumableUploader.resumableSessionStatus(
                statusCode: 200,
                rangeHeader: nil,
                responseData: Data(#"{"kind":"youtube#video"}"#.utf8)
            )
        ) {
            XCTAssertEqual(
                $0 as? YouTubeUploadError,
                .missingVideoID
            )
        }
    }

    func testFailedStatusRemainsUploadFailure() {
        XCTAssertThrowsError(
            try YouTubeResumableUploader.resumableSessionStatus(
                statusCode: 503,
                rangeHeader: nil,
                responseData: Data()
            )
        ) {
            XCTAssertEqual(
                $0 as? YouTubeUploadError,
                .uploadFailed(503)
            )
        }
    }
}
