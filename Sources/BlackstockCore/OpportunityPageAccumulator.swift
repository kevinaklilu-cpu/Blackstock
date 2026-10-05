import Foundation

/// Counts new, distinct results rather than raw provider rows. Keeps a usable
/// cursor when a bounded fetch ends so a subsequent user action can continue.
public struct OpportunityPageAccumulator {
    public private(set) var candidates: [YouTubeOpportunityCandidate] = []
    public private(set) var nextPageToken: String?
    private var seenIDs: Set<String>
    private var visitedTokens = Set<String>()

    public init(existingIDs: [String], initialToken: String? = nil) {
        seenIDs = Set(existingIDs)
        nextPageToken = initialToken
        if let initialToken { visitedTokens.insert(initialToken) }
    }

    public mutating func append(_ page: YouTubeOpportunityPage) {
        candidates.append(contentsOf: page.candidates.filter { seenIDs.insert($0.videoID).inserted })
        guard let token = page.nextPageToken, !token.isEmpty, visitedTokens.insert(token).inserted else {
            nextPageToken = nil
            return
        }
        nextPageToken = token
    }

    public func needsMore(target: Int = 50) -> Bool {
        candidates.count < target && nextPageToken != nil
    }
}
