#if os(macOS)
import Foundation
import AppKit
@preconcurrency import AVFoundation
import BlackstockCore

@MainActor final class NativeMediaService: ObservableObject {
    enum MediaError: LocalizedError, Sendable {
        case missingSource, exportUnavailable, exportFailed(String), frameUnavailable, videoTrackUnavailable
        var errorDescription: String? {
            switch self {
            case .missingSource: return "Für den Export fehlt eine lokale Videodatei."
            case .exportUnavailable: return "Für diese Datei konnte kein Videoexport vorbereitet werden."
            case .exportFailed(let message): return message
            case .frameUnavailable: return "Aus dem Video konnte kein Thumbnail-Frame erzeugt werden."
            case .videoTrackUnavailable: return "Die Videospur konnte nicht gelesen werden."
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

    func render(project: Project, to destination: URL, completion: @escaping @MainActor @Sendable (Result<URL, MediaError>) -> Void) {
        guard let source = project.localMediaURL else { completion(.failure(.missingSource)); return }
        let asset = AVURLAsset(url: source)
        guard let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetHighestQuality) else { completion(.failure(.exportUnavailable)); return }

        let duration = asset.duration.seconds
        let range = ProjectWorkflowEngine().clampedRange(for: project, duration: duration.isFinite ? duration : 0)
        session.timeRange = CMTimeRange(
            start: CMTime(seconds: range.lowerBound, preferredTimescale: 600),
            duration: CMTime(seconds: max(range.upperBound - range.lowerBound, 0.05), preferredTimescale: 600)
        )
        if project.effectiveRenderCanvas != .source {
            do { session.videoComposition = try composition(for: asset, project: project) }
            catch { completion(.failure(error as? MediaError ?? .exportFailed(error.localizedDescription))); return }
        }

        try? FileManager.default.removeItem(at: destination)
        session.outputURL = destination
        session.outputFileType = .mp4
        session.shouldOptimizeForNetworkUse = true
        exportSession = session
        isRendering = true
        statusMessage = "Video wird gerendert …"

        session.exportAsynchronously { [weak self] in
            Task { @MainActor in
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
                    completion(.failure(.exportFailed("Der Videoexport wurde abgebrochen.")))
                default:
                    let message = active?.error?.localizedDescription ?? "Der Videoexport ist fehlgeschlagen."
                    self.statusMessage = message
                    completion(.failure(.exportFailed(message)))
                }
            }
        }
    }

    func cancelRender() { exportSession?.cancelExport() }

    func exportThumbnail(project: Project, at seconds: Double, to destination: URL) throws -> URL {
        guard let source = project.localMediaURL else { throw MediaError.missingSource }
        let asset = AVURLAsset(url: source)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 1920, height: 1920)
        let image = try generator.copyCGImage(at: CMTime(seconds: max(seconds, 0), preferredTimescale: 600), actualTime: nil)
        let representation = NSBitmapImageRep(cgImage: image)
        guard let data = representation.representation(using: .png, properties: [:]) else { throw MediaError.frameUnavailable }
        try data.write(to: destination, options: .atomic)
        return destination
    }

    private func composition(for asset: AVAsset, project: Project) throws -> AVVideoComposition {
        guard let track = asset.tracks(withMediaType: .video).first else { throw MediaError.videoTrackUnavailable }
        guard let width = project.effectiveRenderCanvas.pixelWidth, let height = project.effectiveRenderCanvas.pixelHeight else { throw MediaError.videoTrackUnavailable }
        let target = CGSize(width: width, height: height)
        let transformedRect = CGRect(origin: .zero, size: track.naturalSize).applying(track.preferredTransform)
        let oriented = CGSize(width: abs(transformedRect.width), height: abs(transformedRect.height))
        guard oriented.width > 0, oriented.height > 0 else { throw MediaError.videoTrackUnavailable }

        let scale = max(target.width / oriented.width, target.height / oriented.height)
        let scaled = CGSize(width: oriented.width * scale, height: oriented.height * scale)
        let overflowX = max(scaled.width - target.width, 0)
        let overflowY = max(scaled.height - target.height, 0)

        var transform = track.preferredTransform
        transform = transform.concatenating(CGAffineTransform(translationX: -transformedRect.minX, y: -transformedRect.minY))
        transform = transform.concatenating(CGAffineTransform(scaleX: scale, y: scale))
        transform = transform.concatenating(CGAffineTransform(translationX: -overflowX * project.effectiveCropAnchorX, y: -overflowY * project.effectiveCropAnchorY))

        let layer = AVMutableVideoCompositionLayerInstruction(assetTrack: track)
        layer.setTransform(transform, at: .zero)
        let instruction = AVMutableVideoCompositionInstruction()
        instruction.timeRange = CMTimeRange(start: .zero, duration: asset.duration)
        instruction.layerInstructions = [layer]
        let composition = AVMutableVideoComposition()
        composition.instructions = [instruction]
        composition.renderSize = target
        composition.frameDuration = CMTime(value: 1, timescale: 30)
        return composition
    }
}
#endif
