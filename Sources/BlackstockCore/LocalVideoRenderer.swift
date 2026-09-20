#if os(macOS)
import Foundation
@preconcurrency import AVFoundation
import CryptoKit
import CoreGraphics

public enum LocalRenderPreset: String, Codable, Sendable, CaseIterable, Hashable {
    case hd1080
    case uhd4K

    var avPresetName: String {
        switch self {
        case .hd1080: return AVAssetExportPreset1920x1080
        case .uhd4K: return AVAssetExportPreset3840x2160
        }
    }
}

public enum LocalRenderError: Error, Sendable, Equatable {
    case unauthorizedMedia
    case unsupportedEditOperation(EditOperationType)
    case exportSessionUnavailable
    case unsupportedOutputType
    case missingVideoTrack
    case missingSupplementalAudioTrack(UUID)
    case missingSupplementalVideoTrack(UUID)
    case noUsableSupplementalVideo
    case emptyEditResult
    case reframePlanUnavailable
    case exportFailed(String)
    case missingOutput
    case technicalValidationFailed([RenderTechnicalBlocker])
}

private final class ExportSessionBox: @unchecked Sendable {
    let session: AVAssetExportSession
    init(_ session: AVAssetExportSession) { self.session = session }
}

public actor LocalVideoRenderer {
    public init() {}

    public func render(
        projectID: UUID,
        asset: ProductionMediaAsset,
        graph: EditGraph,
        outputURL: URL,
        preset: LocalRenderPreset,
        transcript: LocalTranscript? = nil,
        burnInCaptions: Bool = false,
        captionStyle: CaptionVisualStyle = .clear,
        supplementalAudio: [SupplementalAudioMixInput] = [],
        supplementalVideo: [SupplementalVideoInsertInput] = []
    ) async throws -> RenderArtifact {
        guard asset.mayEnterProduction else {
            throw LocalRenderError.unauthorizedMedia
        }

        let unsupported = graph.currentOperations.first {
            ![
                EditOperationType.trim,
                EditOperationType.removeRange,
                EditOperationType.volume,
                EditOperationType.reframe,
                EditOperationType.overlay
            ].contains($0.type)
        }
        if let unsupported {
            throw LocalRenderError.unsupportedEditOperation(unsupported.type)
        }

        let source = AVURLAsset(url: asset.sourceURL)
        let composition = AVMutableComposition()

        let sourceDuration = try await source.load(.duration)
        let sourceDurationSeconds = max(
            CMTimeGetSeconds(sourceDuration),
            0
        )
        let timeline = EditTimelineResolver().resolve(
            sourceDurationSeconds: sourceDurationSeconds,
            operations: graph.currentOperations
        )
        guard timeline.hasContent else {
            throw LocalRenderError.emptyEditResult
        }

        let textOverlays = TextOverlayPlanner().cues(
            operations: graph.currentOperations,
            outputDurationSeconds: timeline.outputDurationSeconds
        )

        let captionTranscript: LocalTranscript?
        if burnInCaptions,
           let transcript,
           transcript.segments.contains(
                where: {
                    !$0.text.trimmingCharacters(
                        in: .whitespacesAndNewlines
                    ).isEmpty
                }
           ) {
            captionTranscript = transcript
        } else {
            captionTranscript = nil
        }

        let hasCaptionPostProcess =
            captionTranscript != nil
            || !textOverlays.isEmpty
        let hasSupplementalVideo =
            !supplementalVideo.isEmpty

        let exportOutputURL: URL
        if hasCaptionPostProcess {
            exportOutputURL = FileManager.default
                .temporaryDirectory
                .appendingPathComponent(
                    "blackstock-base-render-\(UUID().uuidString)"
                )
                .appendingPathExtension("mp4")
        } else {
            exportOutputURL = outputURL
        }

        defer {
            if exportOutputURL != outputURL {
                try? FileManager.default.removeItem(
                    at: exportOutputURL
                )
            }
        }

        for sourceRange in timeline.sourceRanges {
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

        let masterVolume = EditAudioPlanner().masterVolume(
            operations: graph.currentOperations
        )
        var audioMixParameters: [AVAudioMixInputParameters] = []
        for track in composition.tracks(withMediaType: .audio) {
            let parameters = AVMutableAudioMixInputParameters(
                track: track
            )
            parameters.setVolume(
                Float(masterVolume),
                at: .zero
            )
            audioMixParameters.append(parameters)
        }


        for input in supplementalAudio {
            guard input.volume > 0 else { continue }

            let supplementalAsset = AVURLAsset(url: input.fileURL)
            let audioTracks = try await supplementalAsset.loadTracks(
                withMediaType: .audio
            )
            guard let sourceAudioTrack = audioTracks.first else {
                throw LocalRenderError.missingSupplementalAudioTrack(
                    input.captureID
                )
            }

            let supplementalDuration = try await supplementalAsset.load(
                .duration
            )
            let supplementalDurationSeconds = max(
                CMTimeGetSeconds(supplementalDuration),
                0
            )
            let mixDurationSeconds = min(
                supplementalDurationSeconds,
                timeline.outputDurationSeconds
            )
            guard mixDurationSeconds > 0.01 else { continue }

            guard let compositionTrack = composition.addMutableTrack(
                withMediaType: .audio,
                preferredTrackID: kCMPersistentTrackID_Invalid
            ) else {
                throw LocalRenderError.exportFailed(
                    "Zusätzliche Audiospur konnte nicht angelegt werden."
                )
            }

            try compositionTrack.insertTimeRange(
                CMTimeRange(
                    start: .zero,
                    duration: CMTime(
                        seconds: mixDurationSeconds,
                        preferredTimescale: 600
                    )
                ),
                of: sourceAudioTrack,
                at: .zero
            )

            let parameters = AVMutableAudioMixInputParameters(
                track: compositionTrack
            )
            parameters.setVolume(
                Float(min(max(input.volume, 0), 1)),
                at: .zero
            )
            audioMixParameters.append(parameters)
        }

        let activeReframe = graph.currentOperations
            .last(where: { $0.type == .reframe })?
            .reframeSpec

        let sourceVideoTracks = try await source.loadTracks(
            withMediaType: .video
        )
        let compositionVideoTracks = composition.tracks(
            withMediaType: .video
        )
        guard let sourceVideoTrack = sourceVideoTracks.first,
              let baseCompositionVideoTrack =
                compositionVideoTracks.first else {
            throw LocalRenderError.missingVideoTrack
        }

        let sourceNaturalSize = try await sourceVideoTrack.load(
            .naturalSize
        )
        let sourcePreferredTransform = try await sourceVideoTrack.load(
            .preferredTransform
        )

        let baseRenderSize: CGSize
        let baseTransform: CGAffineTransform
        if let reframe = activeReframe {
            let requestedRenderSize = preset.renderSize(
                for: reframe.aspectRatio
            )
            guard let plan = ReframeTransformPlan.make(
                naturalSize: sourceNaturalSize,
                preferredTransform: sourcePreferredTransform,
                spec: reframe,
                renderSize: requestedRenderSize
            ) else {
                throw LocalRenderError.reframePlanUnavailable
            }
            baseRenderSize = CGSize(
                width: plan.renderWidth,
                height: plan.renderHeight
            )
            baseTransform = plan.transform
        } else {
            let bounds = CGRect(
                origin: .zero,
                size: sourceNaturalSize
            ).applying(sourcePreferredTransform)
            baseRenderSize = CGSize(
                width: abs(bounds.width),
                height: abs(bounds.height)
            )
            guard baseRenderSize.width > 0,
                  baseRenderSize.height > 0 else {
                throw LocalRenderError.reframePlanUnavailable
            }
            baseTransform = Self.normalizedVideoTransform(
                naturalSize: sourceNaturalSize,
                preferredTransform: sourcePreferredTransform,
                renderSize: baseRenderSize
            )
        }

        struct PreparedSupplementalVideo {
            let order: Int
            let track: AVMutableCompositionTrack
            let timelineStartSeconds: Double
            let timelineEndSeconds: Double
            let transform: CGAffineTransform
        }

        var preparedSupplementalVideo:
            [PreparedSupplementalVideo] = []
        let compositionDurationSeconds = max(
            CMTimeGetSeconds(composition.duration),
            0
        )

        for (order, input) in supplementalVideo.enumerated() {
            let supplementalAsset = AVURLAsset(
                url: input.fileURL
            )
            let tracks = try await supplementalAsset.loadTracks(
                withMediaType: .video
            )
            guard let sourceTrack = tracks.first else {
                throw LocalRenderError
                    .missingSupplementalVideoTrack(
                        input.captureID
                    )
            }

            let sourceTimeRange = try await sourceTrack.load(
                .timeRange
            )
            let sourceDurationSeconds = max(
                CMTimeGetSeconds(
                    sourceTimeRange.duration
                ),
                0
            )
            let sourceStartOffset = min(
                max(input.sourceStartSeconds, 0),
                sourceDurationSeconds
            )
            let timelineStart = min(
                max(input.timelineStartSeconds, 0),
                compositionDurationSeconds
            )
            let requestedDuration = min(
                max(input.durationSeconds, 0),
                sourceDurationSeconds - sourceStartOffset,
                compositionDurationSeconds - timelineStart
            )
            guard requestedDuration >= 0.05 else {
                continue
            }

            let timelineStartTime = CMTime(
                seconds: timelineStart,
                preferredTimescale: 600
            )
            let durationTime = CMTime(
                seconds: requestedDuration,
                preferredTimescale: 600
            )
            let sourceStartTime = CMTimeAdd(
                sourceTimeRange.start,
                CMTime(
                    seconds: sourceStartOffset,
                    preferredTimescale: 600
                )
            )

            guard let supplementalTrack =
                    composition.addMutableTrack(
                        withMediaType: .video,
                        preferredTrackID:
                            kCMPersistentTrackID_Invalid
                    ) else {
                throw LocalRenderError.exportFailed(
                    "Zusätzliche Videospur konnte nicht angelegt werden."
                )
            }

            do {
                try supplementalTrack.insertTimeRange(
                    CMTimeRange(
                        start: sourceStartTime,
                        duration: durationTime
                    ),
                    of: sourceTrack,
                    at: timelineStartTime
                )
            } catch {
                throw LocalRenderError.exportFailed(
                    "B-Roll konnte nicht in den Haupt-Render übernommen werden: "
                    + error.localizedDescription
                )
            }

            let naturalSize = try await sourceTrack.load(
                .naturalSize
            )
            let preferredTransform = try await sourceTrack.load(
                .preferredTransform
            )
            let insertedStart = CMTimeGetSeconds(
                timelineStartTime
            )
            let insertedEnd = CMTimeGetSeconds(
                CMTimeAdd(
                    timelineStartTime,
                    durationTime
                )
            )
            preparedSupplementalVideo.append(
                PreparedSupplementalVideo(
                    order: order,
                    track: supplementalTrack,
                    timelineStartSeconds:
                        insertedStart,
                    timelineEndSeconds:
                        insertedEnd,
                    transform:
                        Self.aspectFillVideoTransform(
                            naturalSize: naturalSize,
                            preferredTransform:
                                preferredTransform,
                            renderSize: baseRenderSize
                        )
                )
            )
        }

        let renderVideoComposition:
            AVMutableVideoComposition?
        if !preparedSupplementalVideo.isEmpty {
            var boundaries = [
                0.0,
                compositionDurationSeconds
            ]
            for insert in preparedSupplementalVideo {
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
                    compositionDurationSeconds
                )
                if let last =
                        normalizedBoundaries.last,
                   abs(last - clamped) < 0.000_5 {
                    continue
                }
                normalizedBoundaries.append(clamped)
            }

            var instructions:
                [AVMutableVideoCompositionInstruction] = []
            for index in 0..<(normalizedBoundaries.count - 1) {
                let start =
                    normalizedBoundaries[index]
                let end =
                    normalizedBoundaries[index + 1]
                guard end - start >= 0.001 else {
                    continue
                }

                let activeInsert =
                    preparedSupplementalVideo
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
                            assetTrack:
                                activeInsert.track
                        )
                    layer.setTransform(
                        activeInsert.transform,
                        at: .zero
                    )
                    instruction.layerInstructions = [
                        layer
                    ]
                } else {
                    let layer =
                        AVMutableVideoCompositionLayerInstruction(
                            assetTrack:
                                baseCompositionVideoTrack
                        )
                    layer.setTransform(
                        baseTransform,
                        at: .zero
                    )
                    instruction.layerInstructions = [
                        layer
                    ]
                }

                instructions.append(instruction)
            }

            let videoComposition =
                AVMutableVideoComposition()
            videoComposition.instructions =
                instructions
            videoComposition.renderSize =
                baseRenderSize
            videoComposition.frameDuration =
                CMTime(value: 1, timescale: 30)
            renderVideoComposition =
                videoComposition
        } else if hasSupplementalVideo {
            throw LocalRenderError
                .noUsableSupplementalVideo
        } else if activeReframe != nil {
            let instruction =
                AVMutableVideoCompositionInstruction()
            instruction.timeRange = CMTimeRange(
                start: .zero,
                duration: composition.duration
            )
            let layer =
                AVMutableVideoCompositionLayerInstruction(
                    assetTrack:
                        baseCompositionVideoTrack
                )
            layer.setTransform(
                baseTransform,
                at: .zero
            )
            instruction.layerInstructions = [layer]

            let videoComposition =
                AVMutableVideoComposition()
            videoComposition.instructions = [
                instruction
            ]
            videoComposition.renderSize =
                baseRenderSize
            videoComposition.frameDuration =
                CMTime(value: 1, timescale: 30)
            renderVideoComposition =
                videoComposition
        } else {
            renderVideoComposition = nil
        }

        guard let exporter = AVAssetExportSession(
            asset: composition,
            presetName: preset.avPresetName
        ) else {
            throw LocalRenderError.exportSessionUnavailable
        }

        if !audioMixParameters.isEmpty {
            let audioMix = AVMutableAudioMix()
            audioMix.inputParameters = audioMixParameters
            exporter.audioMix = audioMix
        }

        if let renderVideoComposition {
            exporter.videoComposition =
                renderVideoComposition
        }

        let supported = exporter.supportedFileTypes
        guard supported.contains(.mp4) else {
            throw LocalRenderError.unsupportedOutputType
        }

        if FileManager.default.fileExists(
            atPath: exportOutputURL.path
        ) {
            try FileManager.default.removeItem(
                at: exportOutputURL
            )
        }

        exporter.outputURL = exportOutputURL
        exporter.outputFileType = .mp4
        exporter.shouldOptimizeForNetworkUse = true

        let exportBox = ExportSessionBox(exporter)
        try await withCheckedThrowingContinuation { continuation in
            exportBox.session.exportAsynchronously {
                let session = exportBox.session
                switch session.status {
                case .completed:
                    continuation.resume()
                case .failed, .cancelled:
                    continuation.resume(
                        throwing: LocalRenderError.exportFailed(
                            session.error?.localizedDescription ?? "Unbekannter Exportfehler"
                        )
                    )
                default:
                    continuation.resume(
                        throwing: LocalRenderError.exportFailed(
                            "Export endete im Zustand \(session.status.rawValue)."
                        )
                    )
                }
            }
        }

        guard FileManager.default.fileExists(
            atPath: exportOutputURL.path
        ) else {
            throw LocalRenderError.missingOutput
        }

        if hasCaptionPostProcess {
            try await LocalCaptionBurnInRenderer()
                .render(
                    inputURL: exportOutputURL,
                    transcript: captionTranscript,
                    textOverlays: textOverlays,
                    outputURL: outputURL,
                    preset: preset,
                    style: captionStyle
                )
        }

        guard FileManager.default.fileExists(
            atPath: outputURL.path
        ) else {
            throw LocalRenderError.missingOutput
        }

        let expectedRenderSize = activeReframe.map {
            preset.renderSize(for: $0.aspectRatio)
        }
        let technicalAssessment = try await LocalRenderTechnicalInspector()
            .inspect(
                url: outputURL,
                expectedDurationSeconds: timeline.outputDurationSeconds,
                expectedRenderSize: expectedRenderSize,
                expectedPreset: preset
            )
        guard technicalAssessment.validated else {
            throw LocalRenderError.technicalValidationFailed(
                technicalAssessment.blockers
            )
        }

        let data = try Data(contentsOf: outputURL)
        let digest = SHA256.hash(data: data)
        let sha256 = digest.map { String(format: "%02x", $0) }.joined()

        return RenderArtifact(
            projectID: projectID,
            fileURL: outputURL,
            sha256: sha256,
            mimeType: "video/mp4",
            validated: true,
            createdAt: Date()
        )
    }

    private static func normalizedVideoTransform(
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
        var transform =
            preferredTransform.concatenating(
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

    private static func aspectFillVideoTransform(
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

        var transform =
            preferredTransform.concatenating(
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
