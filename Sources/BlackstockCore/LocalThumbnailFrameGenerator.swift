#if os(macOS)
import Foundation
import AVFoundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

public struct GeneratedThumbnailFrame: Sendable, Equatable {
    public let fileURL: URL
    public let sourceTimeSeconds: Double
    public let width: Int
    public let height: Int
    public let createdAt: Date

    public init(
        fileURL: URL,
        sourceTimeSeconds: Double,
        width: Int,
        height: Int,
        createdAt: Date
    ) {
        self.fileURL = fileURL
        self.sourceTimeSeconds = sourceTimeSeconds
        self.width = width
        self.height = height
        self.createdAt = createdAt
    }
}

public enum LocalThumbnailFrameGeneratorError: Error, Sendable, Equatable {
    case invalidDuration
    case invalidOutputDimensions
    case frameUnavailable
    case imageContextUnavailable
    case imageDestinationUnavailable
    case imageWriteFailed
}

public struct LocalThumbnailFrameGenerator: Sendable {
    public init() {}

    public func generate(
        videoURL: URL,
        normalizedPosition: Double,
        outputURL: URL,
        width: Int = 1_280,
        height: Int = 720,
        now: Date = Date()
    ) async throws -> GeneratedThumbnailFrame {
        guard width > 0, height > 0 else {
            throw LocalThumbnailFrameGeneratorError.invalidOutputDimensions
        }

        let asset = AVURLAsset(url: videoURL)
        let duration = try await asset.load(.duration)
        let durationSeconds = CMTimeGetSeconds(duration)
        guard durationSeconds.isFinite, durationSeconds > 0 else {
            throw LocalThumbnailFrameGeneratorError.invalidDuration
        }

        let position = min(max(normalizedPosition, 0.02), 0.98)
        let sourceTimeSeconds = durationSeconds * position
        let time = CMTime(
            seconds: sourceTimeSeconds,
            preferredTimescale: 600
        )

        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = CMTime(
            seconds: 0.1,
            preferredTimescale: 600
        )
        generator.requestedTimeToleranceAfter = CMTime(
            seconds: 0.1,
            preferredTimescale: 600
        )

        let frame: CGImage
        do {
            frame = try await generator.image(at: time).image
        } catch {
            throw LocalThumbnailFrameGeneratorError.frameUnavailable
        }

        guard let cropRect = Self.centerCropRect(
            sourceWidth: frame.width,
            sourceHeight: frame.height,
            targetAspectRatio: Double(width) / Double(height)
        ),
        let cropped = frame.cropping(to: cropRect) else {
            throw LocalThumbnailFrameGeneratorError.frameUnavailable
        }

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw LocalThumbnailFrameGeneratorError.imageContextUnavailable
        }

        context.interpolationQuality = .high
        context.draw(
            cropped,
            in: CGRect(
                x: 0,
                y: 0,
                width: width,
                height: height
            )
        )

        guard let renderedImage = context.makeImage() else {
            throw LocalThumbnailFrameGeneratorError.imageContextUnavailable
        }

        try FileManager.default.createDirectory(
            at: outputURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        if FileManager.default.fileExists(atPath: outputURL.path) {
            try FileManager.default.removeItem(at: outputURL)
        }

        guard let destination = CGImageDestinationCreateWithURL(
            outputURL as CFURL,
            UTType.jpeg.identifier as CFString,
            1,
            nil
        ) else {
            throw LocalThumbnailFrameGeneratorError.imageDestinationUnavailable
        }

        let properties = [
            kCGImageDestinationLossyCompressionQuality: 0.9
        ] as CFDictionary
        CGImageDestinationAddImage(
            destination,
            renderedImage,
            properties
        )

        guard CGImageDestinationFinalize(destination) else {
            throw LocalThumbnailFrameGeneratorError.imageWriteFailed
        }

        return GeneratedThumbnailFrame(
            fileURL: outputURL,
            sourceTimeSeconds: sourceTimeSeconds,
            width: width,
            height: height,
            createdAt: now
        )
    }

    static func centerCropRect(
        sourceWidth: Int,
        sourceHeight: Int,
        targetAspectRatio: Double
    ) -> CGRect? {
        guard sourceWidth > 0,
              sourceHeight > 0,
              targetAspectRatio.isFinite,
              targetAspectRatio > 0 else {
            return nil
        }

        let width = Double(sourceWidth)
        let height = Double(sourceHeight)
        let sourceAspectRatio = width / height

        if sourceAspectRatio > targetAspectRatio {
            let cropWidth = height * targetAspectRatio
            return CGRect(
                x: (width - cropWidth) / 2,
                y: 0,
                width: cropWidth,
                height: height
            ).integral
        }

        let cropHeight = width / targetAspectRatio
        return CGRect(
            x: 0,
            y: (height - cropHeight) / 2,
            width: width,
            height: cropHeight
        ).integral
    }
}
#endif
