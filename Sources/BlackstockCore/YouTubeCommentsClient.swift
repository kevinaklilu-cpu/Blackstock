import Foundation

public enum YouTubeCommentThreadOrder: String, Codable, Sendable, CaseIterable {
    case time
    case relevance

    public var germanTitle: String {
        switch self {
        case .time: return "Neueste"
        case .relevance: return "YouTube-Relevanz"
        }
    }
}

public struct YouTubeCommentSnapshot: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let authorDisplayName: String
    public let authorChannelID: String?
    public let authorProfileImageURL: URL?
    public let textDisplay: String
    public let likeCount: Int?
    public let publishedAt: Date?
    public let updatedAt: Date?

    public init(
        id: String,
        authorDisplayName: String,
        authorChannelID: String?,
        authorProfileImageURL: URL?,
        textDisplay: String,
        likeCount: Int?,
        publishedAt: Date?,
        updatedAt: Date?
    ) {
        self.id = id
        self.authorDisplayName = authorDisplayName
        self.authorChannelID = authorChannelID
        self.authorProfileImageURL = authorProfileImageURL
        self.textDisplay = textDisplay
        self.likeCount = likeCount
        self.publishedAt = publishedAt
        self.updatedAt = updatedAt
    }
}

public struct YouTubeCommentThreadSnapshot: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let channelID: String
    public let videoID: String
    public let topLevelComment: YouTubeCommentSnapshot
    public let totalReplyCount: Int?
    public let canReply: Bool?
    public let isPublic: Bool?
    public let retrievedAt: Date

    public init(
        id: String,
        channelID: String,
        videoID: String,
        topLevelComment: YouTubeCommentSnapshot,
        totalReplyCount: Int?,
        canReply: Bool?,
        isPublic: Bool?,
        retrievedAt: Date
    ) {
        self.id = id
        self.channelID = channelID
        self.videoID = videoID
        self.topLevelComment = topLevelComment
        self.totalReplyCount = totalReplyCount
        self.canReply = canReply
        self.isPublic = isPublic
        self.retrievedAt = retrievedAt
    }
}

public struct YouTubeCommentThreadPage: Codable, Sendable, Equatable {
    public let threads: [YouTubeCommentThreadSnapshot]
    public let nextPageToken: String?
    public let retrievedAt: Date

    public init(
        threads: [YouTubeCommentThreadSnapshot],
        nextPageToken: String?,
        retrievedAt: Date
    ) {
        self.threads = threads
        self.nextPageToken = nextPageToken
        self.retrievedAt = retrievedAt
    }
}

public enum YouTubeCommentContextError: Error, Sendable, Equatable {
    case unexpectedThreadContext
}

public struct YouTubeCommentContextGuard: Sendable {
    public init() {}

    public func validate(
        page: YouTubeCommentThreadPage,
        expectedVideoID: String,
        expectedChannelID: String
    ) throws {
        guard page.threads.allSatisfy({
            $0.videoID == expectedVideoID
            && $0.channelID == expectedChannelID
        }) else {
            throw YouTubeCommentContextError.unexpectedThreadContext
        }
    }
}

public enum YouTubeCommentsError: Error, Sendable, Equatable {
    case invalidVideoID
    case invalidResponse
    case unauthorized
    case commentsDisabled
    case forbidden
    case videoNotFound
    case api(Int)
}

public struct YouTubeCommentsClient: Sendable {
    public let accessToken: String

    public init(accessToken: String) {
        self.accessToken = accessToken
    }

    public func listThreads(
        videoID: String,
        maxResults: Int = 20,
        order: YouTubeCommentThreadOrder = .time,
        pageToken: String? = nil,
        session: URLSession = .shared,
        now: Date = Date()
    ) async throws -> YouTubeCommentThreadPage {
        let request = try listThreadsRequest(
            videoID: videoID,
            maxResults: maxResults,
            order: order,
            pageToken: pageToken
        )
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw YouTubeCommentsError.invalidResponse
        }

        guard 200..<300 ~= http.statusCode else {
            throw Self.error(
                statusCode: http.statusCode,
                data: data
            )
        }

        return try decodePage(
            data,
            retrievedAt: now
        )
    }

    func listThreadsRequest(
        videoID: String,
        maxResults: Int,
        order: YouTubeCommentThreadOrder,
        pageToken: String?
    ) throws -> URLRequest {
        let trimmedVideoID = videoID.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard !trimmedVideoID.isEmpty else {
            throw YouTubeCommentsError.invalidVideoID
        }

        var components = URLComponents(
            string: "https://www.googleapis.com/youtube/v3/commentThreads"
        )!
        var queryItems: [URLQueryItem] = [
            .init(name: "part", value: "snippet"),
            .init(name: "videoId", value: trimmedVideoID),
            .init(
                name: "maxResults",
                value: String(min(max(maxResults, 1), 100))
            ),
            .init(name: "order", value: order.rawValue),
            .init(name: "textFormat", value: "plainText")
        ]
        if let pageToken = pageToken?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !pageToken.isEmpty {
            queryItems.append(
                .init(name: "pageToken", value: pageToken)
            )
        }
        components.queryItems = queryItems

        var request = URLRequest(url: components.url!)
        request.setValue(
            "Bearer \(accessToken)",
            forHTTPHeaderField: "Authorization"
        )
        return request
    }

    func decodePage(
        _ data: Data,
        retrievedAt: Date
    ) throws -> YouTubeCommentThreadPage {
        let response = try JSONDecoder.youtubeComments.decode(
            CommentThreadListResponse.self,
            from: data
        )

        let threads = response.items.map { item in
            let top = item.snippet.topLevelComment
            return YouTubeCommentThreadSnapshot(
                id: item.id,
                channelID: item.snippet.channelId,
                videoID: item.snippet.videoId,
                topLevelComment: YouTubeCommentSnapshot(
                    id: top.id,
                    authorDisplayName: top.snippet.authorDisplayName,
                    authorChannelID: top.snippet.authorChannelId?.value,
                    authorProfileImageURL: top.snippet.authorProfileImageUrl,
                    textDisplay: top.snippet.textDisplay,
                    likeCount: top.snippet.likeCount,
                    publishedAt: top.snippet.publishedAt,
                    updatedAt: top.snippet.updatedAt
                ),
                totalReplyCount: item.snippet.totalReplyCount,
                canReply: item.snippet.canReply,
                isPublic: item.snippet.isPublic,
                retrievedAt: retrievedAt
            )
        }

        return YouTubeCommentThreadPage(
            threads: threads,
            nextPageToken: response.nextPageToken,
            retrievedAt: retrievedAt
        )
    }

    static func error(
        statusCode: Int,
        data: Data
    ) -> YouTubeCommentsError {
        if statusCode == 401 {
            return .unauthorized
        }

        let reasons = (
            try? JSONDecoder().decode(
                GoogleAPIErrorEnvelope.self,
                from: data
            )
        )?.error.errors.map(\.reason) ?? []

        if reasons.contains("commentsDisabled") {
            return .commentsDisabled
        }
        if reasons.contains("videoNotFound") {
            return .videoNotFound
        }
        if statusCode == 403 {
            return .forbidden
        }
        return .api(statusCode)
    }
}

private struct CommentThreadListResponse: Decodable {
    let nextPageToken: String?
    let items: [CommentThreadItem]
}

private struct CommentThreadItem: Decodable {
    let id: String
    let snippet: CommentThreadSnippet
}

private struct CommentThreadSnippet: Decodable {
    let channelId: String
    let videoId: String
    let topLevelComment: CommentItem
    let canReply: Bool?
    let totalReplyCount: Int?
    let isPublic: Bool?
}

private struct CommentItem: Decodable {
    let id: String
    let snippet: CommentSnippet
}

private struct CommentSnippet: Decodable {
    let authorDisplayName: String
    let authorProfileImageUrl: URL?
    let authorChannelId: AuthorChannelID?
    let textDisplay: String
    let likeCount: Int?
    let publishedAt: Date?
    let updatedAt: Date?
}

private struct AuthorChannelID: Decodable {
    let value: String
}

private struct GoogleAPIErrorEnvelope: Decodable {
    let error: GoogleAPIErrorBody
}

private struct GoogleAPIErrorBody: Decodable {
    let errors: [GoogleAPIErrorItem]
}

private struct GoogleAPIErrorItem: Decodable {
    let reason: String
}

private extension JSONDecoder {
    static var youtubeComments: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
