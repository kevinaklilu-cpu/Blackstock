import Foundation

public struct LocalOriginalMediaMatcher: Sendable {
    public static let supportedExtensions: Set<String> = [
        "mov", "mp4", "m4v"
    ]

    public init() {}

    public func bestMatch(
        videoID: String?,
        title: String,
        fileURLs: [URL]
    ) -> URL? {
        let ranked = fileURLs.compactMap { url -> (URL, Int)? in
            let score = score(
                videoID: videoID,
                title: title,
                fileURL: url
            )
            return score > 0 ? (url, score) : nil
        }
        .sorted {
            if $0.1 == $1.1 {
                return $0.0.path < $1.0.path
            }
            return $0.1 > $1.1
        }

        guard let first = ranked.first,
              first.1 >= 700 else {
            return nil
        }
        if ranked.count > 1,
           ranked[1].1 == first.1 {
            return nil
        }
        return first.0
    }

    public func score(
        videoID: String?,
        title: String,
        fileURL: URL
    ) -> Int {
        let ext = fileURL.pathExtension.lowercased()
        guard Self.supportedExtensions.contains(ext) else {
            return 0
        }

        let stem = fileURL.deletingPathExtension()
            .lastPathComponent
        let foldedStem = stem.folding(
            options: [.caseInsensitive, .diacriticInsensitive],
            locale: Locale(identifier: "en_US_POSIX")
        )
        if let videoID {
            let id = videoID.trimmingCharacters(
                in: .whitespacesAndNewlines
            )
            if !id.isEmpty,
               foldedStem.localizedCaseInsensitiveContains(id) {
                return 1000
            }
        }

        let titleTokens = normalizedTokens(title)
        let stemTokens = normalizedTokens(stem)
        guard !titleTokens.isEmpty,
              !stemTokens.isEmpty else {
            return 0
        }

        let normalizedTitle = titleTokens.joined(separator: " ")
        let normalizedStem = stemTokens.joined(separator: " ")
        if normalizedTitle == normalizedStem {
            return 900
        }
        if normalizedTitle.count >= 8,
           normalizedStem.contains(normalizedTitle) {
            return 850
        }
        if normalizedStem.count >= 8,
           normalizedTitle.contains(normalizedStem) {
            return 820
        }

        let titleSet = Set(
            titleTokens.filter { $0.count > 2 }
        )
        let stemSet = Set(
            stemTokens.filter { $0.count > 2 }
        )
        guard titleSet.count >= 3 else {
            return 0
        }

        let overlap = titleSet.intersection(stemSet).count
        let coverage = Double(overlap)
            / Double(titleSet.count)
        guard overlap >= 3,
              coverage >= 0.85 else {
            return 0
        }
        return 700 + Int((coverage * 100).rounded())
    }

    private func normalizedTokens(
        _ value: String
    ) -> [String] {
        let folded = value.folding(
            options: [.caseInsensitive, .diacriticInsensitive],
            locale: Locale(identifier: "en_US_POSIX")
        )
        let normalized = folded.unicodeScalars.map { scalar in
            CharacterSet.alphanumerics.contains(scalar)
                ? String(scalar)
                : " "
        }
        .joined()
        return normalized
            .split(whereSeparator: { $0.isWhitespace })
            .map(String.init)
    }
}
