#if os(macOS)
import Foundation
@preconcurrency import AVFoundation
import AppKit
import QuartzCore

public struct CaptionBurnInCue:
    Sendable,
    Equatable,
    Identifiable {
    public let id: UUID
    public let startSeconds: Double
    public let durationSeconds: Double
    public let text: String

    public init(
        id: UUID,
        startSeconds: Double,
        durationSeconds: Double,
        text: String
    ) {
        self.id = id
        self.startSeconds = max(startSeconds, 0)
        self.durationSeconds = max(durationSeconds, 0)
        self.text = text
    }
}

public struct CaptionBurnInPlanner: Sendable {
    public init() {}

    public func cues(
        transcript: LocalTranscript,
        outputDurationSeconds: Double
    ) -> [CaptionBurnInCue] {
        let outputDuration = max(
            outputDurationSeconds,
            0
        )
        guard outputDuration > 0 else {
            return []
        }

        return transcript.segments.compactMap {
            segment in
            let text = segment.text
                .trimmingCharacters(
                    in: .whitespacesAndNewlines
                )
            guard !text.isEmpty else {
                return nil
            }

            let start = min(
                max(segment.startSeconds, 0),
                outputDuration
            )
            let end = min(
                max(
                    segment.startSeconds
                        + max(
                            segment.durationSeconds,
                            0
                        ),
                    start
                ),
                outputDuration
            )
            guard end - start >= 0.05 else {
                return nil
            }

            return CaptionBurnInCue(
                id: segment.id,
                startSeconds: start,
                durationSeconds: end - start,
                text: text
            )
        }
    }
}

public enum LocalCaptionBurnInError:
    Error,
    Sendable,
    Equatable {
    case missingVideoTrack
    case invalidVideoSize
    case exportSessionUnavailable
    case unsupportedOutputType
    case exportFailed(String)
    case missingOutput
}

private final class CaptionExportSessionBox:
    @unchecked Sendable {
    let session: AVAssetExportSession

    init(_ session: AVAssetExportSession) {
        self.session = session
    }
}

public actor LocalCaptionBurnInRenderer {
    public init() {}

    public func render(
        inputURL: URL,
        transcript: LocalTranscript?,
        textOverlays: [TextOverlayCue] = [],
        outputURL: URL,
        preset: LocalRenderPreset,
        style: CaptionVisualStyle = .clear
    ) async throws {
        let asset = AVURLAsset(url: inputURL)
        let duration = try await asset.load(.duration)
        let durationSeconds = max(
            CMTimeGetSeconds(duration),
            0
        )
        let tracks = try await asset.loadTracks(
            withMediaType: .video
        )
        guard let videoTrack = tracks.first else {
            throw LocalCaptionBurnInError
                .missingVideoTrack
        }

        let naturalSize = try await videoTrack.load(
            .naturalSize
        )
        let preferredTransform = try await videoTrack
            .load(.preferredTransform)
        let transformedBounds = CGRect(
            origin: .zero,
            size: naturalSize
        ).applying(preferredTransform)
        let renderSize = CGSize(
            width: abs(transformedBounds.width),
            height: abs(transformedBounds.height)
        )
        guard renderSize.width > 0,
              renderSize.height > 0 else {
            throw LocalCaptionBurnInError
                .invalidVideoSize
        }

        let instruction =
            AVMutableVideoCompositionInstruction()
        instruction.timeRange = CMTimeRange(
            start: .zero,
            duration: duration
        )

        let layerInstruction =
            AVMutableVideoCompositionLayerInstruction(
                assetTrack: videoTrack
            )
        var transform = preferredTransform
        transform = transform.concatenating(
            CGAffineTransform(
                translationX:
                    -transformedBounds.minX,
                y:
                    -transformedBounds.minY
            )
        )
        layerInstruction.setTransform(
            transform,
            at: .zero
        )
        instruction.layerInstructions = [
            layerInstruction
        ]

        let videoComposition =
            AVMutableVideoComposition()
        videoComposition.instructions = [
            instruction
        ]
        videoComposition.renderSize = renderSize
        videoComposition.frameDuration = CMTime(
            value: 1,
            timescale: 30
        )

        let parentLayer = CALayer()
        parentLayer.frame = CGRect(
            origin: .zero,
            size: renderSize
        )

        let videoLayer = CALayer()
        videoLayer.frame = parentLayer.frame
        parentLayer.addSublayer(videoLayer)

        let overlayLayer = CALayer()
        overlayLayer.frame = parentLayer.frame
        parentLayer.addSublayer(overlayLayer)

        let captionCues = transcript.map {
            CaptionBurnInPlanner().cues(
                transcript: $0,
                outputDurationSeconds:
                    durationSeconds
            )
        } ?? []
        for cue in captionCues {
            overlayLayer.addSublayer(
                Self.captionLayer(
                    cue: cue,
                    renderSize: renderSize,
                    style: style
                )
            )
        }

        for cue in textOverlays {
            overlayLayer.addSublayer(
                Self.textOverlayLayer(
                    cue: cue,
                    renderSize: renderSize
                )
            )
        }

        videoComposition.animationTool =
            AVVideoCompositionCoreAnimationTool(
                postProcessingAsVideoLayer:
                    videoLayer,
                in: parentLayer
            )

        guard let exporter =
            AVAssetExportSession(
                asset: asset,
                presetName: preset.avPresetName
            ) else {
            throw LocalCaptionBurnInError
                .exportSessionUnavailable
        }
        guard exporter.supportedFileTypes
            .contains(.mp4) else {
            throw LocalCaptionBurnInError
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
        exporter.videoComposition =
            videoComposition

        let box = CaptionExportSessionBox(
            exporter
        )
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
                            LocalCaptionBurnInError
                                .exportFailed(
                                    session.error?
                                        .localizedDescription
                                    ?? "Caption-Export fehlgeschlagen."
                                )
                    )
                default:
                    continuation.resume(
                        throwing:
                            LocalCaptionBurnInError
                                .exportFailed(
                                    "Caption-Export endete im Zustand \(session.status.rawValue)."
                                )
                    )
                }
            }
        }

        guard FileManager.default.fileExists(
            atPath: outputURL.path
        ) else {
            throw LocalCaptionBurnInError
                .missingOutput
        }
    }

    private static func textOverlayLayer(
        cue: TextOverlayCue,
        renderSize: CGSize
    ) -> CALayer {
        let width = renderSize.width * 0.72
        let height = max(
            renderSize.height * 0.12,
            84
        )
        let x = (renderSize.width - width) / 2
        let centerY = renderSize.height
            * (1 - cue.normalizedYFromTop)
        let y = min(
            max(centerY - (height / 2), 0),
            max(renderSize.height - height, 0)
        )

        let layer = CATextLayer()
        layer.frame = CGRect(
            x: x,
            y: y,
            width: width,
            height: height
        )
        layer.string = cue.text
        layer.alignmentMode = .center
        layer.isWrapped = true
        layer.truncationMode = .end
        layer.foregroundColor = NSColor.white.cgColor
        layer.backgroundColor = NSColor.black
            .withAlphaComponent(0.52)
            .cgColor
        layer.cornerRadius = max(
            renderSize.height * 0.012,
            10
        )
        layer.masksToBounds = true
        layer.contentsScale = 2

        let fontSize = max(
            renderSize.height * 0.05,
            28
        )
        layer.font = NSFont.systemFont(
            ofSize: fontSize,
            weight: .bold
        )
        layer.fontSize = fontSize
        layer.shadowOpacity = 0.35
        layer.shadowRadius = 3
        layer.shadowOffset = CGSize(
            width: 0,
            height: -1
        )
        layer.opacity = 0

        let visibility = CABasicAnimation(
            keyPath: "opacity"
        )
        visibility.fromValue = 1
        visibility.toValue = 1
        visibility.beginTime =
            AVCoreAnimationBeginTimeAtZero
            + cue.startSeconds
        visibility.duration = max(
            cue.durationSeconds,
            0.05
        )
        visibility.isRemovedOnCompletion = true
        layer.add(
            visibility,
            forKey: "blackstock-text-overlay-visible"
        )

        return layer
    }

    private static func captionLayer(
        cue: CaptionBurnInCue,
        renderSize: CGSize,
        style: CaptionVisualStyle
    ) -> CALayer {
        let width =
            renderSize.width * style.widthFactor
        let height =
            max(
                renderSize.height * style.heightFactor,
                style.minimumRenderedHeight
            )
        let x =
            (renderSize.width - width) / 2
        let y =
            renderSize.height * style.bottomOffsetFactor

        let layer = CATextLayer()
        layer.frame = CGRect(
            x: x,
            y: y,
            width: width,
            height: height
        )
        layer.string = cue.text
        layer.alignmentMode = .center
        layer.isWrapped = true
        layer.truncationMode = .end
        layer.foregroundColor =
            NSColor.white.cgColor
        layer.backgroundColor =
            NSColor.black
                .withAlphaComponent(
                    style.backgroundOpacity
                )
                .cgColor
        layer.cornerRadius =
            max(
                renderSize.height
                    * style.cornerRadiusFactor,
                8
            )
        layer.masksToBounds = true
        layer.contentsScale = 2
        let fontSize = max(
            renderSize.height
                * style.fontSizeFactor,
            style.minimumRenderedFontSize
        )
        let fontWeight: NSFont.Weight
        switch style.fontWeight {
        case .semibold:
            fontWeight = .semibold
        case .bold:
            fontWeight = .bold
        case .heavy:
            fontWeight = .heavy
        }
        layer.font = NSFont.systemFont(
            ofSize: fontSize,
            weight: fontWeight
        )
        layer.fontSize = fontSize
        layer.shadowOpacity = style.shadowOpacity
        layer.shadowRadius = 3
        layer.shadowOffset = CGSize(
            width: 0,
            height: -1
        )
        layer.opacity = 0

        let visibility =
            CABasicAnimation(
                keyPath: "opacity"
            )
        visibility.fromValue = 1
        visibility.toValue = 1
        visibility.beginTime =
            AVCoreAnimationBeginTimeAtZero
            + cue.startSeconds
        visibility.duration =
            max(cue.durationSeconds, 0.05)
        visibility.isRemovedOnCompletion = true
        layer.add(
            visibility,
            forKey: "blackstock-caption-visible"
        )

        return layer
    }
}
#endif
