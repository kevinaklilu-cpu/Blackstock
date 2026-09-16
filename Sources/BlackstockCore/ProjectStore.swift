import Foundation
public actor ProjectStore {
    private let fileURL: URL
    private var projects: [Project] = []
    public init(fileURL: URL? = nil) {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first ?? URL(fileURLWithPath: NSTemporaryDirectory())
        self.fileURL = fileURL ?? base.appendingPathComponent("Blackstock/projects.json")
    }
    public func load() throws -> [Project] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { projects = []; return [] }
        projects = try JSONDecoder().decode([Project].self, from: Data(contentsOf: fileURL)); return projects.sorted { $0.updatedAt > $1.updatedAt }
    }
    @discardableResult public func save(_ project: Project) throws -> Project {
        var item = project; item.updatedAt = Date()
        if let index = projects.firstIndex(where: { $0.id == item.id }) { projects[index] = item } else { projects.append(item) }
        try persist(); return item
    }
    public func delete(id: UUID) throws { projects.removeAll { $0.id == id }; try persist() }
    private func persist() throws {
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(projects.sorted { $0.updatedAt > $1.updatedAt }).write(to: fileURL, options: .atomic)
    }
}
