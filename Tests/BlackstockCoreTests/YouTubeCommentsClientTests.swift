import XCTest
@testable import BlackstockCore

final class YouTubeCommentsClientTests: XCTestCase {
    func testListThreadsRequestUsesReadOnlyPlainTextParameters() throws {
        let request = try YouTubeCommentsClient(
            accessToken: "access-token"
        ).listThreadsRequest(
            videoID: "video-123",
            maxResults: 150,
            order: .time,
            pageToken: " next-page "
        )

        let url = try XCTUnwrap(request.url)
        let components = try XCTUnwrap(
            URLComponents(
                url: url,
                resolvingAgainstBaseURL: false
            )
        )
        let query = Dictionary(
            uniqueKeysWithValues: (components.queryItems ?? []).map {
                ($0.name, $0.value ?? "")
            }
        )

        XCTAssertEqual(
            url.host,
            "www.googleapis.com"
        )
        XCTAssertEqual(
            url.path,
            "/youtube/v3/commentThreads"
        )
        XCTAssertEqual(query["part"], "snippet")
        XCTAssertEqual(query["videoId"], "video-123")
        XCTAssertEqual(query["maxResults"], "100")
        XCTAssertEqual(query["order"], "time")
        XCTAssertEqual(query["textFormat"], "plainText")
        XCTAssertEqual(query["pageToken"], "next-page")
        XCTAssertEqual(
            request.value(
                forHTTPHeaderField: "Authorization"
            ),
            "Bearer access-token"
        )
        XCTAssertEqual(request.httpMethod, "GET")
    }

    func testCommentThreadResponsePreservesProviderFacts() throws {
        let data = Data(
            """
            {
              "nextPageToken": "next",
              "items": [
                {
                  "id": "thread-1",
                  "snippet": {
                    "channelId": "channel-A",
                    "videoId": "video-A",
                    "canReply": true,
                    "totalReplyCount": 3,
                    "isPublic": true,
                    "topLevelComment": {
                      "id": "comment-1",
                      "snippet": {
                        "authorDisplayName": "Creator Fan",
                        "authorProfileImageUrl": "https://example.com/avatar.jpg",
                        "authorChannelId": {
                          "value": "author-channel"
                        },
                        "textDisplay": "Gutes Video!",
                        "likeCount": 7,
                        "publishedAt": "2026-09-19T12:00:00Z",
                        "updatedAt": "2026-09-19T12:05:00Z"
                      }
                    }
                  }
                }
              ]
            }
            """.utf8
        )
        let retrievedAt = Date(
            timeIntervalSince1970: 1_789_815_000
        )

        let page = try YouTubeCommentsClient(
            accessToken: "token"
        ).decodePage(
            data,
            retrievedAt: retrievedAt
        )

        XCTAssertEqual(page.nextPageToken, "next")
        XCTAssertEqual(page.retrievedAt, retrievedAt)
        XCTAssertEqual(page.threads.count, 1)

        let thread = try XCTUnwrap(page.threads.first)
        XCTAssertEqual(thread.id, "thread-1")
        XCTAssertEqual(thread.channelID, "channel-A")
        XCTAssertEqual(thread.videoID, "video-A")
        XCTAssertEqual(thread.totalReplyCount, 3)
        XCTAssertEqual(thread.canReply, true)
        XCTAssertEqual(thread.isPublic, true)
        XCTAssertEqual(
            thread.topLevelComment.authorDisplayName,
            "Creator Fan"
        )
        XCTAssertEqual(
            thread.topLevelComment.authorChannelID,
            "author-channel"
        )
        XCTAssertEqual(
            thread.topLevelComment.textDisplay,
            "Gutes Video!"
        )
        XCTAssertEqual(thread.topLevelComment.likeCount, 7)
    }

    func testCommentsDisabledProviderErrorIsDistinct() {
        let data = Data(
            """
            {
              "error": {
                "errors": [
                  {"reason": "commentsDisabled"}
                ]
              }
            }
            """.utf8
        )

        XCTAssertEqual(
            YouTubeCommentsClient.error(
                statusCode: 403,
                data: data
            ),
            .commentsDisabled
        )
    }

    func testMissingVideoIDIsRejectedBeforeRequest() {
        XCTAssertThrowsError(
            try YouTubeCommentsClient(
                accessToken: "token"
            ).listThreadsRequest(
                videoID: "   ",
                maxResults: 20,
                order: .time,
                pageToken: nil
            )
        ) { error in
            XCTAssertEqual(
                error as? YouTubeCommentsError,
                .invalidVideoID
            )
        }
    }
}
