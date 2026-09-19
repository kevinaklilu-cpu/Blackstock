#if os(macOS)
import AudioToolbox
@preconcurrency import AVFoundation
import CoreMedia
import Foundation

public struct AudioLoudnessSnapshot: Codable, Sendable, Equatable {
    public let integratedLUFS: Double?
    public let maximumMomentaryLUFS: Double?
    public let maximumShortTermLUFS: Double?
    public let truePeakDBTP: Double?
    public let samplePeakDBFS: Double?
    public let sampleRateHz: Double
    public let channelCount: Int
    public let analyzedFrameCount: Int64
    public let absoluteGatedBlockCount: Int
    public let relativeGatedBlockCount: Int
    public let inspectedAt: Date

    public init(
        integratedLUFS: Double?,
        maximumMomentaryLUFS: Double?,
        maximumShortTermLUFS: Double?,
        truePeakDBTP: Double?,
        samplePeakDBFS: Double?,
        sampleRateHz: Double,
        channelCount: Int,
        analyzedFrameCount: Int64,
        absoluteGatedBlockCount: Int,
        relativeGatedBlockCount: Int,
        inspectedAt: Date
    ) {
        self.integratedLUFS = integratedLUFS
        self.maximumMomentaryLUFS = maximumMomentaryLUFS
        self.maximumShortTermLUFS = maximumShortTermLUFS
        self.truePeakDBTP = truePeakDBTP
        self.samplePeakDBFS = samplePeakDBFS
        self.sampleRateHz = sampleRateHz
        self.channelCount = channelCount
        self.analyzedFrameCount = analyzedFrameCount
        self.absoluteGatedBlockCount = absoluteGatedBlockCount
        self.relativeGatedBlockCount = relativeGatedBlockCount
        self.inspectedAt = inspectedAt
    }
}

public enum AudioLoudnessFinding: String, Codable, Sendable, Equatable {
    case noIntegratedLoudness = "NO_INTEGRATED_LOUDNESS"
    case truePeakAboveFullScale = "TRUE_PEAK_ABOVE_FULL_SCALE"
}

public struct AudioLoudnessAssessment: Codable, Sendable, Equatable {
    public let snapshot: AudioLoudnessSnapshot
    public let findings: [AudioLoudnessFinding]

    public init(
        snapshot: AudioLoudnessSnapshot,
        findings: [AudioLoudnessFinding]
    ) {
        self.snapshot = snapshot
        self.findings = findings
    }

    public static func evaluate(
        _ snapshot: AudioLoudnessSnapshot
    ) -> AudioLoudnessAssessment {
        var findings: [AudioLoudnessFinding] = []
        if snapshot.integratedLUFS == nil {
            findings.append(.noIntegratedLoudness)
        }
        if let truePeak = snapshot.truePeakDBTP,
           truePeak > 0 {
            findings.append(.truePeakAboveFullScale)
        }
        return .init(snapshot: snapshot, findings: findings)
    }
}

public enum LocalLoudnessAnalyzerError:
    Error,
    LocalizedError,
    Sendable,
    Equatable {
    case noAudioTrack
    case readerCreationFailed(String)
    case cannotAddReaderOutput
    case readerStartFailed(String)
    case missingAudioFormat
    case unsupportedSampleRate(Double)
    case unsupportedChannelCount(Int)
    case inconsistentAudioFormat
    case blockBufferAccessFailed(Int32)
    case incompleteInterleavedFrame
    case readerFailed(String)

    public var errorDescription: String? {
        switch self {
        case .noAudioTrack:
            return "Der finale Render enthält keine Audiospur."
        case .readerCreationFailed(let message):
            return "Audio-Reader konnte nicht erstellt werden: \(message)"
        case .cannotAddReaderOutput:
            return "48-kHz-PCM-Ausgabe konnte nicht vorbereitet werden."
        case .readerStartFailed(let message):
            return "Loudness-Reader konnte nicht starten: \(message)"
        case .missingAudioFormat:
            return "Das PCM-Audioformat konnte nicht bestimmt werden."
        case .unsupportedSampleRate(let rate):
            return "Die Loudness-Analyse erwartet 48 kHz, erhielt aber \(rate) Hz."
        case .unsupportedChannelCount(let count):
            return "Die professionelle Loudness-Analyse unterstützt aktuell Mono/Stereo; gefunden: \(count) Kanäle."
        case .inconsistentAudioFormat:
            return "Das decodierte Audioformat wechselte während der Analyse."
        case .blockBufferAccessFailed(let status):
            return "PCM-Daten konnten nicht gelesen werden (OSStatus \(status))."
        case .incompleteInterleavedFrame:
            return "PCM-Daten endeten innerhalb eines Mehrkanal-Frames."
        case .readerFailed(let message):
            return "Loudness-Analyse fehlgeschlagen: \(message)"
        }
    }
}

public struct LocalLoudnessAnalyzer: Sendable {
    public init() {}

    public func analyze(
        url: URL,
        now: Date = Date()
    ) async throws -> AudioLoudnessAssessment {
        let asset = AVURLAsset(url: url)
        let tracks = try await asset.loadTracks(withMediaType: .audio)
        guard let track = tracks.first else {
            throw LocalLoudnessAnalyzerError.noAudioTrack
        }

        let reader: AVAssetReader
        do {
            reader = try AVAssetReader(asset: asset)
        } catch {
            throw LocalLoudnessAnalyzerError.readerCreationFailed(
                error.localizedDescription
            )
        }

        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 48_000,
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
            throw LocalLoudnessAnalyzerError.cannotAddReaderOutput
        }
        reader.add(output)

        guard reader.startReading() else {
            throw LocalLoudnessAnalyzerError.readerStartFailed(
                reader.error?.localizedDescription
                    ?? "Reader konnte nicht starten."
            )
        }

        var meter: BS1770StreamingMeter?

        while reader.status == .reading,
              let sampleBuffer = output.copyNextSampleBuffer() {
            defer { CMSampleBufferInvalidate(sampleBuffer) }

            guard let format = CMSampleBufferGetFormatDescription(
                sampleBuffer
            ),
            let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(
                format
            ) else {
                throw LocalLoudnessAnalyzerError.missingAudioFormat
            }

            let sampleRate = asbd.pointee.mSampleRate
            let channelCount = Int(asbd.pointee.mChannelsPerFrame)

            guard abs(sampleRate - 48_000) < 1 else {
                throw LocalLoudnessAnalyzerError
                    .unsupportedSampleRate(sampleRate)
            }
            guard channelCount == 1 || channelCount == 2 else {
                throw LocalLoudnessAnalyzerError
                    .unsupportedChannelCount(channelCount)
            }

            if meter == nil {
                meter = try BS1770StreamingMeter(
                    channelCount: channelCount
                )
            } else if meter?.channelCount != channelCount {
                throw LocalLoudnessAnalyzerError
                    .inconsistentAudioFormat
            }

            guard let blockBuffer = CMSampleBufferGetDataBuffer(
                sampleBuffer
            ) else {
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
                    throw LocalLoudnessAnalyzerError
                        .blockBufferAccessFailed(status)
                }
                continue
            }

            let floatCount = totalLength / MemoryLayout<Float>.size
            guard floatCount % channelCount == 0 else {
                throw LocalLoudnessAnalyzerError
                    .incompleteInterleavedFrame
            }

            let floats = UnsafeRawPointer(dataPointer)
                .bindMemory(
                    to: Float.self,
                    capacity: floatCount
                )
            try meter?.append(
                interleaved: floats,
                sampleCount: floatCount
            )
        }

        if reader.status == .failed {
            throw LocalLoudnessAnalyzerError.readerFailed(
                reader.error?.localizedDescription
                    ?? "Audioanalyse fehlgeschlagen."
            )
        }

        guard var meter else {
            let snapshot = AudioLoudnessSnapshot(
                integratedLUFS: nil,
                maximumMomentaryLUFS: nil,
                maximumShortTermLUFS: nil,
                truePeakDBTP: nil,
                samplePeakDBFS: nil,
                sampleRateHz: 48_000,
                channelCount: 0,
                analyzedFrameCount: 0,
                absoluteGatedBlockCount: 0,
                relativeGatedBlockCount: 0,
                inspectedAt: now
            )
            return .evaluate(snapshot)
        }

        return meter.finalize(inspectedAt: now)
    }
}

public enum BS1770LoudnessMeter {
    public static func analyzePCM48k(
        interleaved: [Float],
        channelCount: Int,
        inspectedAt: Date = Date()
    ) throws -> AudioLoudnessAssessment {
        var meter = try BS1770StreamingMeter(
            channelCount: channelCount
        )
        try interleaved.withUnsafeBufferPointer { buffer in
            guard let base = buffer.baseAddress else {
                return
            }
            try meter.append(
                interleaved: base,
                sampleCount: buffer.count
            )
        }
        return meter.finalize(inspectedAt: inspectedAt)
    }
}

private struct Biquad {
    let b0: Double
    let b1: Double
    let b2: Double
    let a1: Double
    let a2: Double

    var x1 = 0.0
    var x2 = 0.0
    var y1 = 0.0
    var y2 = 0.0

    mutating func process(_ input: Double) -> Double {
        let output =
            b0 * input
            + b1 * x1
            + b2 * x2
            - a1 * y1
            - a2 * y2

        x2 = x1
        x1 = input
        y2 = y1
        y1 = output
        return output
    }
}

private final class BS1770ChannelDSP {
    private var shelf = Biquad(
        b0: 1.53512485958697,
        b1: -2.69169618940638,
        b2: 1.19839281085285,
        a1: -1.69065929318241,
        a2: 0.73248077421585
    )
    private var highPass = Biquad(
        b0: 1.0,
        b1: -2.0,
        b2: 1.0,
        a1: -1.99004745483398,
        a2: 0.99007225036621
    )

    private var truePeakHistory = [Double](
        repeating: 0,
        count: 12
    )

    func process(_ sample: Double) -> (
        weighted: Double,
        truePeak: Double
    ) {
        let weighted = highPass.process(
            shelf.process(sample)
        )
        let truePeak = processTruePeak(sample)
        return (weighted, truePeak)
    }

    func flushTruePeak() -> Double {
        processTruePeak(0)
    }

    private func processTruePeak(
        _ sample: Double
    ) -> Double {
        for index in stride(
            from: truePeakHistory.count - 1,
            through: 1,
            by: -1
        ) {
            truePeakHistory[index] =
                truePeakHistory[index - 1]
        }
        truePeakHistory[0] = sample

        var maximum = abs(sample)
        for phase in Self.truePeakPhases {
            var interpolated = 0.0
            for index in 0..<12 {
                interpolated +=
                    phase[index]
                    * truePeakHistory[index]
            }
            maximum = max(
                maximum,
                abs(interpolated)
            )
        }
        return maximum
    }

    // ITU-R BS.1770-5 Annex 2: 48-order, four-phase FIR
    // interpolator for 48 kHz -> 192 kHz true-peak metering.
    private static let truePeakPhases: [[Double]] = [
        [
            0.0017089843750,
            0.0109863281250,
            -0.0196533203125,
            0.0332031250000,
            -0.0594482421875,
            0.1373291015625,
            0.9721679687500,
            -0.1022949218750,
            0.0476074218750,
            -0.0266113281250,
            0.0148925781250,
            -0.0083007812500
        ],
        [
            -0.0291748046875,
            0.0292968750000,
            -0.0517578125000,
            0.0891113281250,
            -0.1665039062500,
            0.4650878906250,
            0.7797851562500,
            -0.2003173828125,
            0.1015625000000,
            -0.0582275390625,
            0.0330810546875,
            -0.0189208984375
        ],
        [
            -0.0189208984375,
            0.0330810546875,
            -0.0582275390625,
            0.1015625000000,
            -0.2003173828125,
            0.7797851562500,
            0.4650878906250,
            -0.1665039062500,
            0.0891113281250,
            -0.0517578125000,
            0.0292968750000,
            -0.0291748046875
        ],
        [
            -0.0083007812500,
            0.0148925781250,
            -0.0266113281250,
            0.0476074218750,
            -0.1022949218750,
            0.9721679687500,
            0.1373291015625,
            -0.0594482421875,
            0.0332031250000,
            -0.0196533203125,
            0.0109863281250,
            0.0017089843750
        ]
    ]
}

private struct RollingEnergyWindow {
    private var values: [Double]
    private var index = 0
    private(set) var count = 0
    private(set) var sum = 0.0

    init(size: Int) {
        values = [Double](
            repeating: 0,
            count: size
        )
    }

    mutating func append(
        _ value: Double
    ) {
        if count < values.count {
            values[index] = value
            sum += value
            count += 1
        } else {
            sum -= values[index]
            values[index] = value
            sum += value
        }
        index = (index + 1) % values.count
    }

    var isFull: Bool {
        count == values.count
    }

    var mean: Double? {
        guard isFull, !values.isEmpty else {
            return nil
        }
        return sum / Double(values.count)
    }
}

private struct BS1770StreamingMeter {
    static let sampleRate = 48_000
    static let momentaryFrames = 19_200
    static let shortTermFrames = 144_000
    static let stepFrames = 4_800

    let channelCount: Int
    private var channels: [BS1770ChannelDSP]
    private var momentaryWindow = RollingEnergyWindow(
        size: Self.momentaryFrames
    )
    private var shortTermWindow = RollingEnergyWindow(
        size: Self.shortTermFrames
    )

    private var frameCount: Int64 = 0
    private var samplePeak = 0.0
    private var truePeak = 0.0
    private var gatingBlockEnergies: [Double] = []
    private var maximumMomentary: Double?
    private var maximumShortTerm: Double?

    init(channelCount: Int) throws {
        guard channelCount == 1 || channelCount == 2 else {
            throw LocalLoudnessAnalyzerError
                .unsupportedChannelCount(channelCount)
        }
        self.channelCount = channelCount
        self.channels = (0..<channelCount).map { _ in
            BS1770ChannelDSP()
        }
    }

    mutating func append(
        interleaved: UnsafePointer<Float>,
        sampleCount: Int
    ) throws {
        guard sampleCount % channelCount == 0 else {
            throw LocalLoudnessAnalyzerError
                .incompleteInterleavedFrame
        }

        let frames = sampleCount / channelCount
        for frame in 0..<frames {
            var weightedEnergy = 0.0

            for channel in 0..<channelCount {
                let sample = Double(
                    interleaved[
                        frame * channelCount + channel
                    ]
                )
                guard sample.isFinite else {
                    continue
                }

                samplePeak = max(
                    samplePeak,
                    abs(sample)
                )

                let processed = channels[channel]
                    .process(sample)
                truePeak = max(
                    truePeak,
                    processed.truePeak
                )
                weightedEnergy +=
                    processed.weighted
                    * processed.weighted
            }

            momentaryWindow.append(weightedEnergy)
            shortTermWindow.append(weightedEnergy)
            frameCount += 1

            if momentaryWindow.isFull,
               (
                    frameCount
                    - Int64(Self.momentaryFrames)
               ) % Int64(Self.stepFrames) == 0,
               let energy = momentaryWindow.mean {
                gatingBlockEnergies.append(energy)
                if let loudness = Self.loudness(
                    energy: energy
                ) {
                    maximumMomentary = max(
                        maximumMomentary
                            ?? -Double.infinity,
                        loudness
                    )
                }
            }

            if shortTermWindow.isFull,
               (
                    frameCount
                    - Int64(Self.shortTermFrames)
               ) % Int64(Self.stepFrames) == 0,
               let energy = shortTermWindow.mean,
               let loudness = Self.loudness(
                    energy: energy
               ) {
                maximumShortTerm = max(
                    maximumShortTerm
                        ?? -Double.infinity,
                    loudness
                )
            }
        }
    }

    mutating func finalize(
        inspectedAt: Date
    ) -> AudioLoudnessAssessment {
        // Flush the 12-tap true-peak interpolator with zeros.
        for _ in 0..<11 {
            for channel in channels {
                truePeak = max(
                    truePeak,
                    channel.flushTruePeak()
                )
            }
        }

        let absoluteBlocks = gatingBlockEnergies.filter {
            guard let level = Self.loudness(
                energy: $0
            ) else {
                return false
            }
            return level > -70
        }

        let absoluteLoudness = Self.loudness(
            energy: Self.mean(absoluteBlocks)
        )
        let relativeThreshold = absoluteLoudness.map {
            $0 - 10
        }

        let relativeBlocks: [Double]
        if let relativeThreshold {
            relativeBlocks = absoluteBlocks.filter {
                guard let level = Self.loudness(
                    energy: $0
                ) else {
                    return false
                }
                return level > relativeThreshold
            }
        } else {
            relativeBlocks = []
        }

        let integrated = Self.loudness(
            energy: Self.mean(relativeBlocks)
        )
        let snapshot = AudioLoudnessSnapshot(
            integratedLUFS: integrated,
            maximumMomentaryLUFS: maximumMomentary,
            maximumShortTermLUFS: maximumShortTerm,
            truePeakDBTP: Self.db(
                amplitude: truePeak
            ),
            samplePeakDBFS: Self.db(
                amplitude: samplePeak
            ),
            sampleRateHz: Double(Self.sampleRate),
            channelCount: channelCount,
            analyzedFrameCount: frameCount,
            absoluteGatedBlockCount:
                absoluteBlocks.count,
            relativeGatedBlockCount:
                relativeBlocks.count,
            inspectedAt: inspectedAt
        )
        return .evaluate(snapshot)
    }

    private static func mean(
        _ values: [Double]
    ) -> Double? {
        guard !values.isEmpty else {
            return nil
        }
        return values.reduce(0, +)
            / Double(values.count)
    }

    private static func loudness(
        energy: Double?
    ) -> Double? {
        guard let energy,
              energy.isFinite,
              energy > 0 else {
            return nil
        }
        return -0.691 + 10 * log10(energy)
    }

    private static func db(
        amplitude: Double
    ) -> Double? {
        guard amplitude.isFinite,
              amplitude > 0 else {
            return nil
        }
        return 20 * log10(amplitude)
    }
}
#endif
