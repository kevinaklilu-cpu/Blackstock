#if os(macOS)
import Foundation
@preconcurrency import AVFoundation
@preconcurrency import Vision

public enum VisionFocalObservationKind: String, Codable, Sendable {
    case face = "FACE"
    case human = "HUMAN"
}

public struct VisionFocalObservation: Codable, Sendable, Equatable {
    public let normalizedX: Double
    public let normalizedYFromTop: Double
    public let weight: Double
    public let kind: VisionFocalObservationKind

    public init(
        normalizedX: Double,
        normalizedYFromTop: Double,
        weight: Double,
        kind: VisionFocalObservationKind
    ) {
        self.normalizedX = min(max(normalizedX, 0), 1)
        self.normalizedYFromTop = min(max(normalizedYFromTop, 0), 1)
        self.weight = max(weight, 0.0001)
        self.kind = kind
    }
}

public struct VisionFocalPointProposal: Codable, Sendable, Equatable {
    public let focalX: Double
    public let focalY: Double
    public let observationCount: Int
    public let faceObservationCount: Int
    public let humanObservationCount: Int
    public let sampledFrameCount: Int
    public let createdAt: Date

    public init(
        focalX: Double,
        focalY: Double,
        observationCount: Int,
        faceObservationCount: Int,
        humanObservationCount: Int,
        sampledFrameCount: Int,
        createdAt: Date
    ) {
        self.focalX = min(max(focalX, 0), 1)
        self.focalY = min(max(focalY, 0), 1)
        self.observationCount = max(observationCount, 0)
        self.faceObservationCount = max(faceObservationCount, 0)
        self.humanObservationCount = max(humanObservationCount, 0)
        self.sampledFrameCount = max(sampledFrameCount, 0)
        self.createdAt = createdAt
    }

    public var explanation: String {
        if faceObservationCount > 0 && humanObservationCount > 0 {
            return "Lokaler Vision-Vorschlag aus Gesicht- und Personenerkennung."
        }
        if faceObservationCount > 0 {
            return "Lokaler Vision-Vorschlag aus Gesichtserkennung."
        }
        return "Lokaler Vision-Vorschlag aus Personenerkennung."
    }
}

public enum LocalVisionFocalPointError: Error, Sendable, Equatable {
    case invalidDuration
    case noRelevantObservation
}

public struct LocalVisionFocalPointSuggester: Sendable {
    public init() {}

    public func suggest(
        url: URL,
        sampleCount: Int = 7,
        now: Date = Date()
    ) async throws -> VisionFocalPointProposal {
        let asset = AVURLAsset(url: url)
        let duration = try await asset.load(.duration)
        let seconds = CMTimeGetSeconds(duration)
        guard seconds.isFinite, seconds > 0 else {
            throw LocalVisionFocalPointError.invalidDuration
        }

        let count = min(max(sampleCount, 3), 15)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 1280, height: 1280)
        generator.requestedTimeToleranceBefore = CMTime(
            seconds: 0.25,
            preferredTimescale: 600
        )
        generator.requestedTimeToleranceAfter = CMTime(
            seconds: 0.25,
            preferredTimescale: 600
        )

        var observations: [VisionFocalObservation] = []
        var sampledFrames = 0

        for index in 0..<count {
            let fraction = Double(index + 1) / Double(count + 1)
            let time = CMTime(
                seconds: seconds * fraction,
                preferredTimescale: 600
            )

            guard let frame = try? await generator.image(at: time).image else {
                continue
            }
            sampledFrames += 1

            if let face = Self.largestFace(in: frame) {
                observations.append(face)
                continue
            }

            if let human = Self.largestHuman(in: frame) {
                observations.append(human)
            }
        }

        guard let proposal = Self.aggregate(
            observations,
            sampledFrameCount: sampledFrames,
            now: now
        ) else {
            throw LocalVisionFocalPointError.noRelevantObservation
        }
        return proposal
    }

    public static func aggregate(
        _ observations: [VisionFocalObservation],
        sampledFrameCount: Int,
        now: Date
    ) -> VisionFocalPointProposal? {
        guard !observations.isEmpty else { return nil }

        let totalWeight = observations.reduce(0) { $0 + $1.weight }
        guard totalWeight > 0 else { return nil }

        let x = observations.reduce(0) {
            $0 + ($1.normalizedX * $1.weight)
        } / totalWeight
        let y = observations.reduce(0) {
            $0 + ($1.normalizedYFromTop * $1.weight)
        } / totalWeight

        return .init(
            focalX: x,
            focalY: y,
            observationCount: observations.count,
            faceObservationCount: observations.filter {
                $0.kind == .face
            }.count,
            humanObservationCount: observations.filter {
                $0.kind == .human
            }.count,
            sampledFrameCount: sampledFrameCount,
            createdAt: now
        )
    }

    private static func largestFace(
        in image: CGImage
    ) -> VisionFocalObservation? {
        let request = VNDetectFaceRectanglesRequest()
        let handler = VNImageRequestHandler(cgImage: image)
        do {
            try handler.perform([request])
        } catch {
            return nil
        }

        guard let observation = request.results?
            .max(by: {
                $0.boundingBox.width * $0.boundingBox.height
                < $1.boundingBox.width * $1.boundingBox.height
            }) else {
            return nil
        }

        return focalObservation(
            boundingBox: observation.boundingBox,
            confidence: Double(observation.confidence),
            kind: .face
        )
    }

    private static func largestHuman(
        in image: CGImage
    ) -> VisionFocalObservation? {
        let request = VNDetectHumanRectanglesRequest()
        request.upperBodyOnly = false
        let handler = VNImageRequestHandler(cgImage: image)
        do {
            try handler.perform([request])
        } catch {
            return nil
        }

        guard let observation = request.results?
            .max(by: {
                $0.boundingBox.width * $0.boundingBox.height
                < $1.boundingBox.width * $1.boundingBox.height
            }) else {
            return nil
        }

        return focalObservation(
            boundingBox: observation.boundingBox,
            confidence: Double(observation.confidence),
            kind: .human
        )
    }

    private static func focalObservation(
        boundingBox: CGRect,
        confidence: Double,
        kind: VisionFocalObservationKind
    ) -> VisionFocalObservation {
        let centerX = boundingBox.midX
        let centerYFromTop = 1 - boundingBox.midY
        let area = max(
            Double(boundingBox.width * boundingBox.height),
            0.0001
        )
        return .init(
            normalizedX: centerX,
            normalizedYFromTop: centerYFromTop,
            weight: max(confidence, 0.1) * area,
            kind: kind
        )
    }
}
#endif
