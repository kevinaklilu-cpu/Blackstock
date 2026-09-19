#if os(macOS)
import Foundation
@preconcurrency import AVFoundation
import CoreGraphics

public struct RenderTechnicalSnapshot: Sendable, Equatable {
    public let fileSizeBytes: Int64
    public let durationSeconds: Double
    public let videoTrackCount: Int
    public let width: Int
    public let height: Int
    public let inspectedAt: Date

    public init(
        fileSizeBytes: Int64,
        durationSeconds: Double,
        videoTrackCount: Int,
        width: Int,
        height: Int,
        inspectedAt: Date
    ) {
        self.fileSizeBytes = fileSizeBytes
        self.durationSeconds = durationSeconds
        self.videoTrackCount = videoTrackCount
        self.width = width
        self.height = height
        self.inspectedAt = inspectedAt
    }
}

public enum RenderTechnicalBlocker: String, Sendable, Equatable, CaseIterable {
    case emptyFile
    case nonPositiveDuration
    case missingVideoTrack
    case invalidDimensions
    case durationMismatch
    case dimensionMismatch
    case presetResolutionMismatch
}

public struct RenderTechnicalAssessment: Sendable, Equatable {
    public let snapshot: RenderTechnicalSnapshot
    public let blockers: [RenderTechnicalBlocker]

    public init(
        snapshot: RenderTechnicalSnapshot,
        blockers: [RenderTechnicalBlocker]
    ) {
        self.snapshot = snapshot
        self.blockers = blockers
    }

    public var validated: Bool {
        blockers.isEmpty
    }
}

public struct RenderTechnicalValidator: Sendable {
    public init() {}

    public func assess(
        snapshot: RenderTechnicalSnapshot,
        expectedDurationSeconds: Double,
        expectedRenderSize: CGSize?,
        expectedPreset: LocalRenderPreset? = nil
    ) -> RenderTechnicalAssessment {
        var blockers: [RenderTechnicalBlocker] = []

        if snapshot.fileSizeBytes <= 0 {
            blockers.append(.emptyFile)
        }
        if snapshot.durationSeconds <= 0.001 {
            blockers.append(.nonPositiveDuration)
        }
        if snapshot.videoTrackCount <= 0 {
            blockers.append(.missingVideoTrack)
        }
        if snapshot.width <= 0 || snapshot.height <= 0 {
            blockers.append(.invalidDimensions)
        }

        let expectedDuration = max(expectedDurationSeconds, 0)
        if expectedDuration > 0.001 {
            let tolerance = max(0.25, expectedDuration * 0.01)
            if abs(snapshot.durationSeconds - expectedDuration) > tolerance {
                blockers.append(.durationMismatch)
            }
        }

        if let expectedRenderSize {
            let expectedWidth = Int(expectedRenderSize.width.rounded())
            let expectedHeight = Int(expectedRenderSize.height.rounded())
            if snapshot.width != expectedWidth
                || snapshot.height != expectedHeight {
                blockers.append(.dimensionMismatch)
            }
        }

        if let expectedPreset,
           snapshot.width > 0,
           snapshot.height > 0,
           !Self.matchesResolutionClass(
                width: snapshot.width,
                height: snapshot.height,
                preset: expectedPreset
           ) {
            blockers.append(.presetResolutionMismatch)
        }

        return RenderTechnicalAssessment(
            snapshot: snapshot,
            blockers: blockers
        )
    }

    private static func matchesResolutionClass(
        width: Int,
        height: Int,
        preset: LocalRenderPreset
    ) -> Bool {
        let shortEdge = min(width, height)
        let longEdge = max(width, height)
        let isSquare = abs(width - height) <= 2

        switch preset {
        case .hd1080:
            if isSquare {
                return shortEdge >= 1_080
            }
            return shortEdge >= 1_080
                && longEdge >= 1_920
        case .uhd4K:
            if isSquare {
                return shortEdge >= 2_160
            }
            return shortEdge >= 2_160
                && longEdge >= 3_840
        }
    }
}

public enum LocalRenderTechnicalInspectionError: Error, Sendable, Equatable {
    case fileMissing
    case unreadableFileSize
}

public actor LocalRenderTechnicalInspector {
    public init() {}

    public func inspect(
        url: URL,
        expectedDurationSeconds: Double,
        expectedRenderSize: CGSize?,
        expectedPreset: LocalRenderPreset? = nil,
        now: Date = Date()
    ) async throws -> RenderTechnicalAssessment {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw LocalRenderTechnicalInspectionError.fileMissing
        }

        let values = try url.resourceValues(forKeys: [.fileSizeKey])
        guard let fileSize = values.fileSize else {
            throw LocalRenderTechnicalInspectionError.unreadableFileSize
        }

        let asset = AVURLAsset(url: url)
        let duration = try await asset.load(.duration)
        let durationSeconds = max(CMTimeGetSeconds(duration), 0)
        let videoTracks = try await asset.loadTracks(withMediaType: .video)

        var width = 0
        var height = 0
        if let track = videoTracks.first {
            let naturalSize = try await track.load(.naturalSize)
            let preferredTransform = try await track.load(.preferredTransform)
            let transformed = CGRect(
                origin: .zero,
                size: naturalSize
            ).applying(preferredTransform)
            width = Int(abs(transformed.width).rounded())
            height = Int(abs(transformed.height).rounded())
        }

        let snapshot = RenderTechnicalSnapshot(
            fileSizeBytes: Int64(fileSize),
            durationSeconds: durationSeconds,
            videoTrackCount: videoTracks.count,
            width: width,
            height: height,
            inspectedAt: now
        )

        return RenderTechnicalValidator().assess(
            snapshot: snapshot,
            expectedDurationSeconds: expectedDurationSeconds,
            expectedRenderSize: expectedRenderSize,
            expectedPreset: expectedPreset
        )
    }
}
#endif
