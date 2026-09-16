#if os(macOS)
import Foundation
import BlackstockCore

@MainActor final class ReleasePackageService {
    func export(project: Project, to parentDirectory: URL) throws -> URL {
        let manifest = try ReleasePackageBuilder().manifest(for: project)
        guard let video = project.renderedOutputURL, let thumbnail = project.thumbnailURL else {
            throw ReleasePackageError.notReady(["Video oder Thumbnail fehlt"])
        }
        let safeName = sanitized(project.publishTitle ?? project.title)
        let packageURL = parentDirectory.appendingPathComponent("\(safeName)-Blackstock-Release", isDirectory: true)
        let fm = FileManager.default
        if fm.fileExists(atPath: packageURL.path) { try fm.removeItem(at: packageURL) }
        try fm.createDirectory(at: packageURL, withIntermediateDirectories: true)

        let videoTarget = packageURL.appendingPathComponent(video.lastPathComponent)
        let thumbTarget = packageURL.appendingPathComponent(thumbnail.lastPathComponent)
        try fm.copyItem(at: video, to: videoTarget)
        try fm.copyItem(at: thumbnail, to: thumbTarget)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(manifest).write(to: packageURL.appendingPathComponent("release-manifest.json"), options: .atomic)

        let metadata = """
        \(manifest.title)

        \(manifest.description)

        Tags: \(manifest.tags.joined(separator: ", "))
        Format: \(manifest.targetFormat.rawValue)
        Canvas: \(manifest.renderCanvas.label)
        """
        try metadata.data(using: .utf8)?.write(to: packageURL.appendingPathComponent("metadata.txt"), options: .atomic)
        return packageURL
    }

    private func sanitized(_ value: String) -> String {
        let invalid = CharacterSet(charactersIn: "/:\\?%*|\"<>")
        let clean = value.components(separatedBy: invalid).joined(separator: "-").trimmingCharacters(in: .whitespacesAndNewlines)
        return clean.isEmpty ? "Blackstock" : clean
    }
}
#endif
