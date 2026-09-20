#if os(macOS)
import Foundation
@preconcurrency import AVFoundation
import CoreGraphics

public enum LocalSupplementalVideoError:
    Error,
    Sendable,
    Equatable {
    case missingBaseVideoTrack
    case missingSupplementalVideoTrack(UUID)
    case invalidBaseVideoSize
    case noUsableInsert
    case exportSessionUnavailable
    case unsupportedOutputType
    case exportFailed(String)
    case missingOutput
}

private final class SupplementalVideoExportSessionBox:
    @unchecked Sendable {
    let session: AVAssetExportSession
    init(_ session: AVAssetExportSession) {
        self.session = session
    }
}

public actor LocalSupplementalVideoCompositor {
    public init() {}

    public func render(
        inputURL: URL,
        supplementalVideo: [SupplementalVideoInsertInput],
        outputURL: URL,
        preset: LocalRenderPreset
    ) async throws {
        let baseAsset = AVURLAsset(url: inputURL)
        let baseDuration = try await baseAsset.load(.duration)
        let baseDurationSeconds = max(CMTimeGetSeconds(baseDuration), 0)
        let baseVideoTracks = try await baseAsset.loadTracks(withMediaType: .video)
        guard let baseVideoTrack = baseVideoTracks.first else {
            throw LocalSupplementalVideoError.missingBaseVideoTrack
        }

        let composition = AVMutableComposition()
        guard let baseCompositionTrack =
                composition.addMutableTrack(
                    withMediaType: .video,
                    preferredTrackID:
                        kCMPersistentTrackID_Invalid
                ) else {
            throw LocalSupplementalVideoError.missingBaseVideoTrack
        }
        try baseCompositionTrack.insertTimeRange(
            CMTimeRange(start: .zero, duration: baseDuration),
            of: baseVideoTrack,
            at: .zero
        )

        let baseAudioTracks = try await baseAsset.loadTracks(
            withMediaType: .audio
        )
        for sourceAudioTrack in baseAudioTracks {
            guard let audioTrack = composition.addMutableTrack(
                withMediaType: .audio,
                preferredTrackID: kCMPersistentTrackID_Invalid
            ) else {
                throw LocalSupplementalVideoError.exportFailed(
                    "Basisaudiospur konnte nicht angelegt werden."
                )
            }
            try audioTrack.insertTimeRange(
                CMTimeRange(start: .zero, duration: baseDuration),
                of: sourceAudioTrack,
                at: .zero
            )
        }

        let baseNaturalSize = try await baseVideoTrack.load(.naturalSize)
        let basePreferredTransform = try await baseVideoTrack.load(.preferredTransform)
        let baseBounds = CGRect(
            origin: .zero,
            size: baseNaturalSize
        ).applying(basePreferredTransform)
        let renderSize = CGSize(
            width: abs(baseBounds.width),
            height: abs(baseBounds.height)
        )
        guard renderSize.width > 0,
              renderSize.height > 0 else {
            throw LocalSupplementalVideoError.invalidBaseVideoSize
        }

        let baseTransform = Self.normalizedTransform(
            naturalSize: baseNaturalSize,
            preferredTransform: basePreferredTransform,
            renderSize: renderSize
        )

        struct PreparedInsert {
            let track: AVMutableCompositionTrack
            let startSeconds: Double
            let endSeconds: Double
            let transform: CGAffineTransform
        }

        var prepared: [PreparedInsert] = []

        for input in supplementalVideo {
            let asset = AVURLAsset(url: input.fileURL)
            let tracks = try await asset.loadTracks(withMediaType: .video)
            guard let sourceTrack = tracks.first else {
                throw LocalSupplementalVideoError
                    .missingSupplementalVideoTrack(input.captureID)
            }

            let sourceDuration = try await asset.load(.duration)
            let sourceDurationSeconds = max(CMTimeGetSeconds(sourceDuration), 0)
            let sourceStart = min(
                max(input.sourceStartSeconds, 0),
                sourceDurationSeconds
            )
            let timelineStart = min(
                max(input.timelineStartSeconds, 0),
                baseDurationSeconds
            )
            let durationSeconds = min(
                max(input.durationSeconds, 0),
                sourceDurationSeconds - sourceStart,
                baseDurationSeconds - timelineStart
            )
            guard durationSeconds >= 0.05 else { continue }

            guard let compositionTrack = composition.addMutableTrack(
                withMediaType: .video,
                preferredTrackID: kCMPersistentTrackID_Invalid
            ) else {
                throw LocalSupplementalVideoError.exportFailed(
                    "Zusätzliche Videospur konnte nicht angelegt werden."
                )
            }

            try compositionTrack.insertTimeRange(
                CMTimeRange(
                    start: CMTime(
                        seconds: sourceStart,
                        preferredTimescale: 600
                    ),
                    duration: CMTime(
                        seconds: durationSeconds,
                        preferredTimescale: 600
                    )
                ),
                of: sourceTrack,
                at: CMTime(
                    seconds: timelineStart,
                    preferredTimescale: 600
                )
            )

            let naturalSize = try await sourceTrack.load(.naturalSize)
            let preferredTransform = try await sourceTrack.load(.preferredTransform)
            prepared.append(
                PreparedInsert(
                    track: compositionTrack,
                    startSeconds: timelineStart,
                    endSeconds: timelineStart + durationSeconds,
                    transform: Self.aspectFillTransform(
                        naturalSize: naturalSize,
                        preferredTransform: preferredTransform,
                        renderSize: renderSize
                    )
                )
            )
        }

        guard !prepared.isEmpty else {
            throw LocalSupplementalVideoError.noUsableInsert
        }

        var boundaries: [Double] = [0, baseDurationSeconds]
        for insert in prepared {
            boundaries.append(insert.startSeconds)
            boundaries.append(insert.endSeconds)
        }
        boundaries = Array(Set(boundaries.map {
            ($0 * 1_000).rounded() / 1_000
        })).sorted()

        var instructions: [AVMutableVideoCompositionInstruction] = []
        for index in 0..<(boundaries.count - 1) {
            let start = boundaries[index]
            let end = boundaries[index + 1]
            guard end - start >= 0.001 else { continue }

            let instruction = AVMutableVideoCompositionInstruction()
            instruction.timeRange = CMTimeRange(
                start: CMTime(seconds: start, preferredTimescale: 600),
                duration: CMTime(
                    seconds: end - start,
                    preferredTimescale: 600
                )
            )

            var layers: [AVMutableVideoCompositionLayerInstruction] = []
            let active = prepared.filter {
                $0.startSeconds < end - 0.0005
                    && $0.endSeconds > start + 0.0005
            }
            for insert in active.reversed() {
                let layer = AVMutableVideoCompositionLayerInstruction(
                    assetTrack: insert.track
                )
                layer.setTransform(insert.transform, at: .zero)
                layers.append(layer)
            }

            let baseLayer = AVMutableVideoCompositionLayerInstruction(
                assetTrack: baseCompositionTrack
            )
            baseLayer.setTransform(baseTransform, at: .zero)
            layers.append(baseLayer)
            instruction.layerInstructions = layers
            instructions.append(instruction)
        }

        let videoComposition = AVMutableVideoComposition()
        videoComposition.instructions = instructions
        videoComposition.renderSize = renderSize
        videoComposition.frameDuration = CMTime(value: 1, timescale: 30)

        guard let exporter = AVAssetExportSession(
            asset: composition,
            presetName: preset.avPresetName
        ) else {
            throw LocalSupplementalVideoError.exportSessionUnavailable
        }
        guard exporter.supportedFileTypes.contains(.mp4) else {
            throw LocalSupplementalVideoError.unsupportedOutputType
        }

        if FileManager.default.fileExists(atPath: outputURL.path) {
            try FileManager.default.removeItem(at: outputURL)
        }
        exporter.outputURL = outputURL
        exporter.outputFileType = .mp4
        exporter.shouldOptimizeForNetworkUse = true
        exporter.videoComposition = videoComposition

        let box = SupplementalVideoExportSessionBox(exporter)
        try await withCheckedThrowingContinuation { continuation in
            box.session.exportAsynchronously {
                let session = box.session
                switch session.status {
                case .completed:
                    continuation.resume()
                case .failed, .cancelled:
                    continuation.resume(
                        throwing: LocalSupplementalVideoError.exportFailed(
                            session.error?.localizedDescription
                                ?? "Video-Einblendung fehlgeschlagen."
                        )
                    )
                default:
                    continuation.resume(
                        throwing: LocalSupplementalVideoError.exportFailed(
                            "Video-Einblendung endete im Zustand \(session.status.rawValue)."
                        )
                    )
                }
            }
        }

        guard FileManager.default.fileExists(atPath: outputURL.path) else {
            throw LocalSupplementalVideoError.missingOutput
        }
    }

    private static func normalizedTransform(
        naturalSize: CGSize,
        preferredTransform: CGAffineTransform,
        renderSize: CGSize
    ) -> CGAffineTransform {
        let bounds = CGRect(
            origin: .zero,
            size: naturalSize
        ).applying(preferredTransform)
        let width = abs(bounds.width)
        let height = abs(bounds.height)
        var transform = preferredTransform.concatenating(
            CGAffineTransform(
                translationX: -bounds.minX,
                y: -bounds.minY
            )
        )
        guard width > 0, height > 0 else { return transform }
        transform = transform.concatenating(
            CGAffineTransform(
                scaleX: renderSize.width / width,
                y: renderSize.height / height
            )
        )
        return transform
    }

    private static func aspectFillTransform(
        naturalSize: CGSize,
        preferredTransform: CGAffineTransform,
        renderSize: CGSize
    ) -> CGAffineTransform {
        let bounds = CGRect(
            origin: .zero,
            size: naturalSize
        ).applying(preferredTransform)
        let width = abs(bounds.width)
        let height = abs(bounds.height)
        guard width > 0,
              height > 0,
              renderSize.width > 0,
              renderSize.height > 0 else {
            return preferredTransform
        }

        let scale = max(
            renderSize.width / width,
            renderSize.height / height
        )
        let cropX = max(
            (width - renderSize.width / scale) / 2,
            0
        )
        let cropY = max(
            (height - renderSize.height / scale) / 2,
            0
        )
        var transform = preferredTransform
        transform = transform.concatenating(
            CGAffineTransform(
                translationX: -bounds.minX,
                y: -bounds.minY
            )
        )
        transform = transform.concatenating(
            CGAffineTransform(
                translationX: -cropX,
                y: -cropY
            )
        )
        transform = transform.concatenating(
            CGAffineTransform(scaleX: scale, y: scale)
        )
        return transform
    }
}
#endif
