#if os(macOS)
import Foundation
@preconcurrency import AVFoundation
@preconcurrency import Speech

public enum LocalSpeechAuthorizationState: String, Codable, Sendable {
    case notDetermined = "NOT_DETERMINED"
    case denied = "DENIED"
    case restricted = "RESTRICTED"
    case authorized = "AUTHORIZED"
}

public struct TranscriptSegment: Codable, Sendable, Equatable, Identifiable {
    public let id: UUID
    public let startSeconds: Double
    public let durationSeconds: Double
    public let text: String
    public let confidence: Float

    public init(
        id: UUID = UUID(),
        startSeconds: Double,
        durationSeconds: Double,
        text: String,
        confidence: Float
    ) {
        self.id = id
        self.startSeconds = startSeconds
        self.durationSeconds = durationSeconds
        self.text = text
        self.confidence = confidence
    }
}

public struct LocalTranscript: Codable, Sendable, Equatable {
    public let localeIdentifier: String
    public let text: String
    public let segments: [TranscriptSegment]
    public let onDevice: Bool
    public let createdAt: Date

    public init(
        localeIdentifier: String,
        text: String,
        segments: [TranscriptSegment],
        onDevice: Bool,
        createdAt: Date
    ) {
        self.localeIdentifier = localeIdentifier
        self.text = text
        self.segments = segments
        self.onDevice = onDevice
        self.createdAt = createdAt
    }
}

public enum LocalTranscriptionError: Error, Sendable, Equatable {
    case authorizationDenied
    case authorizationRestricted
    case recognizerUnavailable
    case onDeviceRecognitionUnsupported
    case audioExtractionUnavailable
    case audioExtractionFailed(String)
    case recognitionFailed(String)
    case emptyTranscript
}

private final class SpeechExportSessionBox: @unchecked Sendable {
    let session: AVAssetExportSession
    init(_ session: AVAssetExportSession) {
        self.session = session
    }
}

@MainActor
public final class LocalOnDeviceTranscriber {
    public init() {}

    public func authorizationState() -> LocalSpeechAuthorizationState {
        switch SFSpeechRecognizer.authorizationStatus() {
        case .notDetermined:
            return .notDetermined
        case .denied:
            return .denied
        case .restricted:
            return .restricted
        case .authorized:
            return .authorized
        @unknown default:
            return .restricted
        }
    }

    public func requestAuthorization() async -> LocalSpeechAuthorizationState {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: Self.map(status))
            }
        }
    }

    public func isOnDeviceAvailable(localeIdentifier: String) -> Bool {
        guard let recognizer = SFSpeechRecognizer(
            locale: Locale(identifier: localeIdentifier)
        ) else {
            return false
        }
        return recognizer.isAvailable && recognizer.supportsOnDeviceRecognition
    }

    public func transcribeVideo(
        url: URL,
        localeIdentifier: String,
        contextualTerms: [String] = []
    ) async throws -> LocalTranscript {
        switch authorizationState() {
        case .notDetermined, .denied:
            throw LocalTranscriptionError.authorizationDenied
        case .restricted:
            throw LocalTranscriptionError.authorizationRestricted
        case .authorized:
            break
        }

        guard let recognizer = SFSpeechRecognizer(
            locale: Locale(identifier: localeIdentifier)
        ), recognizer.isAvailable else {
            throw LocalTranscriptionError.recognizerUnavailable
        }
        guard recognizer.supportsOnDeviceRecognition else {
            throw LocalTranscriptionError.onDeviceRecognitionUnsupported
        }

        let audioURL = try await extractAudio(from: url)
        defer { try? FileManager.default.removeItem(at: audioURL) }

        let request = SFSpeechURLRecognitionRequest(url: audioURL)
        request.requiresOnDeviceRecognition = true
        request.shouldReportPartialResults = false
        request.taskHint = .dictation
        request.contextualStrings = Array(contextualTerms.prefix(100))
        if #available(macOS 13.0, *) {
            request.addsPunctuation = true
        }

        let result = try await recognize(
            recognizer: recognizer,
            request: request
        )
        let transcription = result.bestTranscription
        let text = transcription.formattedString
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            throw LocalTranscriptionError.emptyTranscript
        }

        let segments = transcription.segments.map {
            TranscriptSegment(
                startSeconds: $0.timestamp,
                durationSeconds: $0.duration,
                text: $0.substring,
                confidence: $0.confidence
            )
        }

        return LocalTranscript(
            localeIdentifier: localeIdentifier,
            text: text,
            segments: segments,
            onDevice: true,
            createdAt: Date()
        )
    }

    private func extractAudio(from videoURL: URL) async throws -> URL {
        let asset = AVURLAsset(url: videoURL)
        guard let exporter = AVAssetExportSession(
            asset: asset,
            presetName: AVAssetExportPresetAppleM4A
        ) else {
            throw LocalTranscriptionError.audioExtractionUnavailable
        }

        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent("blackstock-speech-\(UUID().uuidString)")
            .appendingPathExtension("m4a")

        exporter.outputURL = destination
        exporter.outputFileType = .m4a

        let box = SpeechExportSessionBox(exporter)
        try await withCheckedThrowingContinuation { continuation in
            box.session.exportAsynchronously {
                let session = box.session
                switch session.status {
                case .completed:
                    continuation.resume()
                case .failed, .cancelled:
                    continuation.resume(
                        throwing: LocalTranscriptionError.audioExtractionFailed(
                            session.error?.localizedDescription
                            ?? "Audio-Extraktion fehlgeschlagen."
                        )
                    )
                default:
                    continuation.resume(
                        throwing: LocalTranscriptionError.audioExtractionFailed(
                            "Audio-Extraktion endete im Zustand \(session.status.rawValue)."
                        )
                    )
                }
            }
        }

        return destination
    }

    private func recognize(
        recognizer: SFSpeechRecognizer,
        request: SFSpeechURLRecognitionRequest
    ) async throws -> SFSpeechRecognitionResult {
        try await withCheckedThrowingContinuation { continuation in
            var completed = false
            var task: SFSpeechRecognitionTask?
            task = recognizer.recognitionTask(with: request) { result, error in
                guard !completed else { return }

                if let error {
                    completed = true
                    task?.cancel()
                    continuation.resume(
                        throwing: LocalTranscriptionError.recognitionFailed(
                            error.localizedDescription
                        )
                    )
                    return
                }

                if let result, result.isFinal {
                    completed = true
                    task?.finish()
                    continuation.resume(returning: result)
                }
            }
        }
    }

    private static func map(
        _ status: SFSpeechRecognizerAuthorizationStatus
    ) -> LocalSpeechAuthorizationState {
        switch status {
        case .notDetermined: return .notDetermined
        case .denied: return .denied
        case .restricted: return .restricted
        case .authorized: return .authorized
        @unknown default: return .restricted
        }
    }
}

public struct WebVTTCaptionWriter: Sendable {
    public init() {}

    public func contents(for transcript: LocalTranscript) -> String {
        var lines = ["WEBVTT", ""]
        for segment in transcript.segments where !segment.text.isEmpty {
            let start = Self.timestamp(segment.startSeconds)
            let end = Self.timestamp(
                segment.startSeconds + max(segment.durationSeconds, 0.05)
            )
            lines.append("\(start) --> \(end)")
            lines.append(segment.text)
            lines.append("")
        }
        return lines.joined(separator: "\n")
    }

    public func write(
        transcript: LocalTranscript,
        to url: URL
    ) throws {
        try contents(for: transcript).write(
            to: url,
            atomically: true,
            encoding: .utf8
        )
    }

    static func timestamp(_ seconds: Double) -> String {
        let safe = max(seconds, 0)
        let totalMilliseconds = Int((safe * 1_000).rounded())
        let hours = totalMilliseconds / 3_600_000
        let minutes = (totalMilliseconds % 3_600_000) / 60_000
        let secs = (totalMilliseconds % 60_000) / 1_000
        let millis = totalMilliseconds % 1_000
        return String(
            format: "%02d:%02d:%02d.%03d",
            hours,
            minutes,
            secs,
            millis
        )
    }
}
#endif
