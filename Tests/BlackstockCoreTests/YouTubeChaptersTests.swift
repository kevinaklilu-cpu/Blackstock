import XCTest
@testable import BlackstockCore

final class YouTubeChaptersTests: XCTestCase {
    func testValidChaptersFollowYouTubeRules() throws {
        let chapters = [
            YouTubeChapter(startSeconds: 0, title: "Intro"),
            YouTubeChapter(startSeconds: 15, title: "Thema"),
            YouTubeChapter(startSeconds: 35, title: "Fazit")
        ]

        XCTAssertNoThrow(
            try YouTubeChapterValidator().validate(
                chapters,
                videoDurationSeconds: 60
            )
        )
    }

    func testFirstChapterMustStartAtZero() {
        let chapters = [
            YouTubeChapter(startSeconds: 1, title: "Intro"),
            YouTubeChapter(startSeconds: 15, title: "Thema"),
            YouTubeChapter(startSeconds: 35, title: "Fazit")
        ]

        XCTAssertThrowsError(
            try YouTubeChapterValidator().validate(
                chapters,
                videoDurationSeconds: 60
            )
        ) {
            XCTAssertEqual(
                $0 as? YouTubeChapterValidationError,
                .firstChapterMustStartAtZero
            )
        }
    }

    func testChapterMustBeAtLeastTenSecondsLong() {
        let chapters = [
            YouTubeChapter(startSeconds: 0, title: "Intro"),
            YouTubeChapter(startSeconds: 5, title: "Thema"),
            YouTubeChapter(startSeconds: 20, title: "Fazit")
        ]

        XCTAssertThrowsError(
            try YouTubeChapterValidator().validate(
                chapters,
                videoDurationSeconds: 60
            )
        ) {
            XCTAssertEqual(
                $0 as? YouTubeChapterValidationError,
                .chapterShorterThanTenSeconds(index: 0)
            )
        }
    }

    func testStoryboardBeatsBecomeSortedChapters() {
        let projectID = UUID()
        let now = Date()
        let storyboard = StoryboardPlan(
            projectID: projectID,
            beats: [
                .init(
                    title: "Mitte",
                    timeRange: .init(startSeconds: 20, durationSeconds: 10),
                    createdAt: now,
                    updatedAt: now
                ),
                .init(
                    title: "Start",
                    timeRange: .init(startSeconds: 0, durationSeconds: 20),
                    createdAt: now,
                    updatedAt: now
                ),
                .init(
                    title: "Ende",
                    timeRange: .init(startSeconds: 40, durationSeconds: 20),
                    createdAt: now,
                    updatedAt: now
                )
            ],
            updatedAt: now
        )

        let chapters = StoryboardChapterBuilder().build(from: storyboard)

        XCTAssertEqual(chapters.map(\.title), ["Start", "Mitte", "Ende"])
        XCTAssertEqual(chapters.map(\.startSeconds), [0, 20, 40])
    }

    func testDescriptionComposerKeepsExistingDescription() {
        let chapters = [
            YouTubeChapter(startSeconds: 0, title: "Intro"),
            YouTubeChapter(startSeconds: 15, title: "Thema"),
            YouTubeChapter(startSeconds: 35, title: "Fazit")
        ]

        let result = YouTubeDescriptionComposer().appendingChapters(
            description: "Beschreibung",
            chapters: chapters
        )

        XCTAssertTrue(result.hasPrefix("Beschreibung\n\n00:00 Intro"))
        XCTAssertTrue(result.contains("00:15 Thema"))
        XCTAssertTrue(result.contains("00:35 Fazit"))
    }
}
