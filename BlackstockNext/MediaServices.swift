import Foundation
import AVFoundation
import Speech
import CoreGraphics

@available(macOS 13.0, *)
public enum MediaInspector {
    public static func inspect(_ url: URL) async throws -> MediaInfo {
        let asset = AVURLAsset(url: url)
        let durationValue = try await asset.load(.duration)
        let videoTracks = try await asset.loadTracks(withMediaType: .video)
        guard let video = videoTracks.first else { throw BlackstockError.noVideoTrack }
        let naturalSize = try await video.load(.naturalSize)
        let transform = try await video.load(.preferredTransform)
        let fps = Double(try await video.load(.nominalFrameRate))
        let transformed = CGRect(origin: .zero, size: naturalSize).applying(transform)
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) ?? 0
        return MediaInfo(url: url, duration: max(0, durationValue.seconds), width: Int(abs(transformed.width).rounded()), height: Int(abs(transformed.height).rounded()), fps: fps > 0 ? fps : 30, hasAudio: !audioTracks.isEmpty, fileSizeBytes: size)
    }
}

@available(macOS 13.0, *)
public final class LocalSpeechTranscriber {
    public init() {}

    public func transcribe(videoURL: URL, languageHint: String?) async throws -> [TranscriptSegment] {
        let status = await authorizationStatus()
        guard status == .authorized else { throw BlackstockError.speechPermissionDenied }
        let audioURL = try await extractAudio(from: videoURL)
        defer { try? FileManager.default.removeItem(at: audioURL) }
        let localeID = languageHint?.lowercased().contains("deutsch") == true ? "de-DE" : (languageHint?.lowercased().contains("englisch") == true ? "en-US" : Locale.current.identifier)
        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: localeID)), recognizer.isAvailable else { throw BlackstockError.speechUnavailable }
        let request = SFSpeechURLRecognitionRequest(url: audioURL)
        request.shouldReportPartialResults = false
        if recognizer.supportsOnDeviceRecognition { request.requiresOnDeviceRecognition = true }
        return try await withCheckedThrowingContinuation { continuation in
            var completed = false
            var task: SFSpeechRecognitionTask?
            task = recognizer.recognitionTask(with: request) { result, error in
                guard !completed else { return }
                if let error {
                    completed = true
                    task?.cancel()
                    continuation.resume(throwing: error)
                    return
                }
                guard let result, result.isFinal else { return }
                completed = true
                continuation.resume(returning: result.bestTranscription.segments.map {
                    TranscriptSegment(start: $0.timestamp, duration: $0.duration, text: $0.substring, confidence: Double($0.confidence))
                })
            }
        }
    }

    private func authorizationStatus() async -> SFSpeechRecognizerAuthorizationStatus {
        let current = SFSpeechRecognizer.authorizationStatus()
        guard current == .notDetermined else { return current }
        return await withCheckedContinuation { continuation in SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) } }
    }

    private func extractAudio(from videoURL: URL) async throws -> URL {
        let destination = FileManager.default.temporaryDirectory.appendingPathComponent("blackstock-audio-\(UUID().uuidString)").appendingPathExtension("m4a")
        let asset = AVURLAsset(url: videoURL)
        guard let exporter = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else { throw BlackstockError.speechUnavailable }
        exporter.outputURL = destination
        exporter.outputFileType = .m4a
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in exporter.exportAsynchronously { continuation.resume() } }
        guard exporter.status == .completed else { throw exporter.error ?? BlackstockError.speechUnavailable }
        return destination
    }
}

@available(macOS 13.0, *)
public enum HighQualityRenderService {
    public static func export(sourceURL: URL, moment: ClipMoment, aspect: AspectMode, destination: URL) async throws {
        guard moment.end > moment.start else { throw BlackstockError.exportFailed("Ungültiger Schnittbereich") }
        let asset = AVURLAsset(url: sourceURL)
        let videoTracks = try await asset.loadTracks(withMediaType: .video)
        guard let sourceVideo = videoTracks.first else { throw BlackstockError.noVideoTrack }
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        let composition = AVMutableComposition()
        let timeRange = CMTimeRange(start: CMTime(seconds: moment.start, preferredTimescale: 600), duration: CMTime(seconds: moment.duration, preferredTimescale: 600))
        guard let compositionVideo = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else { throw BlackstockError.exportFailed("Videospur konnte nicht erstellt werden") }
        try compositionVideo.insertTimeRange(timeRange, of: sourceVideo, at: .zero)
        if let sourceAudio = audioTracks.first, let compositionAudio = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) {
            try compositionAudio.insertTimeRange(timeRange, of: sourceAudio, at: .zero)
        }
        guard let exporter = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetHighestQuality) else { throw BlackstockError.exportFailed("High-Quality-Exporter nicht verfügbar") }
        exporter.outputURL = destination
        exporter.outputFileType = .mov
        exporter.shouldOptimizeForNetworkUse = false
        if aspect != .original {
            exporter.videoComposition = try await makeVideoComposition(sourceTrack: sourceVideo, compositionTrack: compositionVideo, aspect: aspect, duration: timeRange.duration)
        } else {
            compositionVideo.preferredTransform = try await sourceVideo.load(.preferredTransform)
        }
        if FileManager.default.fileExists(atPath: destination.path) { try FileManager.default.removeItem(at: destination) }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in exporter.exportAsynchronously { continuation.resume() } }
        guard exporter.status == .completed else { throw BlackstockError.exportFailed(exporter.error?.localizedDescription ?? "Unbekannter Rendererfehler") }
    }

    private static func makeVideoComposition(sourceTrack: AVAssetTrack, compositionTrack: AVCompositionTrack, aspect: AspectMode, duration: CMTime) async throws -> AVMutableVideoComposition {
        let naturalSize = try await sourceTrack.load(.naturalSize)
        let preferredTransform = try await sourceTrack.load(.preferredTransform)
        let sourceRect = CGRect(origin: .zero, size: naturalSize).applying(preferredTransform)
        let orientedSize = CGSize(width: abs(sourceRect.width), height: abs(sourceRect.height))
        let fpsValue = Double(try await sourceTrack.load(.nominalFrameRate))
        let fps = max(24, min(60, fpsValue > 0 ? fpsValue : 30))
        let target: CGSize
        switch aspect {
        case .vertical:
            let maxWidthWithoutUpscale = min(orientedSize.width, orientedSize.height * 9.0 / 16.0, 2160)
            let width = max(2, floor(maxWidthWithoutUpscale / 2) * 2)
            let height = max(2, floor((width * 16.0 / 9.0) / 2) * 2)
            target = CGSize(width: width, height: height)
        case .square:
            let edge = max(2, floor(min(orientedSize.width, orientedSize.height, 2160) / 2) * 2)
            target = CGSize(width: edge, height: edge)
        case .original:
            target = orientedSize
        }
        let normalize = preferredTransform.concatenating(CGAffineTransform(translationX: -sourceRect.minX, y: -sourceRect.minY))
        let scale = max(target.width / max(1, orientedSize.width), target.height / max(1, orientedSize.height))
        let scaledSize = CGSize(width: orientedSize.width * scale, height: orientedSize.height * scale)
        let transform = normalize.concatenating(CGAffineTransform(scaleX: scale, y: scale)).concatenating(CGAffineTransform(translationX: (target.width - scaledSize.width) / 2, y: (target.height - scaledSize.height) / 2))
        let instruction = AVMutableVideoCompositionInstruction()
        instruction.timeRange = CMTimeRange(start: .zero, duration: duration)
        let layer = AVMutableVideoCompositionLayerInstruction(assetTrack: compositionTrack)
        layer.setTransform(transform, at: .zero)
        instruction.layerInstructions = [layer]
        let videoComposition = AVMutableVideoComposition()
        videoComposition.renderSize = target
        videoComposition.frameDuration = CMTime(value: 600, timescale: CMTimeScale((fps * 600).rounded()))
        videoComposition.instructions = [instruction]
        return videoComposition
    }
}

@available(macOS 13.0, *)
public enum QualityGate {
    public static func verify(source: MediaInfo, outputURL: URL, requestedMoment: ClipMoment, aspect: AspectMode) async -> QualityReport {
        var checks: [String] = [], warnings: [String] = []
        guard let output = try? await MediaInspector.inspect(outputURL) else { return QualityReport(passed: false, checks: [], warnings: ["Exportdatei konnte nicht erneut geprüft werden."], output: nil) }
        let durationDelta = abs(output.duration - requestedMoment.duration)
        if durationDelta <= 0.35 { checks.append("Schnittdauer stimmt") } else { warnings.append("Schnittdauer weicht um \(String(format: "%.2f", durationDelta)) s ab") }
        if output.hasAudio == source.hasAudio { checks.append("Audiozustand erhalten") } else { warnings.append("Audiozustand hat sich verändert") }
        if output.fps + 1 >= min(60, source.fps) { checks.append("Framerate erhalten") } else { warnings.append("Framerate wurde reduziert") }
        switch aspect {
        case .original:
            if output.width >= min(source.width, 1920) || output.height >= min(source.height, 1080) { checks.append("Quellauflösung hochwertig erhalten") } else { warnings.append("Auflösung liegt unerwartet unter der Quelle") }
        case .vertical:
            let expectedWidth = min(Double(source.width), Double(source.height) * 9.0 / 16.0, 2160)
            if output.height > output.width && abs(Double(output.width) - expectedWidth) <= 6 { checks.append("9:16 ohne künstliches Upscaling") } else { warnings.append("9:16-Ausgabe weicht vom quelltreuen Crop ab") }
        case .square:
            let expectedEdge = min(source.width, source.height, 2160)
            if abs(output.width - output.height) <= 2 && abs(output.width - expectedEdge) <= 4 { checks.append("1:1 ohne künstliches Upscaling") } else { warnings.append("1:1-Ausgabe weicht vom quelltreuen Crop ab") }
        }
        if output.fileSizeBytes > 64_000 { checks.append("Exportdatei plausibel groß") } else { warnings.append("Exportdatei ist ungewöhnlich klein") }
        return QualityReport(passed: warnings.isEmpty, checks: checks, warnings: warnings, output: output)
    }
}
