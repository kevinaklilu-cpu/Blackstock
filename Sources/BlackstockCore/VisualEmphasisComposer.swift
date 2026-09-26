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
        if starts.isEmpty {
            starts = [0.14, 0.47, 0.76].map { duration * $0 }
                .filter { $0 >= 1 && $0 + 1.25 <= duration - 0.5 }
        }
        var lastEnd = -Double.infinity
        return starts.compactMap { start in
            guard start >= lastEnd + 3 else { return nil }
            lastEnd = start + 1.25
            return VisualEmphasisCue(startSeconds: start, durationSeconds: 1.25, scale: 1.08)
        }
    }

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
