#if os(macOS)
import Foundation
@preconcurrency import AVFoundation
import CoreGraphics
import CoreImage
import CoreVideo

public enum LocalSupplementalVideoError:
    Error,
    Sendable,
    Equatable {
    case missingBaseVideoTrack
    case missingSupplementalVideoTrack(UUID)
    case invalidBaseVideoSize
    case noUsableInsert
    case exportSessionUnavailable
    case unsupportedOutputType
    case exportFailed(String)
    case missingOutput
}

private final class SupplementalMuxExportSessionBox:
    @unchecked Sendable {
    let session: AVAssetExportSession
    init(_ session: AVAssetExportSession) {
        self.session = session
    }
}

public actor LocalSupplementalVideoCompositor {
    private struct PreparedInsert {
        let order: Int
        let captureID: UUID
        let generator: AVAssetImageGenerator
        let sourceStartSeconds: Double
        let timelineStartSeconds: Double
        let timelineEndSeconds: Double
    }

    public init() {}

    public func render(
        inputURL: URL,
        supplementalVideo: [SupplementalVideoInsertInput],
        outputURL: URL,
        preset: LocalRenderPreset
    ) async throws {
        let baseAsset = AVURLAsset(url: inputURL)
        let baseTracks = try await baseAsset.loadTracks(
            withMediaType: .video
        )
        guard let baseTrack = baseTracks.first else {
            throw LocalSupplementalVideoError
                .missingBaseVideoTrack
        }

        let baseTimeRange = try await baseTrack.load(
            .timeRange
        )
        let baseDurationSeconds = max(
            CMTimeGetSeconds(baseTimeRange.duration),
            0
        )
        guard baseDurationSeconds >= 0.05 else {
            throw LocalSupplementalVideoError
                .missingBaseVideoTrack
        }

        let naturalSize = try await baseTrack.load(
            .naturalSize
        )
        let preferredTransform = try await baseTrack.load(
            .preferredTransform
        )
        let transformedBounds = CGRect(
            origin: .zero,
            size: naturalSize
        ).applying(preferredTransform)
        let renderSize = CGSize(
            width: abs(transformedBounds.width),
            height: abs(transformedBounds.height)
        )
        guard renderSize.width >= 2,
              renderSize.height >= 2 else {
            throw LocalSupplementalVideoError
                .invalidBaseVideoSize
        }

        var prepared: [PreparedInsert] = []
        for (order, input) in supplementalVideo.enumerated() {
            let asset = AVURLAsset(url: input.fileURL)
            let tracks = try await asset.loadTracks(
                withMediaType: .video
            )
            guard let track = tracks.first else {
                throw LocalSupplementalVideoError
                    .missingSupplementalVideoTrack(
                        input.captureID
                    )
            }

            let sourceRange = try await track.load(
                .timeRange
            )
            let sourceDurationSeconds = max(
                CMTimeGetSeconds(sourceRange.duration),
                0
            )
            let sourceStart = min(
                max(input.sourceStartSeconds, 0),
                sourceDurationSeconds
            )
            let timelineStart = min(
                max(input.timelineStartSeconds, 0),
                baseDurationSeconds
            )
            let duration = min(
                max(input.durationSeconds, 0),
                sourceDurationSeconds - sourceStart,
                baseDurationSeconds - timelineStart
            )
            guard duration >= 0.05 else {
                continue
            }

            let generator = AVAssetImageGenerator(
                asset: asset
            )
            generator.appliesPreferredTrackTransform = true
            generator.requestedTimeToleranceBefore =
                CMTime(seconds: 1.0 / 120.0, preferredTimescale: 600)
            generator.requestedTimeToleranceAfter =
                CMTime(seconds: 1.0 / 120.0, preferredTimescale: 600)

            prepared.append(
                PreparedInsert(
                    order: order,
                    captureID: input.captureID,
                    generator: generator,
                    sourceStartSeconds: sourceStart,
                    timelineStartSeconds: timelineStart,
                    timelineEndSeconds:
                        timelineStart + duration
                )
            )
        }

        guard !prepared.isEmpty else {
            throw LocalSupplementalVideoError
                .noUsableInsert
        }

        let videoOnlyURL = FileManager.default
            .temporaryDirectory
            .appendingPathComponent(
                "blackstock-software-composite-\(UUID().uuidString)"
            )
            .appendingPathExtension("mp4")
        defer {
            try? FileManager.default.removeItem(
                at: videoOnlyURL
            )
        }

        try await renderVideoFrames(
            baseAsset: baseAsset,
            baseTrack: baseTrack,
            baseTimeRange: baseTimeRange,
            basePreferredTransform: preferredTransform,
            renderSize: renderSize,
            prepared: prepared,
            outputURL: videoOnlyURL,
            preset: preset
        )

        try await muxBaseAudio(
            baseAsset: baseAsset,
            videoURL: videoOnlyURL,
            outputURL: outputURL
        )

        guard FileManager.default.fileExists(
            atPath: outputURL.path
        ) else {
            throw LocalSupplementalVideoError
                .missingOutput
        }
    }

    private func renderVideoFrames(
        baseAsset: AVURLAsset,
        baseTrack: AVAssetTrack,
        baseTimeRange: CMTimeRange,
        basePreferredTransform: CGAffineTransform,
        renderSize: CGSize,
        prepared: [PreparedInsert],
        outputURL: URL,
        preset: LocalRenderPreset
    ) async throws {
        if FileManager.default.fileExists(
            atPath: outputURL.path
        ) {
            try FileManager.default.removeItem(
                at: outputURL
            )
        }

        let reader = try AVAssetReader(
            asset: baseAsset
        )
        let readerOutput = AVAssetReaderTrackOutput(
            track: baseTrack,
            outputSettings: [
                kCVPixelBufferPixelFormatTypeKey as String:
                    Int(kCVPixelFormatType_32BGRA)
            ]
        )
        readerOutput.alwaysCopiesSampleData = false
        guard reader.canAdd(readerOutput) else {
            throw LocalSupplementalVideoError
                .exportFailed(
                    "Basisvideo konnte nicht für den Software-Compositor dekodiert werden."
                )
        }
        reader.add(readerOutput)
        reader.timeRange = baseTimeRange

        let writer = try AVAssetWriter(
            outputURL: outputURL,
            fileType: .mp4
        )
        let width = max(
            Int(renderSize.width.rounded()),
            2
        )
        let height = max(
            Int(renderSize.height.rounded()),
            2
        )

        let bitRate: Int
        switch preset {
        case .hd1080:
            bitRate = 12_000_000
        case .uhd4K:
            bitRate = 38_000_000
        }

        let writerInput = AVAssetWriterInput(
            mediaType: .video,
            outputSettings: [
                AVVideoCodecKey:
                    AVVideoCodecType.h264,
                AVVideoWidthKey: width,
                AVVideoHeightKey: height,
                AVVideoCompressionPropertiesKey: [
                    AVVideoAverageBitRateKey:
                        bitRate,
                    AVVideoProfileLevelKey:
                        AVVideoProfileLevelH264HighAutoLevel
                ]
            ]
        )
        writerInput.expectsMediaDataInRealTime = false

        let adaptor =
            AVAssetWriterInputPixelBufferAdaptor(
                assetWriterInput: writerInput,
                sourcePixelBufferAttributes: [
                    kCVPixelBufferPixelFormatTypeKey as String:
                        Int(kCVPixelFormatType_32BGRA),
                    kCVPixelBufferWidthKey as String:
                        width,
                    kCVPixelBufferHeightKey as String:
                        height,
                    kCVPixelBufferIOSurfacePropertiesKey as String:
                        [:]
                ]
            )

        guard writer.canAdd(writerInput) else {
            throw LocalSupplementalVideoError
                .exportFailed(
                    "Videoencoder konnte nicht angelegt werden."
                )
        }
        writer.add(writerInput)

        guard writer.startWriting() else {
            throw LocalSupplementalVideoError
                .exportFailed(
                    writer.error?.localizedDescription
                    ?? "Videoencoder konnte nicht gestartet werden."
                )
        }
        guard reader.startReading() else {
            throw LocalSupplementalVideoError
                .exportFailed(
                    reader.error?.localizedDescription
                    ?? "Videodecoder konnte nicht gestartet werden."
                )
        }
        writer.startSession(atSourceTime: .zero)

        let context = CIContext(
            options: [
                .useSoftwareRenderer: true
            ]
        )
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let outputRect = CGRect(
            origin: .zero,
            size: CGSize(
                width: width,
                height: height
            )
        )

        var appendedFrameCount = 0

        while reader.status == .reading,
              let sample =
                readerOutput.copyNextSampleBuffer() {
            autoreleasepool {
                _ = sample
            }

            guard let imageBuffer =
                    CMSampleBufferGetImageBuffer(
                        sample
                    ) else {
                continue
            }

            let sampleTime =
                CMSampleBufferGetPresentationTimeStamp(
                    sample
                )
            let relativeTime = CMTimeSubtract(
                sampleTime,
                baseTimeRange.start
            )
            let timelineSeconds = max(
                CMTimeGetSeconds(relativeTime),
                0
            )

            let image: CIImage
            if let insert = prepared
                .filter({
                    $0.timelineStartSeconds
                        <= timelineSeconds + 0.000_5
                    && $0.timelineEndSeconds
                        > timelineSeconds + 0.000_5
                })
                .max(by: {
                    $0.order < $1.order
                }) {
                let sourceSeconds =
                    insert.sourceStartSeconds
                    + timelineSeconds
                    - insert.timelineStartSeconds
                do {
                    let cgImage =
                        try insert.generator.copyCGImage(
                            at: CMTime(
                                seconds: sourceSeconds,
                                preferredTimescale: 600
                            ),
                            actualTime: nil
                        )
                    image = Self.aspectFill(
                        CIImage(cgImage: cgImage),
                        into: outputRect
                    )
                } catch {
                    throw LocalSupplementalVideoError
                        .exportFailed(
                            "B-Roll-Frame für \(insert.captureID.uuidString) konnte nicht dekodiert werden: "
                            + error.localizedDescription
                        )
                }
            } else {
                let baseImage = CIImage(
                    cvPixelBuffer: imageBuffer
                )
                image = Self.fitBaseImage(
                    baseImage,
                    preferredTransform:
                        basePreferredTransform,
                    into: outputRect
                )
            }

            while !writerInput.isReadyForMoreMediaData {
                if writer.status == .failed
                    || writer.status == .cancelled {
                    throw LocalSupplementalVideoError
                        .exportFailed(
                            writer.error?
                                .localizedDescription
                            ?? "Software-Videoencoder wurde abgebrochen."
                        )
                }
                try await Task.sleep(
                    nanoseconds: 1_000_000
                )
            }

            let pixelBuffer = try Self.makePixelBuffer(
                adaptor: adaptor,
                width: width,
                height: height
            )
            context.render(
                image,
                to: pixelBuffer,
                bounds: outputRect,
                colorSpace: colorSpace
            )

            guard adaptor.append(
                pixelBuffer,
                withPresentationTime: relativeTime
            ) else {
                throw LocalSupplementalVideoError
                    .exportFailed(
                        writer.error?
                            .localizedDescription
                        ?? "Software-Compositor konnte einen Videoframe nicht schreiben."
                    )
            }
            appendedFrameCount += 1
        }

        if reader.status == .failed {
            throw LocalSupplementalVideoError
                .exportFailed(
                    reader.error?.localizedDescription
                    ?? "Videodekodierung ist fehlgeschlagen."
                )
        }
        guard appendedFrameCount > 0 else {
            throw LocalSupplementalVideoError
                .exportFailed(
                    "Software-Compositor hat keine Videoframes erhalten."
                )
        }

        writerInput.markAsFinished()
        await writer.finishWriting()
        guard writer.status == .completed else {
            throw LocalSupplementalVideoError.exportFailed(
                writer.error?.localizedDescription
                    ?? "Software-Compositor konnte die Videodatei nicht abschließen."
            )
        }
    }

    private func muxBaseAudio(
        baseAsset: AVURLAsset,
        videoURL: URL,
        outputURL: URL
    ) async throws {
        let videoAsset = AVURLAsset(url: videoURL)
        let videoTracks = try await videoAsset.loadTracks(
            withMediaType: .video
        )
        guard let videoTrack = videoTracks.first else {
            throw LocalSupplementalVideoError
                .missingOutput
        }

        let composition = AVMutableComposition()
        guard let compositionVideo =
                composition.addMutableTrack(
                    withMediaType: .video,
                    preferredTrackID:
                        kCMPersistentTrackID_Invalid
                ) else {
            throw LocalSupplementalVideoError
                .exportFailed(
                    "Gerenderte Videospur konnte nicht für das Muxing angelegt werden."
                )
        }
        let videoRange = try await videoTrack.load(
            .timeRange
        )
        try compositionVideo.insertTimeRange(
            videoRange,
            of: videoTrack,
            at: .zero
        )

        let audioTracks = try await baseAsset.loadTracks(
            withMediaType: .audio
        )
        for audioTrack in audioTracks {
            guard let destination =
                    composition.addMutableTrack(
                        withMediaType: .audio,
                        preferredTrackID:
                            kCMPersistentTrackID_Invalid
                    ) else {
                throw LocalSupplementalVideoError
                    .exportFailed(
                        "Hauptton konnte nicht für das Muxing angelegt werden."
                    )
            }
            let range = try await audioTrack.load(
                .timeRange
            )
            let duration = CMTimeMinimum(
                range.duration,
                videoRange.duration
            )
            guard CMTimeCompare(
                duration,
                .zero
            ) > 0 else {
                continue
            }
            try destination.insertTimeRange(
                CMTimeRange(
                    start: range.start,
                    duration: duration
                ),
                of: audioTrack,
                at: .zero
            )
        }

        guard let exporter = AVAssetExportSession(
            asset: composition,
            presetName:
                AVAssetExportPresetPassthrough
        ) else {
            throw LocalSupplementalVideoError
                .exportSessionUnavailable
        }
        guard exporter.supportedFileTypes
            .contains(.mp4) else {
            throw LocalSupplementalVideoError
                .unsupportedOutputType
        }

        if FileManager.default.fileExists(
            atPath: outputURL.path
        ) {
            try FileManager.default.removeItem(
                at: outputURL
            )
        }

        exporter.shouldOptimizeForNetworkUse = true
        do {
            try await AsyncAVAssetExporter.export(
                exporter,
                to: outputURL,
                as: .mp4
            )
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw LocalSupplementalVideoError.exportFailed(
                error.localizedDescription
            )
        }
    }

    private static func makePixelBuffer(
        adaptor: AVAssetWriterInputPixelBufferAdaptor,
        width: Int,
        height: Int
    ) throws -> CVPixelBuffer {
        var buffer: CVPixelBuffer?
        if let pool = adaptor.pixelBufferPool {
            let result = CVPixelBufferPoolCreatePixelBuffer(
                nil,
                pool,
                &buffer
            )
            if result == kCVReturnSuccess,
               let buffer {
                return buffer
            }
        }

        let result = CVPixelBufferCreate(
            nil,
            width,
            height,
            kCVPixelFormatType_32BGRA,
            [
                kCVPixelBufferIOSurfacePropertiesKey:
                    [:]
            ] as CFDictionary,
            &buffer
        )
        guard result == kCVReturnSuccess,
              let buffer else {
            throw LocalSupplementalVideoError
                .exportFailed(
                    "Software-Compositor konnte keinen Ausgabepuffer anlegen."
                )
        }
        return buffer
    }

    private static func fitBaseImage(
        _ image: CIImage,
        preferredTransform: CGAffineTransform,
        into outputRect: CGRect
    ) -> CIImage {
        let transformed = image.transformed(
            by: preferredTransform
        )
        let extent = transformed.extent
        guard extent.width > 0,
              extent.height > 0 else {
            return transformed
        }

        let translated = transformed.transformed(
            by: CGAffineTransform(
                translationX: -extent.minX,
                y: -extent.minY
            )
        )
        let normalizedExtent = translated.extent
        let scaleX =
            outputRect.width
            / normalizedExtent.width
        let scaleY =
            outputRect.height
            / normalizedExtent.height

        return translated
            .transformed(
                by: CGAffineTransform(
                    scaleX: scaleX,
                    y: scaleY
                )
            )
            .cropped(to: outputRect)
    }

    private static func aspectFill(
        _ image: CIImage,
        into outputRect: CGRect
    ) -> CIImage {
        let extent = image.extent
        guard extent.width > 0,
              extent.height > 0 else {
            return image
        }

        let translated = image.transformed(
            by: CGAffineTransform(
                translationX: -extent.minX,
                y: -extent.minY
            )
        )
        let normalizedExtent = translated.extent
        let scale = max(
            outputRect.width
                / normalizedExtent.width,
            outputRect.height
                / normalizedExtent.height
        )
        let scaled = translated.transformed(
            by: CGAffineTransform(
                scaleX: scale,
                y: scale
            )
        )
        let scaledExtent = scaled.extent
        let offsetX =
            (outputRect.width
                - scaledExtent.width) / 2
        let offsetY =
            (outputRect.height
                - scaledExtent.height) / 2

        return scaled
            .transformed(
                by: CGAffineTransform(
                    translationX: offsetX,
                    y: offsetY
                )
            )
            .cropped(to: outputRect)
    }
}
#endif
