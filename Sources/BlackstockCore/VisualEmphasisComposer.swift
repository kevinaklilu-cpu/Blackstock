#if os(macOS)
import AVFoundation
import CoreGraphics

public enum VisualEmphasisComposer {
    /// Align visual changes with speech resumed after a pause. With no reliable
    /// transcript, use restrained rhythmic accents, not semantic predictions.
    public static func automaticCues(
        duration: Double,
        transcript: LocalTranscript?
    ) -> [VisualEmphasisCue] {
        guard duration.isFinite, duration >= 8 else { return [] }
        let segments = (transcript?.segments ?? []).filter {
            $0.startSeconds.isFinite && $0.durationSeconds.isFinite
                && $0.durationSeconds > 0 && $0.confidence >= 0.5
                && !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }.sorted { $0.startSeconds < $1.startSeconds }
        var starts: [Double] = []
        var previousEnd: Double = 0
        for segment in segments {
            let start = segment.startSeconds
            if start - previousEnd >= 0.35,
               start >= 1, start + 1.25 <= duration - 0.5,
               starts.last.map({ start - $0 >= 5 }) ?? true {
                starts.append(start)
            }
            previousEnd = max(previousEnd, start + segment.durationSeconds)
            if starts.count == 3 { break }
        }
        // No arbitrary zooms when no speech boundary supports an accent.
        // Supplemental picture cuts already provide visual variation.
        var lastEnd = -Double.infinity
        return starts.compactMap { start in
            guard start >= lastEnd + 3 else { return nil }
            lastEnd = start + 1.25
            return VisualEmphasisCue(startSeconds: start, durationSeconds: 1.25, scale: 1.08)
        }
    }

    public static func zoomTransform(base: CGAffineTransform, scale: Double, anchor: CGPoint) -> CGAffineTransform {
        base.concatenating(CGAffineTransform(translationX: anchor.x, y: anchor.y)
            .scaledBy(x: scale, y: scale).translatedBy(x: -anchor.x, y: -anchor.y))
    }

    public static func apply(
        cues: [VisualEmphasisCue],
        baseTransform: CGAffineTransform,
        renderSize: CGSize,
        anchor: CGPoint? = nil,
        to layer: AVMutableVideoCompositionLayerInstruction
    ) {
        layer.setTransform(baseTransform, at: .zero)

        for cue in cues {
            let start = CMTime(
                seconds: cue.startSeconds,
                preferredTimescale: 600
            )
            let duration = cue.durationSeconds
            let rampDuration = min(0.45, max(duration * 0.28, 0.18))
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

            let focal = anchor ?? CGPoint(x: renderSize.width / 2, y: renderSize.height / 2)
            let emphasized = zoomTransform(base: baseTransform, scale: cue.scale, anchor: focal)
            layer.setTransform(emphasized, at: CMTimeAdd(start, rampIn.duration))
            // Piecewise smoothstep avoids abrupt acceleration while preserving
            // exactly the same transform and timing in preview and export.
            for step in 0..<6 {
                let t0 = Double(step) / 6
                let t1 = Double(step + 1) / 6
                let ease0 = t0 * t0 * (3 - 2 * t0)
                let ease1 = t1 * t1 * (3 - 2 * t1)
                let from = zoomTransform(base: baseTransform, scale: 1 + (cue.scale - 1) * ease0, anchor: focal)
                let to = zoomTransform(base: baseTransform, scale: 1 + (cue.scale - 1) * ease1, anchor: focal)
                layer.setTransformRamp(fromStart: from, toEnd: to, timeRange: CMTimeRange(
                    start: CMTimeAdd(start, CMTime(seconds: rampDuration * t0, preferredTimescale: 600)),
                    duration: CMTime(seconds: rampDuration / 6, preferredTimescale: 600)))
                layer.setTransformRamp(fromStart: to, toEnd: from, timeRange: CMTimeRange(
                    start: CMTimeAdd(rampOutStart, CMTime(seconds: rampDuration * (1 - t1), preferredTimescale: 600)),
                    duration: CMTime(seconds: rampDuration / 6, preferredTimescale: 600)))
            }
            layer.setTransform(
                baseTransform,
                at: CMTimeAdd(rampOut.start, rampOut.duration)
            )
        }
    }
}
#endif
