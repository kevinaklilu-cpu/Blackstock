#if os(macOS)
import AVFoundation
import CoreGraphics

public enum VisualEmphasisComposer {
    public static func apply(
        cues: [VisualEmphasisCue],
        baseTransform: CGAffineTransform,
        renderSize: CGSize,
        to layer: AVMutableVideoCompositionLayerInstruction
    ) {
        layer.setTransform(baseTransform, at: .zero)

        for cue in cues {
            let start = CMTime(
                seconds: cue.startSeconds,
                preferredTimescale: 600
            )
            let duration = cue.durationSeconds
            let rampDuration = min(0.24, max(duration * 0.22, 0.12))
            let rampIn = CMTimeRange(
                start: start,
                duration: CMTime(
                    seconds: rampDuration,
                    preferredTimescale: 600
                )
            )
            let rampOutStart = CMTime(
                seconds: cue.startSeconds + duration - rampDuration,
                preferredTimescale: 600
            )
            let rampOut = CMTimeRange(
                start: rampOutStart,
                duration: rampIn.duration
            )

            let centerX = renderSize.width / 2
            let centerY = renderSize.height / 2
            let zoom = CGAffineTransform(
                translationX: centerX,
                y: centerY
            )
            .scaledBy(x: cue.scale, y: cue.scale)
            .translatedBy(x: -centerX, y: -centerY)
            let emphasized = baseTransform.concatenating(zoom)

            layer.setTransform(baseTransform, at: start)
            layer.setTransformRamp(
                fromStart: baseTransform,
                toEnd: emphasized,
                timeRange: rampIn
            )
            layer.setTransform(emphasized, at: CMTimeAdd(start, rampIn.duration))
            layer.setTransformRamp(
                fromStart: emphasized,
                toEnd: baseTransform,
                timeRange: rampOut
            )
            layer.setTransform(
                baseTransform,
                at: CMTimeAdd(rampOut.start, rampOut.duration)
            )
        }
    }
}
#endif
