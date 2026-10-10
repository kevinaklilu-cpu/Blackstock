#if os(macOS)
import AVFoundation
import CoreGraphics
import Foundation

public struct VisualMomentSample: Sendable {
    public let time: Double
    public let activity: Double
    public init(time: Double, activity: Double) { self.time = time; self.activity = activity }
}

/// Image-change measurements, not semantic goal detection or predicted audience response.
public enum VisualMomentPlanner {
    public static func activityScore(samples: [VisualMomentSample], range: EditTimeRange, duration: Double) -> Double {
        let values = samples.filter { $0.time >= range.startSeconds && $0.time <= range.endSeconds && $0.activity.isFinite }
            .map { max(0, $0.activity) }
        guard !values.isEmpty else { return 0 }
        let mean = values.reduce(0, +) / Double(values.count)
        let peak = values.max() ?? 0
        let evidence = mean * 0.8 + peak * 0.2
        // Continuous scoring avoids the previous saturated ties, which favored the intro.
        let edgeWeight = duration > 60 && (range.startSeconds < 3 || range.endSeconds > duration - 3) ? 0.7 : 1.0
        return evidence / (evidence + 0.15) * edgeWeight
    }

    public static func ranges(samples: [VisualMomentSample], duration: Double, maximumDuration: Double, profile: ClipOutputProfile = .short) -> [EditTimeRange] {
        guard duration.isFinite, duration >= 8, maximumDuration.isFinite, maximumDuration >= 8 else { return [] }
        let valid = samples.filter { $0.time.isFinite && $0.activity.isFinite && $0.time >= 0 && $0.time < duration }
            .sorted { $0.time < $1.time }
        guard !valid.isEmpty else { return [] }
        let mean = valid.map(\.activity).reduce(0, +) / Double(valid.count)
        let threshold = max(0.035, mean * 1.2)
        var selected: [EditTimeRange] = []
        for peak in valid.sorted(by: { $0.activity > $1.activity }) where peak.activity >= threshold {
            let before = valid.last { $0.time < peak.time - 3 && $0.activity < mean * 0.8 }?.time ?? max(0, peak.time - 8)
            let after = valid.first { $0.time > peak.time + 4 && $0.activity < mean * 0.8 }?.time ?? min(duration, peak.time + 10)
            let start = max(0, max(before - profile.leadIn, peak.time - maximumDuration * 0.5))
            let end = min(duration, min(max(after + profile.leadOut, start + min(profile.minimumDuration, maximumDuration)), start + maximumDuration))
            guard end - start >= 8 else { continue }
            let range = EditTimeRange(startSeconds: start, durationSeconds: end - start)
            guard !selected.contains(where: { min($0.endSeconds, end) - max($0.startSeconds, start) > min($0.durationSeconds, range.durationSeconds) * 0.35 }) else { continue }
            selected.append(range)
            if selected.count == 16 { break }
        }
        return selected
    }
}

public actor VisualMomentAnalyzer {
    public init() {}
    public func analyze(url: URL, duration: Double, maximumDuration: Double, profile: ClipOutputProfile = .short,
        progress: @escaping @Sendable (Double) async -> Void) async throws -> [LocalClipCandidate] {
        guard duration.isFinite, duration >= 8 else { return [] }
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 64, height: 36)
        generator.requestedTimeToleranceBefore = CMTime(seconds: 0.15, preferredTimescale: 600)
        generator.requestedTimeToleranceAfter = generator.requestedTimeToleranceBefore
        defer { generator.cancelAllCGImageGeneration() }
        let count = Int(min(600, max(2, ceil(duration / 1.5))))
        var previous: [UInt8]?
        var samples: [VisualMomentSample] = []
        for index in 0..<count {
            try Task.checkCancellation()
            let time = Double(index) * duration / Double(count)
            if let image = try? await generator.image(at: CMTime(seconds: time, preferredTimescale: 600)).image,
               let pixels = Self.pixels(image) {
                if let previous {
                    let difference = zip(previous, pixels).reduce(0.0) { $0 + abs(Double($1.0) - Double($1.1)) / 255 } / Double(pixels.count)
                    samples.append(.init(time: time, activity: difference))
                }
                previous = pixels
            }
            await progress(Double(index + 1) / Double(count))
        }
        try Task.checkCancellation()
        return VisualMomentPlanner.ranges(samples: samples, duration: duration, maximumDuration: maximumDuration, profile: profile).map { range in
            let activity = VisualMomentPlanner.activityScore(samples: samples, range: range, duration: duration)
            return LocalClipCandidate(sourceRange: range, transcriptPreview: "", wordCount: 0,
                averageConfidence: nil, segmentIDs: [], visualActivityScore: activity,
                selectionExplanation: "Bildbewegung und Szenenwechsel gemessen. Mit Vorlauf und Ausklang; kein automatisch bestätigtes Tor oder Spielereignis.")
        }
    }
    private static func pixels(_ image: CGImage) -> [UInt8]? {
        var data = [UInt8](repeating: 0, count: 64 * 36)
        let success = data.withUnsafeMutableBytes { bytes -> Bool in
            guard let context = CGContext(data: bytes.baseAddress, width: 64, height: 36, bitsPerComponent: 8,
                bytesPerRow: 64, space: CGColorSpaceCreateDeviceGray(), bitmapInfo: 0) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: 64, height: 36)); return true
        }
        return success ? data : nil
    }
}
#endif
