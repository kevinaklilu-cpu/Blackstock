import Foundation

/// Unapproved editor content is separate from the quality-checked upload package.
public struct PublicationEditorDraft: Codable, Equatable, Sendable {
    public var title: String
    public var description: String
    public var tags: String
    public var thumbnailURL: URL?
    public var thumbnailOptions: [URL]
    public init(title: String, description: String, tags: String, thumbnailURL: URL?, thumbnailOptions: [URL]) {
        self.title = title
        self.description = description
        self.tags = tags
        self.thumbnailURL = thumbnailURL
        self.thumbnailOptions = thumbnailOptions
    }
}
