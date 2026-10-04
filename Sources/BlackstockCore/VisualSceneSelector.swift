#if os(macOS)
import Foundation
import AVFoundation
import CoreGraphics

public struct VisualSceneSelection: Sendable {
    public let startSeconds: Double
    public let durationSeconds: Double
    public let explanation: String
}

/// A bounded, on-device visual-quality scan. It deliberately makes no claim
/// about semantic relevance, sporting highlights, or predicted audience response.
public actor VisualSceneSelector {
    public init() {}

    public func select(url: URL, sourceDuration: Double, requestedDuration: Double) async throws -> VisualSceneSelection? {
        guard sourceDuration.isFinite, requestedDuration.isFinite,
              sourceDuration > 0, requestedDuration > 0 else { return nil }
        let duration = min(sourceDuration, requestedDuration)
        let available = sourceDuration - duration
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 160, height: 90)
        generator.requestedTimeToleranceBefore = CMTime(seconds: 0.15, preferredTimescale: 600)
        generator.requestedTimeToleranceAfter = generator.requestedTimeToleranceBefore
        defer { generator.cancelAllCGImageGeneration() }
        var best: (start: Double, score: Double)?
        // Check beginning, middle and end of every candidate, preventing a
        // single attractive thumbnail from standing in for a black sequence.
        for index in 0..<8 {
            try Task.checkCancellation()
            let start = available * Double(index) / 7
            var scores: [Double] = []
            for fraction in [0.15, 0.5, 0.85] {
                let time = CMTime(seconds: start + duration * fraction, preferredTimescale: 600)
                guard let frame = try? await generator.image(at: time).image else { continue }
                scores.append(Self.quality(frame))
            }
            guard scores.count == 3 else { continue }
            let score = scores.min()! * 0.6 + scores.reduce(0, +) / 3 * 0.4
            if best == nil || score > best!.score { best = (start, score) }
        }
        try Task.checkCancellation()
        guard let best, best.score > 0.03 else { return nil }
        return .init(startSeconds: best.start, durationSeconds: duration,
            explanation: "Lokal visuell geprüft: Belichtung und Bildstruktur an drei Stellen des Ausschnitts. Themenbezug nicht automatisch bestätigt.")
    }

    private static func quality(_ image: CGImage) -> Double {
        let width = 32, height = 18
        var pixels = [UInt8](repeating: 0, count: width * height)
        let measured: Double = pixels.withUnsafeMutableBytes { bytes in
            guard let context = CGContext(data: bytes.baseAddress, width: width, height: height,
                bitsPerComponent: 8, bytesPerRow: width, space: CGColorSpaceCreateDeviceGray(), bitmapInfo: 0) else { return 0 }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            let values = bytes.bindMemory(to: UInt8.self)
            let mean = values.reduce(0.0) { $0 + Double($1) / 255 } / Double(values.count)
            guard mean > 0.04, mean < 0.96 else { return 0 }
            var edges = 0.0
            for y in 0..<height {
                for x in 1..<width {
                    edges += abs(Double(values[y * width + x]) - Double(values[y * width + x - 1])) / 255
                }
            }
            return min(1, edges / Double(height * (width - 1)) * 8) * 0.7
                + (1 - abs(mean - 0.5) * 2) * 0.3
        }
        return measured
    }
}
#endif
