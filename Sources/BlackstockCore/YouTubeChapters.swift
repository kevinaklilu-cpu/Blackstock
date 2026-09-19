import Foundation

public struct YouTubeChapter: Codable, Sendable, Equatable, Identifiable {
    public let id: UUID
    public let startSeconds: Double
    public let title: String

    public init(
        id: UUID = UUID(),
        startSeconds: Double,
        title: String
    ) {
        self.id = id
        self.startSeconds = max(0, startSeconds)
        self.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

public enum YouTubeChapterValidationError: Error, Sendable, Equatable {
    case fewerThanThreeChapters
    case firstChapterMustStartAtZero
    case nonAscendingTimestamps
    case chapterShorterThanTenSeconds(index: Int)
    case emptyTitle(index: Int)
}

public struct YouTubeChapterValidator: Sendable {
    public init() {}

    public func validate(
        _ chapters: [YouTubeChapter],
        videoDurationSeconds: Double
    ) throws {
        guard chapters.count >= 3 else {
            throw YouTubeChapterValidationError.fewerThanThreeChapters
        }
        guard chapters[0].startSeconds < 0.5 else {
            throw YouTubeChapterValidationError.firstChapterMustStartAtZero
        }

        for index in chapters.indices {
            guard !chapters[index].title.isEmpty else {
                throw YouTubeChapterValidationError.emptyTitle(index: index)
            }

            if index > 0 {
                guard chapters[index].startSeconds > chapters[index - 1].startSeconds else {
                    throw YouTubeChapterValidationError.nonAscendingTimestamps
                }
            }

            let end = index + 1 < chapters.count
                ? chapters[index + 1].startSeconds
                : videoDurationSeconds
            guard end - chapters[index].startSeconds >= 10 else {
                throw YouTubeChapterValidationError.chapterShorterThanTenSeconds(
                    index: index
                )
            }
        }
    }
}

public struct StoryboardChapterBuilder: Sendable {
    public init() {}

    public func build(
        from storyboard: StoryboardPlan
    ) -> [YouTubeChapter] {
        storyboard.beats.compactMap { beat in
            guard let range = beat.timeRange else { return nil }
            return YouTubeChapter(
                startSeconds: range.startSeconds,
                title: beat.title
            )
        }
        .sorted { $0.startSeconds < $1.startSeconds }
    }
}

public struct YouTubeDescriptionComposer: Sendable {
    public init() {}

    public func appendingChapters(
        description: String,
        chapters: [YouTubeChapter]
    ) -> String {
        let clean = description.trimmingCharacters(in: .whitespacesAndNewlines)
        let chapterText = chapters.map {
            "\(Self.timestamp($0.startSeconds)) \($0.title)"
        }
        .joined(separator: "\n")

        if clean.isEmpty {
            return chapterText
        }
        return clean + "\n\n" + chapterText
    }

    public static func timestamp(_ seconds: Double) -> String {
        let total = max(Int(seconds.rounded(.down)), 0)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60

        if hours > 0 {
            return String(
                format: "%02d:%02d:%02d",
                hours,
                minutes,
                secs
            )
        }
        return String(
            format: "%02d:%02d",
            minutes,
            secs
        )
    }
}
