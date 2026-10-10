#if os(macOS)
import Foundation
@preconcurrency import AVFoundation

enum AsyncAVAssetExportError: LocalizedError, Sendable {
    case failed(String)
    case unexpectedState

    var errorDescription: String? {
        switch self {
        case .failed(let message): return message
        case .unexpectedState: return "Der Medienexport endete unerwartet."
        }
    }
}

private final class AsyncAVAssetExportBox: @unchecked Sendable {
    let session: AVAssetExportSession

    init(_ session: AVAssetExportSession) {
        self.session = session
    }
}

enum AsyncAVAssetExporter {
    static func export(
        _ session: AVAssetExportSession,
        to outputURL: URL,
        as fileType: AVFileType
    ) async throws {
        let box = AsyncAVAssetExportBox(session)
        try await withTaskCancellationHandler {
            if #available(macOS 15.0, *) {
                try await box.session.export(to: outputURL, as: fileType)
            } else {
                box.session.outputURL = outputURL
                box.session.outputFileType = fileType
                try await legacyExport(box)
            }
        } onCancel: {
            box.session.cancelExport()
        }
    }

    private nonisolated static func legacyExport(
        _ box: AsyncAVAssetExportBox
    ) async throws {
        try await withCheckedThrowingContinuation { continuation in
            box.session.exportAsynchronously {
                switch box.session.status {
                case .completed:
                    continuation.resume()
                case .cancelled:
                    continuation.resume(throwing: CancellationError())
                case .failed:
                    continuation.resume(
                        throwing: AsyncAVAssetExportError.failed(
                            box.session.error?.localizedDescription
                                ?? "Medienexport fehlgeschlagen."
                        )
                    )
                default:
                    continuation.resume(
                        throwing: AsyncAVAssetExportError.unexpectedState
                    )
                }
            }
        }
    }
}
#endif
