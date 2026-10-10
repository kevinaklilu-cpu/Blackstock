#if os(macOS)
import Foundation
@preconcurrency import AVFoundation
import AppKit
import QuartzCore
import ImageIO

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

        let raw: [CaptionBurnInCue] = transcript.segments.compactMap {
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
        var grouped: [CaptionBurnInCue] = []
        for cue in raw.sorted(by: { $0.startSeconds < $1.startSeconds }) {
            if let previous = grouped.last,
               cue.startSeconds - previous.startSeconds - previous.durationSeconds < 0.35,
               cue.startSeconds >= previous.startSeconds + previous.durationSeconds - 0.05,
               cue.startSeconds + cue.durationSeconds - previous.startSeconds <= 3.2,
               (previous.text + " " + cue.text).split(whereSeparator: \.isWhitespace).count <= 7,
               previous.text.last.map({ !".!?".contains($0) }) == true {
                grouped[grouped.count - 1] = .init(id: previous.id, startSeconds: previous.startSeconds,
                    durationSeconds: cue.startSeconds + cue.durationSeconds - previous.startSeconds,
                    text: previous.text + " " + cue.text)
            } else { grouped.append(cue) }
        }
        return grouped
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

        let captionCues = transcript.map {
            CaptionBurnInPlanner().cues(transcript: $0, outputDurationSeconds: durationSeconds)
        } ?? []
        let overlays: [TimedVideoOverlay] = try await MainActor.run {
            var result: [TimedVideoOverlay] = []
            func rasterize(_ layer: CALayer, start: Double, duration: Double) throws {
                layer.removeAllAnimations()
                layer.opacity = 1
                let frame = layer.frame
                guard let context = CGContext(data: nil, width: Int(ceil(frame.width)),
                    height: Int(ceil(frame.height)), bitsPerComponent: 8, bytesPerRow: 0,
                    space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
                else { throw LocalCaptionBurnInError.invalidVideoSize }
                layer.displayIfNeeded()
                layer.render(in: context)
                guard let image = context.makeImage() else { throw LocalCaptionBurnInError.invalidVideoSize }
                let data = NSMutableData()
                guard let destination = CGImageDestinationCreateWithData(data, "public.png" as CFString, 1, nil)
                else { throw LocalCaptionBurnInError.invalidVideoSize }
                CGImageDestinationAddImage(destination, image, nil)
                guard CGImageDestinationFinalize(destination) else { throw LocalCaptionBurnInError.invalidVideoSize }
                result.append(.init(imageData: data as Data, frame: frame, start: start, duration: duration))
            }
            for cue in captionCues {
                try rasterize(Self.captionLayer(cue: cue, renderSize: renderSize, style: style),
                    start: cue.startSeconds, duration: cue.durationSeconds)
            }
            for cue in textOverlays {
                try rasterize(Self.textOverlayLayer(cue: cue, renderSize: renderSize),
                    start: cue.startSeconds, duration: cue.durationSeconds)
            }
            return result
        }
        guard !overlays.isEmpty else {
            if FileManager.default.fileExists(atPath: outputURL.path) { try FileManager.default.removeItem(at: outputURL) }
            try FileManager.default.copyItem(at: inputURL, to: outputURL)
            return
        }
        // Composite text into each decoded source frame. Core Animation is only
        // used to rasterize a static text image, never to advance video timing.
        try await LocalSupplementalVideoCompositor().render(inputURL: inputURL,
            supplementalVideo: [], outputURL: outputURL, preset: preset, overlays: overlays)
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
