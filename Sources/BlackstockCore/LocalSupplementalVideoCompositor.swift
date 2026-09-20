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
        let baseAssetDuration = try await baseAsset.load(.duration)
        let baseVideoTracks = try await baseAsset.loadTracks(
            withMediaType: .video
        )
        guard let baseVideoTrack = baseVideoTracks.first else {
            throw LocalSupplementalVideoError
                .missingBaseVideoTrack
        }

        let baseVideoTimeRange = try await baseVideoTrack.load(
            .timeRange
        )
        let baseDurationSeconds = min(
            max(CMTimeGetSeconds(baseAssetDuration), 0),
            max(CMTimeGetSeconds(baseVideoTimeRange.duration), 0)
        )
        guard baseDurationSeconds >= 0.05 else {
            throw LocalSupplementalVideoError
                .missingBaseVideoTrack
        }
        let baseDuration = CMTime(
            seconds: baseDurationSeconds,
            preferredTimescale: 600
        )

        let baseNaturalSize = try await baseVideoTrack.load(
            .naturalSize
        )
        let basePreferredTransform = try await baseVideoTrack.load(
            .preferredTransform
        )
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
            throw LocalSupplementalVideoError
                .invalidBaseVideoSize
        }

        let baseTransform = Self.normalizedTransform(
            naturalSize: baseNaturalSize,
            preferredTransform: basePreferredTransform,
            renderSize: renderSize
        )

        let composition = AVMutableComposition()
        guard let baseCompositionTrack =
                composition.addMutableTrack(
                    withMediaType: .video,
                    preferredTrackID:
                        kCMPersistentTrackID_Invalid
                ) else {
            throw LocalSupplementalVideoError
                .missingBaseVideoTrack
        }

        try baseCompositionTrack.insertTimeRange(
            CMTimeRange(
                start: baseVideoTimeRange.start,
                duration: baseDuration
            ),
            of: baseVideoTrack,
            at: .zero
        )

        let baseAudioTracks = try await baseAsset.loadTracks(
            withMediaType: .audio
        )
        for sourceAudioTrack in baseAudioTracks {
            let sourceRange = try await sourceAudioTrack.load(
                .timeRange
            )
            let audioDurationSeconds = min(
                baseDurationSeconds,
                max(
                    CMTimeGetSeconds(sourceRange.duration),
                    0
                )
            )
            guard audioDurationSeconds >= 0.001 else {
                continue
            }
            guard let audioTrack = composition.addMutableTrack(
                withMediaType: .audio,
                preferredTrackID:
                    kCMPersistentTrackID_Invalid
            ) else {
                throw LocalSupplementalVideoError
                    .exportFailed(
                        "Basisaudiospur konnte nicht angelegt werden."
                    )
            }
            try audioTrack.insertTimeRange(
                CMTimeRange(
                    start: sourceRange.start,
                    duration: CMTime(
                        seconds: audioDurationSeconds,
                        preferredTimescale: 600
                    )
                ),
                of: sourceAudioTrack,
                at: .zero
            )
        }

        struct PreparedInsert {
            let order: Int
            let track: AVMutableCompositionTrack
            let timelineStartSeconds: Double
            let timelineEndSeconds: Double
            let transform: CGAffineTransform
        }

        var prepared: [PreparedInsert] = []
        for (order, input) in supplementalVideo.enumerated() {
            let asset = AVURLAsset(url: input.fileURL)
            let tracks = try await asset.loadTracks(
                withMediaType: .video
            )
            guard let sourceTrack = tracks.first else {
                throw LocalSupplementalVideoError
                    .missingSupplementalVideoTrack(
                        input.captureID
                    )
            }

            let sourceRange = try await sourceTrack.load(
                .timeRange
            )
            let sourceDurationSeconds = max(
                CMTimeGetSeconds(sourceRange.duration),
                0
            )
            let sourceStartOffset = min(
                max(input.sourceStartSeconds, 0),
                sourceDurationSeconds
            )
            let timelineStart = min(
                max(input.timelineStartSeconds, 0),
                baseDurationSeconds
            )
            let durationSeconds = min(
                max(input.durationSeconds, 0),
                sourceDurationSeconds - sourceStartOffset,
                baseDurationSeconds - timelineStart
            )
            guard durationSeconds >= 0.05 else {
                continue
            }

            guard let compositionTrack =
                    composition.addMutableTrack(
                        withMediaType: .video,
                        preferredTrackID:
                            kCMPersistentTrackID_Invalid
                    ) else {
                throw LocalSupplementalVideoError
                    .exportFailed(
                        "Zusätzliche Videospur konnte nicht angelegt werden."
                    )
            }

            let sourceStart = CMTimeAdd(
                sourceRange.start,
                CMTime(
                    seconds: sourceStartOffset,
                    preferredTimescale: 600
                )
            )
            do {
                try compositionTrack.insertTimeRange(
                    CMTimeRange(
                        start: sourceStart,
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
            } catch {
                throw LocalSupplementalVideoError
                    .exportFailed(
                        "B-Roll konnte nicht in die eigene Videospur eingesetzt werden: "
                        + error.localizedDescription
                    )
            }

            let naturalSize = try await sourceTrack.load(
                .naturalSize
            )
            let preferredTransform = try await sourceTrack.load(
                .preferredTransform
            )

            prepared.append(
                PreparedInsert(
                    order: order,
                    track: compositionTrack,
                    timelineStartSeconds: timelineStart,
                    timelineEndSeconds:
                        timelineStart + durationSeconds,
                    transform: Self.aspectFillTransform(
                        naturalSize: naturalSize,
                        preferredTransform:
                            preferredTransform,
                        renderSize: renderSize
                    )
                )
            )
        }

        guard !prepared.isEmpty else {
            throw LocalSupplementalVideoError.noUsableInsert
        }

        var boundaries: [Double] = [
            0,
            baseDurationSeconds
        ]
        for insert in prepared {
            boundaries.append(
                insert.timelineStartSeconds
            )
            boundaries.append(
                insert.timelineEndSeconds
            )
        }
        boundaries.sort()

        var normalizedBoundaries: [Double] = []
        for value in boundaries {
            let clamped = min(
                max(value, 0),
                baseDurationSeconds
            )
            if let last = normalizedBoundaries.last,
               abs(last - clamped) < 0.000_5 {
                continue
            }
            normalizedBoundaries.append(clamped)
        }

        var instructions:
            [AVMutableVideoCompositionInstruction] = []
        for index in 0..<(normalizedBoundaries.count - 1) {
            let start = normalizedBoundaries[index]
            let end = normalizedBoundaries[index + 1]
            guard end - start >= 0.001 else {
                continue
            }

            let activeInsert = prepared
                .filter {
                    $0.timelineStartSeconds
                        <= start + 0.000_5
                    && $0.timelineEndSeconds
                        >= end - 0.000_5
                }
                .max { $0.order < $1.order }

            let instruction =
                AVMutableVideoCompositionInstruction()
            instruction.timeRange = CMTimeRange(
                start: CMTime(
                    seconds: start,
                    preferredTimescale: 600
                ),
                duration: CMTime(
                    seconds: end - start,
                    preferredTimescale: 600
                )
            )

            if let activeInsert {
                let layer =
                    AVMutableVideoCompositionLayerInstruction(
                        assetTrack: activeInsert.track
                    )
                layer.setTransform(
                    activeInsert.transform,
                    at: instruction.timeRange.start
                )
                instruction.layerInstructions = [layer]
            } else {
                let layer =
                    AVMutableVideoCompositionLayerInstruction(
                        assetTrack: baseCompositionTrack
                    )
                layer.setTransform(
                    baseTransform,
                    at: instruction.timeRange.start
                )
                instruction.layerInstructions = [layer]
            }

            instructions.append(instruction)
        }

        let videoComposition = AVMutableVideoComposition()
        videoComposition.instructions = instructions
        videoComposition.renderSize = renderSize
        videoComposition.frameDuration = CMTime(
            value: 1,
            timescale: 30
        )

        guard let exporter = AVAssetExportSession(
            asset: composition,
            presetName: preset.avPresetName
        ) else {
            throw LocalSupplementalVideoError
                .exportSessionUnavailable
        }
        guard exporter.supportedFileTypes.contains(.mp4) else {
            throw LocalSupplementalVideoError
                .unsupportedOutputType
        }

        if FileManager.default.fileExists(
            atPath: outputURL.path
        ) {
            try FileManager.default.removeItem(
                at: outputURL
            )
        }
        exporter.outputURL = outputURL
        exporter.outputFileType = .mp4
        exporter.shouldOptimizeForNetworkUse = true
        exporter.videoComposition = videoComposition

        let box =
            SupplementalVideoExportSessionBox(exporter)
        try await withCheckedThrowingContinuation {
            continuation in
            box.session.exportAsynchronously {
                let session = box.session
                switch session.status {
                case .completed:
                    continuation.resume()
                case .failed, .cancelled:
                    continuation.resume(
                        throwing:
                            LocalSupplementalVideoError
                            .exportFailed(
                                Self.errorDescription(
                                    session.error
                                )
                            )
                    )
                default:
                    continuation.resume(
                        throwing:
                            LocalSupplementalVideoError
                            .exportFailed(
                                "Video-Einblendung endete im Zustand \(session.status.rawValue)."
                            )
                    )
                }
            }
        }

        guard FileManager.default.fileExists(
            atPath: outputURL.path
        ) else {
            throw LocalSupplementalVideoError
                .missingOutput
        }
    }

    private static func errorDescription(
        _ error: Error?
    ) -> String {
        guard let error else {
            return "Video-Einblendung fehlgeschlagen."
        }

        let nsError = error as NSError
        var parts = [
            nsError.localizedDescription,
            "Domain=\(nsError.domain)",
            "Code=\(nsError.code)"
        ]

        if let reason = nsError.userInfo[
            NSLocalizedFailureReasonErrorKey
        ] as? String,
           !reason.isEmpty {
            parts.append("Grund=\(reason)")
        }

        if let underlying = nsError.userInfo[
            NSUnderlyingErrorKey
        ] as? NSError {
            parts.append(
                "UnderlyingDomain=\(underlying.domain)"
            )
            parts.append(
                "UnderlyingCode=\(underlying.code)"
            )
            if !underlying.localizedDescription.isEmpty {
                parts.append(
                    "Underlying=\(underlying.localizedDescription)"
                )
            }
        }

        return parts.joined(separator: " | ")
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
        guard width > 0,
              height > 0 else {
            return transform
        }
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
        let scaledWidth = width * scale
        let scaledHeight = height * scale
        let offsetX =
            (renderSize.width - scaledWidth) / 2
        let offsetY =
            (renderSize.height - scaledHeight) / 2

        var transform = preferredTransform.concatenating(
            CGAffineTransform(
                translationX: -bounds.minX,
                y: -bounds.minY
            )
        )
        transform = transform.concatenating(
            CGAffineTransform(
                scaleX: scale,
                y: scale
            )
        )
        transform = transform.concatenating(
            CGAffineTransform(
                translationX: offsetX / scale,
                y: offsetY / scale
            )
        )
        return transform
    }
}
#endif
