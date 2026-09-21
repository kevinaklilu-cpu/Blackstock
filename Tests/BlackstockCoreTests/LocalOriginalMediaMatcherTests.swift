import XCTest
@testable import BlackstockCore

final class LocalOriginalMediaMatcherTests: XCTestCase {
    func testYouTubeIDWinsWhenFilenameContainsProviderID() {
        let matcher = LocalOriginalMediaMatcher()
        let expected = URL(fileURLWithPath: "/media/My Video dQw4w9WgXcQ.mov")
        let other = URL(fileURLWithPath: "/media/My Video.mp4")

        XCTAssertEqual(
            matcher.bestMatch(
                videoID: "dQw4w9WgXcQ",
                title: "My Video",
                fileURLs: [other, expected]
            ),
            expected
        )
    }

    func testTitleMatchAllowsCommonFilenameSuffixes() {
        let matcher = LocalOriginalMediaMatcher()
        let expected = URL(
            fileURLWithPath:
                "/media/So baust du bessere YouTube Shorts - MASTER 4K.mp4"
        )

        XCTAssertEqual(
            matcher.bestMatch(
                videoID: nil,
                title: "So baust du bessere YouTube Shorts",
                fileURLs: [expected]
            ),
            expected
        )
    }

    func testAmbiguousEqualMatchesAreRejected() {
        let matcher = LocalOriginalMediaMatcher()
        let a = URL(fileURLWithPath: "/a/Test Video Example.mov")
        let b = URL(fileURLWithPath: "/b/Test Video Example.mp4")

        XCTAssertNil(
            matcher.bestMatch(
                videoID: nil,
                title: "Test Video Example",
                fileURLs: [a, b]
            )
        )
    }

    func testUnrelatedFilesAreNotAutoBound() {
        let matcher = LocalOriginalMediaMatcher()
        let file = URL(
            fileURLWithPath:
                "/media/Completely Different Recording.mp4"
        )

        XCTAssertNil(
            matcher.bestMatch(
                videoID: "video-123",
                title: "My Selected YouTube Video",
                fileURLs: [file]
            )
        )
    }
}
