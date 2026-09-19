#if os(macOS)
import Foundation
@preconcurrency import AVFoundation
import CoreMedia

public struct AudioTechnicalSnapshot: Codable, Sendable, Equatable {
    public let hasAudioTrack: Bool
    public let sampleRateHz: Double?
    public let channelCount: Int?
    public let inspectedAt: Date

    public init(
        hasAudioTrack: Bool,
        sampleRateHz: Double?,
        channelCount: Int?,
        inspectedAt: Date
    ) {
        self.hasAudioTrack = hasAudioTrack
        self.sampleRateHz = sampleRateHz
        self.channelCount = channelCount
        self.inspectedAt = inspectedAt
    }
}

public enum AudioTechnicalFinding: String, Codable, Sendable, Equatable {
    case noAudioTrack = "NO_AUDIO_TRACK"
    case lowSampleRate = "LOW_SAMPLE_RATE"
    case monoAudio = "MONO_AUDIO"
}

public struct AudioTechnicalAssessment: Codable, Sendable, Equatable {
    public let snapshot: AudioTechnicalSnapshot
    public let findings: [AudioTechnicalFinding]

    public init(
        snapshot: AudioTechnicalSnapshot,
        findings: [AudioTechnicalFinding]
    ) {
        self.snapshot = snapshot
        self.findings = findings
    }

    public static func evaluate(
        _ snapshot: AudioTechnicalSnapshot
    ) -> AudioTechnicalAssessment {
        var findings: [AudioTechnicalFinding] = []

        if !snapshot.hasAudioTrack {
            findings.append(.noAudioTrack)
        }

        if let sampleRate = snapshot.sampleRateHz,
           sampleRate > 0,
           sampleRate < 44_100 {
            findings.append(.lowSampleRate)
        }

        if snapshot.channelCount == 1 {
            findings.append(.monoAudio)
        }

        return .init(snapshot: snapshot, findings: findings)
    }
}

public enum LocalAudioInspectionError: Error, Sendable, Equatable {
    case formatDescriptionUnavailable
}

public struct LocalAudioTechnicalInspector: Sendable {
    public init() {}

    public func inspect(
        url: URL,
        now: Date = Date()
    ) async throws -> AudioTechnicalAssessment {
        let asset = AVURLAsset(url: url)
        let tracks = try await asset.loadTracks(withMediaType: .audio)

        guard let track = tracks.first else {
            return .evaluate(
                .init(
                    hasAudioTrack: false,
                    sampleRateHz: nil,
                    channelCount: nil,
                    inspectedAt: now
                )
            )
        }

        let descriptions = try await track.load(.formatDescriptions)
        guard let description = descriptions.first,
              let basic = CMAudioFormatDescriptionGetStreamBasicDescription(
                description
              ) else {
            throw LocalAudioInspectionError.formatDescriptionUnavailable
        }

        return .evaluate(
            .init(
                hasAudioTrack: true,
                sampleRateHz: basic.pointee.mSampleRate,
                channelCount: Int(basic.pointee.mChannelsPerFrame),
                inspectedAt: now
            )
        )
    }
}
#endif
