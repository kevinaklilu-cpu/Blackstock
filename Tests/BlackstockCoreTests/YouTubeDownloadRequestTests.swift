import XCTest
@testable import BlackstockCore

final class YouTubeDownloadRequestTests: XCTestCase {
    func testOnlyYouTubeHTTPLinksAreRecognized() {
        for value in ["https://www.youtube.com/watch?v=abc", "https://youtu.be/abc", "https://m.youtube.com/shorts/abc"] {
            XCTAssertTrue(YouTubeDownloadRequest.accepts(URL(string: value)!))
        }
        for value in ["https://youtube.com.attacker.test/watch", "file:///youtube.com", "https://notyoutube.com", "ftp://youtube.com/watch"] {
            XCTAssertFalse(YouTubeDownloadRequest.accepts(URL(string: value)!))
        }
    }

    func testProgressRejectsDiagnosticsAndNonFiniteValues() {
        XCTAssertEqual(YouTubeDownloadRequest.progress("BLACKSTOCK_PROGRESS: 42.5%"), 0.425)
        XCTAssertEqual(YouTubeDownloadRequest.progress("BLACKSTOCK_PROGRESS: 150%"), 1)
        XCTAssertNil(YouTubeDownloadRequest.progress("ERROR: unavailable"))
        XCTAssertNil(YouTubeDownloadRequest.progress("BLACKSTOCK_PROGRESS: nan%"))
        XCTAssertNil(YouTubeDownloadRequest.progress("BLACKSTOCK_PROGRESS: N/A"))
    }

    func testConfigurationAndPlaylistCannotOverrideDownload() {
        let url = URL(string: "https://youtube.com/watch?v=abc&list=xyz")!
        let output = URL(fileURLWithPath: "/tmp/a space/video.mp4")
        let args = YouTubeDownloadRequest.arguments(url: url, output: output)
        XCTAssertTrue(args.contains("--ignore-config"))
        XCTAssertTrue(args.contains("--no-playlist"))
        XCTAssertTrue(args.contains(output.path))
        XCTAssertEqual(Array(args.suffix(2)), ["--", url.absoluteString])
    }
}
