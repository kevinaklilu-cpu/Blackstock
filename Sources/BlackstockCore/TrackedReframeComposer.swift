#if os(macOS)
import AVFoundation
import CoreGraphics
import Foundation

/// The same measured focal path drives preview and export. It does not identify a player or ball.
public enum TrackedReframeComposer {
    public static func focalSample(at seconds: Double, path: [ReframeFocalSample]) -> ReframeFocalSample? {
        let valid = path.filter { $0.sourceSeconds.isFinite && $0.focalX.isFinite && $0.focalY.isFinite }
            .sorted { $0.sourceSeconds < $1.sourceSeconds }
        guard let first = valid.first, let last = valid.last else { return nil }
        guard seconds > first.sourceSeconds else { return first }
        guard seconds < last.sourceSeconds else { return last }
        guard let upper = valid.firstIndex(where: { $0.sourceSeconds >= seconds }), upper > 0 else { return last }
        let a = valid[upper - 1], b = valid[upper]
        let fraction = min(max((seconds - a.sourceSeconds) / max(b.sourceSeconds - a.sourceSeconds, 0.001), 0), 1)
        // A large change of subject should not sweep the crop across the entire frame.
        if abs(a.focalX - b.focalX) > 0.18 { return fraction < 0.5 ? a : b }
        let eased = fraction * fraction * (3 - 2 * fraction)
        return .init(sourceSeconds: seconds, focalX: a.focalX + (b.focalX - a.focalX) * eased,
                     focalY: a.focalY + (b.focalY - a.focalY) * eased)
    }

    public static func apply(spec: ReframeSpec, timeline: EditTimelinePlan, naturalSize: CGSize,
                             preferredTransform: CGAffineTransform, renderSize: CGSize,
                             cues: [VisualEmphasisCue], to layer: AVMutableVideoCompositionLayerInstruction) -> Bool {
        guard spec.aspectRatio == .portrait9x16, spec.preserveFullFrame != true,
              let path = spec.focalPath, path.count >= 2 else { return false }
        var outputStart = 0.0
        for range in timeline.sourceRanges {
            let count = max(1, Int(ceil(range.durationSeconds * 30)))
            for index in 0...count {
                let local = min(range.durationSeconds, Double(index) / Double(count) * range.durationSeconds)
                let outputTime = outputStart + local
                guard let focus = focalSample(at: range.startSeconds + local, path: path),
                      let plan = ReframeTransformPlan.make(naturalSize: naturalSize, preferredTransform: preferredTransform,
                        spec: .init(aspectRatio: spec.aspectRatio, focalX: focus.focalX, focalY: focus.focalY, preserveFullFrame: false), renderSize: renderSize) else { continue }
                var scale = 1.0
                for cue in cues where outputTime >= cue.startSeconds && outputTime <= cue.startSeconds + cue.durationSeconds {
                    let ramp = min(0.45, max(cue.durationSeconds * 0.28, 0.18))
                    let phase = min(1, min((outputTime - cue.startSeconds) / ramp, (cue.startSeconds + cue.durationSeconds - outputTime) / ramp))
                    scale = max(scale, 1 + (cue.scale - 1) * phase * phase * (3 - 2 * phase))
                }
                let transform = VisualEmphasisComposer.zoomTransform(base: plan.transform, scale: scale,
                    anchor: CGPoint(x: renderSize.width / 2, y: renderSize.height / 2))
                layer.setTransform(transform, at: CMTime(seconds: outputTime, preferredTimescale: 600))
            }
            outputStart += range.durationSeconds
        }
        return true
    }
}
#endif
