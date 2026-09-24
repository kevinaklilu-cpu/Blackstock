#if os(macOS)
import Foundation
@preconcurrency import AVFoundation

public enum EditedTimelineAudioMaterializationError: Error, Sendable, Equatable {
    case emptyTimeline
    case exportSessionUnavailable
    case unsupportedOutputType
    case exportFailed(String)
    case missingOutput
}

private final class EditedTimelineAudioExportBox: @unchecked Sendable {
    let session: AVAssetExportSession

    init(_ session: AVAssetExportSession) {
        self.session = session
    }
}

public actor EditedTimelineAudioMaterializer {
    public init() {}

    public func materialize(
        sourceURL: URL,
        sourceRanges: [EditTimeRange]
    ) async throws -> URL {
        guard !sourceRanges.isEmpty,
              sourceRanges.contains(where: { $0.durationSeconds > 0.001 }) else {
            throw EditedTimelineAudioMaterializationError.emptyTimeline
        }

        let source = AVURLAsset(url: sourceURL)
        let composition = AVMutableComposition()

        for sourceRange in sourceRanges where sourceRange.durationSeconds > 0.001 {
            let range = CMTimeRange(
                start: CMTime(
                    seconds: sourceRange.startSeconds,
                    preferredTimescale: 600
                ),
                duration: CMTime(
                    seconds: sourceRange.durationSeconds,
                    preferredTimescale: 600
                )
            )
            try await composition.insertTimeRange(
                range,
                of: source,
                at: composition.duration
            )
        }

        guard let exporter = AVAssetExportSession(
            asset: composition,
            presetName: AVAssetExportPresetAppleM4A
        ) else {
            throw EditedTimelineAudioMaterializationError.exportSessionUnavailable
        }

        guard exporter.supportedFileTypes.contains(.m4a) else {
            throw EditedTimelineAudioMaterializationError.unsupportedOutputType
        }

        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent("blackstock-edited-speech-\(UUID().uuidString)")
            .appendingPathExtension("m4a")

        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }

        do {
            try await AsyncAVAssetExporter.export(
                exporter,
                to: destination,
                as: .m4a
            )
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw EditedTimelineAudioMaterializationError.exportFailed(
                error.localizedDescription
            )
        }

        guard FileManager.default.fileExists(atPath: destination.path) else {
            throw EditedTimelineAudioMaterializationError.missingOutput
        }

        return destination
    }
}
#endif
