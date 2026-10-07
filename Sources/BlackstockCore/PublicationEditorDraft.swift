import Foundation

/// Unapproved editor content is separate from the quality-checked upload package.
public struct PublicationEditorDraft: Codable, Equatable, Sendable {
    public var title: String
    public var description: String
    public var tags: String
    public var thumbnailURL: URL?
    public var thumbnailOptions: [URL]
    public static func removingGeneratedSourceFooter(_ text: String) -> String {
        text.components(separatedBy: "\n").filter { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            return !trimmed.hasPrefix("Quelle: https://")
                && !trimmed.hasPrefix("Quelle: http://")
                && !trimmed.hasPrefix("Short · Ausschnitt ")
                && !trimmed.hasPrefix("Video · Ausschnitt ")
                && trimmed != "Auszug aus dem Video:"
        }.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public init(title: String, description: String, tags: String, thumbnailURL: URL?, thumbnailOptions: [URL]) {
        self.title = title
        self.description = description
        self.tags = tags
        self.thumbnailURL = thumbnailURL
        self.thumbnailOptions = thumbnailOptions
    }
}
