import Foundation
import Security

struct StoredOAuthCredentials: Codable, Hashable {
    var clientID: String
    var clientSecret: String
}

struct OAuthTokenSet: Codable, Hashable {
    var accessToken: String
    var refreshToken: String?
    var expiresAt: Date
    var scope: String

    var needsRefresh: Bool { Date().addingTimeInterval(90) >= expiresAt }
}

enum ProjectStage: String, Codable, CaseIterable {
    case source = "Quelle"
    case analyzed = "Analysiert"
    case edited = "Geschnitten"
    case rendered = "Gerendert"
    case uploading = "Upload"
    case published = "Veröffentlicht"
    case failed = "Fehler"
}

struct UploadRecoveryState: Codable, Hashable {
    var sessionURL: URL
    var nextByte: Int64
    var fileSize: Int64
    var updatedAt: Date
}

struct PublicationSettings: Codable, Hashable {
    enum Privacy: String, Codable, CaseIterable, Identifiable {
        case `private`, unlisted, `public`
        var id: String { rawValue }
        var label: String {
            switch self {
            case .private: return "Privat"
            case .unlisted: return "Nicht gelistet"
            case .public: return "Öffentlich"
            }
        }
    }

    var title: String
    var description: String
    var tags: [String]
    var categoryID: String
    var privacy: Privacy
    var madeForKids: Bool
    var defaultLanguage: String
    var playlistID: String?
    var scheduledAt: Date?
    var thumbnailPath: String?
}

struct BlackstockProject: Identifiable, Codable, Hashable {
    var id: UUID
    var createdAt: Date
    var updatedAt: Date
    var channelID: String?
    var sourcePath: String
    var sourceBookmark: Data?
    var rightsConfirmed: Bool
    var transcriptWords: [TranscriptWord]?
    var transcriptText: String?
    var clipCandidates: [ClipCandidate]?
    var selectedClip: ClipCandidate?
    var captionStyle: CaptionStyle
    var captions: [CaptionCue]
    var outputPortrait: Bool?
    var renderedPath: String?
    var stage: ProjectStage
    var publication: PublicationSettings
    var uploadRecovery: UploadRecoveryState?
    var youtubeVideoID: String?
    var lastError: String?

    init(sourceURL: URL, channelID: String?) {
        id = UUID()
        createdAt = Date()
        updatedAt = Date()
        self.channelID = channelID
        sourcePath = sourceURL.path
        sourceBookmark = try? sourceURL.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil)
        rightsConfirmed = false
        transcriptWords = nil
        transcriptText = nil
        clipCandidates = nil
        selectedClip = nil
        captionStyle = .clean
        captions = []
        outputPortrait = nil
        renderedPath = nil
        stage = .source
        publication = .init(
            title: sourceURL.deletingPathExtension().lastPathComponent,
            description: "",
            tags: [],
            categoryID: "22",
            privacy: .private,
            madeForKids: false,
            defaultLanguage: "de",
            playlistID: nil,
            scheduledAt: nil,
            thumbnailPath: nil
        )
        uploadRecovery = nil
        youtubeVideoID = nil
        lastError = nil
    }

    func resolvedSourceURL() -> URL {
        if let sourceBookmark {
            var stale = false
            if let resolved = try? URL(resolvingBookmarkData: sourceBookmark, options: [.withSecurityScope], relativeTo: nil, bookmarkDataIsStale: &stale) {
                return resolved
            }
        }
        return URL(fileURLWithPath: sourcePath)
    }
}

@MainActor
final class ProjectStore: ObservableObject {
    @Published private(set) var projects: [BlackstockProject] = []
    @Published var selectedProjectID: UUID?

    private let fileURL: URL

    init(fileManager: FileManager = .default) {
        let base = (try? fileManager.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true))
            ?? fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support", isDirectory: true)
        let directory = base.appendingPathComponent("Blackstock", isDirectory: true)
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        fileURL = directory.appendingPathComponent("projects.json")
        load()
    }

    var selected: BlackstockProject? {
        guard let selectedProjectID else { return projects.first }
        return projects.first(where: { $0.id == selectedProjectID })
    }

    @discardableResult
    func create(sourceURL: URL, channelID: String?) -> UUID {
        let project = BlackstockProject(sourceURL: sourceURL, channelID: channelID)
        projects.insert(project, at: 0)
        selectedProjectID = project.id
        persist()
        return project.id
    }

    func select(_ id: UUID) {
        guard projects.contains(where: { $0.id == id }) else { return }
        selectedProjectID = id
    }

    func update(_ project: BlackstockProject) {
        var copy = project
        copy.updatedAt = Date()
        if let index = projects.firstIndex(where: { $0.id == copy.id }) {
            projects[index] = copy
        } else {
            projects.insert(copy, at: 0)
        }
        projects.sort { $0.updatedAt > $1.updatedAt }
        selectedProjectID = copy.id
        persist()
    }

    func remove(_ id: UUID) {
        projects.removeAll { $0.id == id }
        if selectedProjectID == id { selectedProjectID = projects.first?.id }
        persist()
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder.blackstock.decode([BlackstockProject].self, from: data) else { return }
        projects = decoded.sorted { $0.updatedAt > $1.updatedAt }
        selectedProjectID = projects.first?.id
    }

    private func persist() {
        guard let data = try? JSONEncoder.blackstock.encode(projects) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}

extension JSONEncoder {
    static var blackstock: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}

extension JSONDecoder {
    static var blackstock: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

final class KeychainStore {
    private let service = "de.blackstock.next"

    func save<T: Encodable>(_ value: T, account: String) throws {
        let data = try JSONEncoder.blackstock.encode(value)
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(base as CFDictionary)
        var add = base
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = SecItemAdd(add as CFDictionary, nil)
        guard status == errSecSuccess else { throw YouTubeUploadError(message: "Sichere Speicherung fehlgeschlagen (Keychain \(status)).") }
    }

    func load<T: Decodable>(_ type: T.Type, account: String) -> T? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return try? JSONDecoder.blackstock.decode(type, from: data)
    }

    func delete(account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }
}
