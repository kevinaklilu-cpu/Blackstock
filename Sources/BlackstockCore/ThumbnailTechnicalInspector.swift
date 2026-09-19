#if os(macOS)
import Foundation
import ImageIO
import UniformTypeIdentifiers

public struct ThumbnailTechnicalSnapshot: Codable, Sendable, Equatable {
    public let width: Int
    public let height: Int
    public let fileSizeBytes: Int64
    public let mimeType: String
    public let inspectedAt: Date

    public init(
        width: Int,
        height: Int,
        fileSizeBytes: Int64,
        mimeType: String,
        inspectedAt: Date
    ) {
        self.width = max(0, width)
        self.height = max(0, height)
        self.fileSizeBytes = max(0, fileSizeBytes)
        self.mimeType = mimeType
        self.inspectedAt = inspectedAt
    }

    public var aspectRatio: Double? {
        guard height > 0 else { return nil }
        return Double(width) / Double(height)
    }
}

public enum ThumbnailUploadBlocker: String, Codable, Sendable, Equatable {
    case unsupportedMimeType = "UNSUPPORTED_MIME_TYPE"
    case exceedsFiftyMB = "EXCEEDS_FIFTY_MB"
    case invalidDimensions = "INVALID_DIMENSIONS"
}

public enum ThumbnailBestPracticeFinding: String, Codable, Sendable, Equatable {
    case belowRecommendedMinimumWidth = "BELOW_RECOMMENDED_MINIMUM_WIDTH"
    case notSixteenByNine = "NOT_SIXTEEN_BY_NINE"
}

public struct ThumbnailTechnicalAssessment: Codable, Sendable, Equatable {
    public let snapshot: ThumbnailTechnicalSnapshot
    public let uploadBlockers: [ThumbnailUploadBlocker]
    public let bestPracticeFindings: [ThumbnailBestPracticeFinding]

    public init(
        snapshot: ThumbnailTechnicalSnapshot,
        uploadBlockers: [ThumbnailUploadBlocker],
        bestPracticeFindings: [ThumbnailBestPracticeFinding]
    ) {
        self.snapshot = snapshot
        self.uploadBlockers = uploadBlockers
        self.bestPracticeFindings = bestPracticeFindings
    }

    public var uploadCompatible: Bool {
        uploadBlockers.isEmpty
    }

    public static func evaluate(
        _ snapshot: ThumbnailTechnicalSnapshot
    ) -> ThumbnailTechnicalAssessment {
        var blockers: [ThumbnailUploadBlocker] = []
        var bestPractice: [ThumbnailBestPracticeFinding] = []

        if !["image/jpeg", "image/png", "application/octet-stream"].contains(
            snapshot.mimeType
        ) {
            blockers.append(.unsupportedMimeType)
        }

        if snapshot.fileSizeBytes > 50 * 1_024 * 1_024 {
            blockers.append(.exceedsFiftyMB)
        }

        if snapshot.width <= 0 || snapshot.height <= 0 {
            blockers.append(.invalidDimensions)
        } else {
            if snapshot.width < 640 {
                bestPractice.append(.belowRecommendedMinimumWidth)
            }

            if let ratio = snapshot.aspectRatio,
               abs(ratio - (16.0 / 9.0)) > 0.03 {
                bestPractice.append(.notSixteenByNine)
            }
        }

        return .init(
            snapshot: snapshot,
            uploadBlockers: blockers,
            bestPracticeFindings: bestPractice
        )
    }
}

public enum ThumbnailTechnicalInspectorError: Error, Sendable, Equatable {
    case unreadableFile
    case unreadableImage
    case unsupportedType
}

public struct ThumbnailTechnicalInspector: Sendable {
    public init() {}

    public func inspect(
        url: URL,
        now: Date = Date()
    ) throws -> ThumbnailTechnicalAssessment {
        let values = try url.resourceValues(
            forKeys: [.fileSizeKey, .contentTypeKey]
        )
        guard let size = values.fileSize else {
            throw ThumbnailTechnicalInspectorError.unreadableFile
        }

        guard let source = CGImageSourceCreateWithURL(
            url as CFURL,
            nil
        ) else {
            throw ThumbnailTechnicalInspectorError.unreadableImage
        }

        guard let properties = CGImageSourceCopyPropertiesAtIndex(
            source,
            0,
            nil
        ) as? [CFString: Any],
        let width = properties[kCGImagePropertyPixelWidth] as? Int,
        let height = properties[kCGImagePropertyPixelHeight] as? Int else {
            throw ThumbnailTechnicalInspectorError.unreadableImage
        }

        let mime = Self.mimeType(
            contentType: values.contentType,
            url: url
        )

        return .evaluate(
            .init(
                width: width,
                height: height,
                fileSizeBytes: Int64(size),
                mimeType: mime,
                inspectedAt: now
            )
        )
    }

    private static func mimeType(
        contentType: UTType?,
        url: URL
    ) -> String {
        if contentType?.conforms(to: .jpeg) == true {
            return "image/jpeg"
        }
        if contentType?.conforms(to: .png) == true {
            return "image/png"
        }

        switch url.pathExtension.lowercased() {
        case "jpg", "jpeg":
            return "image/jpeg"
        case "png":
            return "image/png"
        default:
            return contentType?.preferredMIMEType
                ?? "application/octet-stream"
        }
    }
}
#endif
