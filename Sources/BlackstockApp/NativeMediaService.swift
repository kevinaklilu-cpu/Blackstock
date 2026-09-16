#if os(macOS)
import Foundation
import AppKit
@preconcurrency import AVFoundation
import BlackstockCore

@MainActor final class NativeMediaService: ObservableObject {
    enum MediaError: LocalizedError {
        case missingSource, exportUnavailable, exportFailed(String), frameUnavailable
        var errorDescription: String? {
            switch self {
            case .missingSource: return "Für den Export fehlt eine lokale Videodatei."
            case .exportUnavailable: return "Für diese Datei konnte kein Videoexport vorbereitet werden."
            case .exportFailed(let message): return message
            case .frameUnavailable: return "Aus dem Video konnte kein Thumbnail-Frame erzeugt werden."
            }
        }
    }

    @Published private(set) var isRendering = false
    @Published private(set) var statusMessage: String?
    private var exportSession: AVAssetExportSession?

    func sourceDuration(_ project: Project) -> Double? {
        guard let source = project.localMediaURL else { return nil }
        let seconds = AVURLAsset(url: source).duration.seconds
        return seconds.isFinite && seconds > 0 ? seconds : nil
    }

    func render(project: Project, to destination: URL, completion: @escaping (Result<URL, Error>) -> Void) {
        guard let source = project.localMediaURL else { completion(.failure(MediaError.missingSource)); return }
        let asset = AVURLAsset(url: source)
        guard let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetHighestQuality) else { completion(.failure(MediaError.exportUnavailable)); return }

        let duration = asset.duration.seconds
        let range = ProjectWorkflowEngine().clampedRange(for: project, duration: duration.isFinite ? duration : 0)
        let start = CMTime(seconds: range.lowerBound, preferredTimescale: 600)
        let length = CMTime(seconds: max(range.upperBound - range.lowerBound, 0.05), preferredTimescale: 600)

        try? FileManager.default.removeItem(at: destination)
        session.outputURL = destination
        session.outputFileType = .mp4
        session.shouldOptimizeForNetworkUse = true
        session.timeRange = CMTimeRange(start: start, duration: length)
        exportSession = session
        isRendering = true
        statusMessage = "Video wird gerendert …"

        session.exportAsynchronously { [weak self] in
            DispatchQueue.main.async {
                guard let self else { return }
                self.isRendering = false
                let active = self.exportSession
                self.exportSession = nil
                switch active?.status {
                case .completed:
                    self.statusMessage = "Render abgeschlossen"
                    completion(.success(destination))
                case .cancelled:
                    self.statusMessage = "Render abgebrochen"
                    completion(.failure(MediaError.exportFailed("Der Videoexport wurde abgebrochen.")))
                default:
                    let message = active?.error?.localizedDescription ?? "Der Videoexport ist fehlgeschlagen."
                    self.statusMessage = message
                    completion(.failure(MediaError.exportFailed(message)))
                }
            }
        }
    }

    func cancelRender() {
        exportSession?.cancelExport()
    }

    func exportThumbnail(project: Project, at seconds: Double, to destination: URL) throws -> URL {
        guard let source = project.localMediaURL else { throw MediaError.missingSource }
        let asset = AVURLAsset(url: source)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 1920, height: 1080)
        let image = try generator.copyCGImage(at: CMTime(seconds: max(seconds, 0), preferredTimescale: 600), actualTime: nil)
        let representation = NSBitmapImageRep(cgImage: image)
        guard let data = representation.representation(using: .png, properties: [:]) else { throw MediaError.frameUnavailable }
        try data.write(to: destination, options: .atomic)
        return destination
    }
}
#endif
