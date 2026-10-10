#if os(macOS)
import Foundation

/// Captions follow the audible source. Lead words are never retained underneath
/// another speaker, and unrecognized source speech never receives invented text.
public enum StoryTranscriptComposer {
    public static func compose(lead: LocalTranscript?, inputs: [SupplementalVideoInsertInput],
                               settings: [SupplementalVideoInsertSetting]) -> LocalTranscript? {
        let audible = inputs.filter(\.usesOriginalAudio)
        guard !audible.isEmpty else { return lead }
        var segments = (lead?.segments ?? []).filter { segment in
            !audible.contains { scene in
                segment.startSeconds < scene.timelineStartSeconds + scene.durationSeconds
                    && segment.startSeconds + segment.durationSeconds > scene.timelineStartSeconds
            }
        }
        for input in audible {
            let scene = settings.first { $0.captureID == input.captureID }?.matchedScenes?.first {
                abs($0.outputStart - input.timelineStartSeconds) < 0.001
                    && abs($0.sourceStart - input.sourceStartSeconds) < 0.001
            }
            for word in scene?.spokenSegments ?? [] {
                let start = max(word.start, input.sourceStartSeconds)
                let end = min(word.start + word.duration, input.sourceStartSeconds + input.durationSeconds)
                guard end > start, !word.text.isEmpty else { continue }
                segments.append(.init(startSeconds: input.timelineStartSeconds + start - input.sourceStartSeconds,
                    durationSeconds: end - start, text: word.text, confidence: word.confidence))
            }
        }
        segments.sort { $0.startSeconds < $1.startSeconds }
        guard !segments.isEmpty else { return nil }
        return LocalTranscript(localeIdentifier: lead?.localeIdentifier ?? "und",
            text: segments.map(\.text).joined(separator: " "), segments: segments,
            onDevice: true, createdAt: Date())
    }
}
#endif
