#if os(macOS)
import Foundation
@preconcurrency import AVFoundation
import CoreMedia
import AudioToolbox

public struct AudioSignalSnapshot: Codable, Sendable, Equatable {
    public let peakDBFS: Double?
    public let rmsDBFS: Double?
    public let analyzedSampleCount: Int64
    public let fullScaleSampleCount: Int64
    public let inspectedAt: Date

    public init(
        peakDBFS: Double?,
        rmsDBFS: Double?,
        analyzedSampleCount: Int64,
        fullScaleSampleCount: Int64,
        inspectedAt: Date
    ) {
        self.peakDBFS = peakDBFS
        self.rmsDBFS = rmsDBFS
        self.analyzedSampleCount = analyzedSampleCount
        self.fullScaleSampleCount = fullScaleSampleCount
        self.inspectedAt = inspectedAt
    }

    public var fullScaleSampleRatio: Double? {
        guard analyzedSampleCount > 0 else { return nil }
        return Double(fullScaleSampleCount) / Double(analyzedSampleCount)
    }
}

public enum AudioSignalFinding: String, Codable, Sendable, Equatable {
    case noSamples = "NO_SAMPLES"
    case fullScaleSamplesDetected = "FULL_SCALE_SAMPLES_DETECTED"
}

public struct AudioSignalAssessment: Codable, Sendable, Equatable {
    public let snapshot: AudioSignalSnapshot
    public let findings: [AudioSignalFinding]

    public init(
        snapshot: AudioSignalSnapshot,
        findings: [AudioSignalFinding]
    ) {
        self.snapshot = snapshot
        self.findings = findings
    }

    public static func evaluate(
        _ snapshot: AudioSignalSnapshot
    ) -> AudioSignalAssessment {
        var findings: [AudioSignalFinding] = []
        if snapshot.analyzedSampleCount == 0 {
            findings.append(.noSamples)
        }
        if snapshot.fullScaleSampleCount > 0 {
            findings.append(.fullScaleSamplesDetected)
        }
        return .init(snapshot: snapshot, findings: findings)
    }
}

public enum LocalAudioSignalAnalyzerError: Error, Sendable, Equatable {
    case noAudioTrack
    case readerCreationFailed(String)
    case cannotAddReaderOutput
    case readerStartFailed(String)
    case blockBufferAccessFailed(Int32)
    case readerFailed(String)
}

public struct LocalAudioSignalAnalyzer: Sendable {
    public init() {}

    public func analyze(
        url: URL,
        now: Date = Date()
    ) async throws -> AudioSignalAssessment {
        let asset = AVURLAsset(url: url)
        let tracks = try await asset.loadTracks(withMediaType: .audio)
        guard let track = tracks.first else {
            throw LocalAudioSignalAnalyzerError.noAudioTrack
        }

        let reader: AVAssetReader
        do {
            reader = try AVAssetReader(asset: asset)
        } catch {
            throw LocalAudioSignalAnalyzerError.readerCreationFailed(
                error.localizedDescription
            )
        }

        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsNonInterleaved: false,
            AVLinearPCMIsBigEndianKey: false
        ]
        let output = AVAssetReaderTrackOutput(
            track: track,
            outputSettings: settings
        )
        output.alwaysCopiesSampleData = false

        guard reader.canAdd(output) else {
            throw LocalAudioSignalAnalyzerError.cannotAddReaderOutput
        }
        reader.add(output)

        guard reader.startReading() else {
            throw LocalAudioSignalAnalyzerError.readerStartFailed(
                reader.error?.localizedDescription ?? "Reader konnte nicht starten."
            )
        }

        var peak: Float = 0
        var sumSquares: Double = 0
        var sampleCount: Int64 = 0
        var fullScaleCount: Int64 = 0

        while reader.status == .reading,
              let sampleBuffer = output.copyNextSampleBuffer() {
            defer { CMSampleBufferInvalidate(sampleBuffer) }

            guard let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else {
                continue
            }

            var lengthAtOffset = 0
            var totalLength = 0
            var dataPointer: UnsafeMutablePointer<Int8>?
            let status = CMBlockBufferGetDataPointer(
                blockBuffer,
                atOffset: 0,
                lengthAtOffsetOut: &lengthAtOffset,
                totalLengthOut: &totalLength,
                dataPointerOut: &dataPointer
            )
            guard status == kCMBlockBufferNoErr,
                  let dataPointer,
                  totalLength >= MemoryLayout<Float>.size else {
                if status != kCMBlockBufferNoErr {
                    throw LocalAudioSignalAnalyzerError.blockBufferAccessFailed(status)
                }
                continue
            }

            let floatCount = totalLength / MemoryLayout<Float>.size
            let floats = UnsafeRawPointer(dataPointer)
                .bindMemory(to: Float.self, capacity: floatCount)

            for index in 0..<floatCount {
                let value = floats[index]
                guard value.isFinite else { continue }
                let magnitude = abs(value)
                peak = max(peak, magnitude)
                let doubleValue = Double(value)
                sumSquares += doubleValue * doubleValue
                sampleCount += 1
                if magnitude >= 0.9999 {
                    fullScaleCount += 1
                }
            }
        }

        if reader.status == .failed {
            throw LocalAudioSignalAnalyzerError.readerFailed(
                reader.error?.localizedDescription ?? "Audioanalyse fehlgeschlagen."
            )
        }

        let peakDBFS = Self.dbfs(amplitude: Double(peak))
        let rmsAmplitude = sampleCount > 0
            ? sqrt(sumSquares / Double(sampleCount))
            : 0
        let rmsDBFS = Self.dbfs(amplitude: rmsAmplitude)

        return .evaluate(
            .init(
                peakDBFS: peakDBFS,
                rmsDBFS: rmsDBFS,
                analyzedSampleCount: sampleCount,
                fullScaleSampleCount: fullScaleCount,
                inspectedAt: now
            )
        )
    }

    public static func dbfs(amplitude: Double) -> Double? {
        guard amplitude.isFinite, amplitude > 0 else { return nil }
        return 20 * log10(amplitude)
    }
}
#endif
