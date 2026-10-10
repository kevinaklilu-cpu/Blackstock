import Foundation

/// Distributes selected source ranges over the lead timeline, preserving each audio mode.
/// It plans pacing and coverage, not semantic correspondence to spoken claims.
public enum StoryMontagePlanner {
    public static func distribute(_ inputs: [SupplementalVideoInsertInput], outputDuration: Double,
                                  shotDuration: Double = 6) -> [SupplementalVideoInsertInput] {
        guard outputDuration.isFinite, outputDuration > 0, shotDuration.isFinite, shotDuration >= 1,
              inputs.allSatisfy({ $0.durationSeconds.isFinite && $0.durationSeconds > 0
                  && $0.sourceStartSeconds.isFinite && $0.sourceStartSeconds >= 0 }) else { return [] }
        let total = inputs.reduce(0) { $0 + $1.durationSeconds }
        guard total <= outputDuration, total > 0 else { return [] }
        // Bound memory and work for long recordings; increase shot length if necessary.
        let shot = max(shotDuration, total / 240)
        var consumed = Array(repeating: 0.0, count: inputs.count)
        var chunks: [(index: Int, offset: Double, duration: Double)] = []
        while true {
            var advanced = false
            for (index, input) in inputs.enumerated() {
                let remaining = input.durationSeconds - consumed[index]
                guard remaining > 0.001 else { continue }
                let duration = min(shot, remaining)
                chunks.append((index, consumed[index], duration))
                consumed[index] += duration
                advanced = true
            }
            if !advanced { break }
        }
        let gap = max(0, (outputDuration - total) / Double(chunks.count + 1))
        var cursor = gap
        return chunks.map { chunk in
            let input = inputs[chunk.index]
            let result = SupplementalVideoInsertInput(captureID: input.captureID, fileURL: input.fileURL,
                timelineStartSeconds: cursor, sourceStartSeconds: input.sourceStartSeconds + chunk.offset,
                durationSeconds: chunk.duration, usesOriginalAudio: input.usesOriginalAudio)
            cursor += chunk.duration + gap
            return result
        }
    }
}
