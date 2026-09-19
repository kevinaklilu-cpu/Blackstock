#if os(macOS)
import Foundation
@preconcurrency import AVFoundation
import CryptoKit

public enum LocalRenderPreset: String, Codable, Sendable, CaseIterable, Hashable {
    case hd1080
    case uhd4K

    var avPresetName: String {
        switch self {
        case .hd1080: return AVAssetExportPreset1920x1080
        case .uhd4K: return AVAssetExportPreset3840x2160
        }
    }
}

public enum LocalRenderError: Error, Sendable, Equatable {
    case unauthorizedMedia
    case unsupportedEditOperation(EditOperationType)
    case exportSessionUnavailable
    case unsupportedOutputType
    case missingVideoTrack
    case reframePlanUnavailable
    case exportFailed(String)
    case missingOutput
}

private final class ExportSessionBox: @unchecked Sendable {
    let session: AVAssetExportSession
    init(_ session: AVAssetExportSession) { self.session = session }
}

public actor LocalVideoRenderer {
    public init() {}

    public func render(
        projectID: UUID,
        asset: ProductionMediaAsset,
        graph: EditGraph,
        outputURL: URL,
        preset: LocalRenderPreset
    ) async throws -> RenderArtifact {
        guard asset.mayEnterProduction else {
            throw LocalRenderError.unauthorizedMedia
        }

        let unsupported = graph.currentOperations.first {
            ![EditOperationType.trim, EditOperationType.reframe].contains($0.type)
        }
        if let unsupported {
            throw LocalRenderError.unsupportedEditOperation(unsupported.type)
        }

        let source = AVURLAsset(url: asset.sourceURL)
        let composition = AVMutableComposition()

        let trim = graph.currentOperations.last(where: { $0.type == .trim })?.timeRange
        let range: CMTimeRange
        if let trim {
            range = CMTimeRange(
                start: CMTime(seconds: trim.startSeconds, preferredTimescale: 600),
                duration: CMTime(seconds: trim.durationSeconds, preferredTimescale: 600)
            )
        } else {
            let duration = try await source.load(.duration)
            range = CMTimeRange(start: .zero, duration: duration)
        }

        try await composition.insertTimeRange(range, of: source, at: .zero)

        guard let exporter = AVAssetExportSession(
            asset: composition,
            presetName: preset.avPresetName
        ) else {
            throw LocalRenderError.exportSessionUnavailable
        }

        if let reframe = graph.currentOperations
            .last(where: { $0.type == .reframe })?
            .reframeSpec {
            let sourceTracks = try await source.loadTracks(withMediaType: .video)
            let compositionTracks = try await composition.loadTracks(withMediaType: .video)
            guard let sourceTrack = sourceTracks.first,
                  let compositionTrack = compositionTracks.first else {
                throw LocalRenderError.missingVideoTrack
            }

            let naturalSize = try await sourceTrack.load(.naturalSize)
            let preferredTransform = try await sourceTrack.load(.preferredTransform)
            let renderSize = preset.renderSize(for: reframe.aspectRatio)

            guard let plan = ReframeTransformPlan.make(
                naturalSize: naturalSize,
                preferredTransform: preferredTransform,
                spec: reframe,
                renderSize: renderSize
            ) else {
                throw LocalRenderError.reframePlanUnavailable
            }

            let duration = try await composition.load(.duration)
            let instruction = AVMutableVideoCompositionInstruction()
            instruction.timeRange = CMTimeRange(start: .zero, duration: duration)

            let layer = AVMutableVideoCompositionLayerInstruction(
                assetTrack: compositionTrack
            )
            layer.setTransform(plan.transform, at: .zero)
            instruction.layerInstructions = [layer]

            let videoComposition = AVMutableVideoComposition()
            videoComposition.instructions = [instruction]
            videoComposition.renderSize = CGSize(
                width: plan.renderWidth,
                height: plan.renderHeight
            )
            videoComposition.frameDuration = CMTime(value: 1, timescale: 30)
            exporter.videoComposition = videoComposition
        }

        let supported = exporter.supportedFileTypes
        guard supported.contains(.mp4) else {
            throw LocalRenderError.unsupportedOutputType
        }

        if FileManager.default.fileExists(atPath: outputURL.path) {
            try FileManager.default.removeItem(at: outputURL)
        }

        exporter.outputURL = outputURL
        exporter.outputFileType = .mp4
        exporter.shouldOptimizeForNetworkUse = true

        let exportBox = ExportSessionBox(exporter)
        try await withCheckedThrowingContinuation { continuation in
            exportBox.session.exportAsynchronously {
                let session = exportBox.session
                switch session.status {
                case .completed:
                    continuation.resume()
                case .failed, .cancelled:
                    continuation.resume(
                        throwing: LocalRenderError.exportFailed(
                            session.error?.localizedDescription ?? "Unbekannter Exportfehler"
                        )
                    )
                default:
                    continuation.resume(
                        throwing: LocalRenderError.exportFailed(
                            "Export endete im Zustand \(session.status.rawValue)."
                        )
                    )
                }
            }
        }

        guard FileManager.default.fileExists(atPath: outputURL.path) else {
            throw LocalRenderError.missingOutput
        }

        let data = try Data(contentsOf: outputURL)
        let digest = SHA256.hash(data: data)
        let sha256 = digest.map { String(format: "%02x", $0) }.joined()

        return RenderArtifact(
            projectID: projectID,
            fileURL: outputURL,
            sha256: sha256,
            mimeType: "video/mp4",
            validated: !data.isEmpty,
            createdAt: Date()
        )
    }
}
#endif
