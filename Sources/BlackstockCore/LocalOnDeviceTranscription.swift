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
    public let editedByUser: Bool?
    public let editedAt: Date?

    public init(
        id: UUID = UUID(),
        startSeconds: Double,
        durationSeconds: Double,
        text: String,
        confidence: Float,
        editedByUser: Bool? = nil,
        editedAt: Date? = nil
    ) {
        self.id = id
        self.startSeconds = startSeconds
        self.durationSeconds = durationSeconds
        self.text = text
        self.confidence = confidence
        self.editedByUser = editedByUser
        self.editedAt = editedAt
    }

    public var wasEditedByUser: Bool {
        editedByUser == true
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

extension LocalTranscriptionError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .authorizationDenied:
            return "Die Spracherkennung wurde nicht erlaubt."
        case .authorizationRestricted:
            return "Die Spracherkennung ist auf diesem Mac eingeschränkt."
        case .recognizerUnavailable:
            return "Die lokale Spracherkennung ist momentan nicht verfügbar."
        case .onDeviceRecognitionUnsupported:
            return "Für diese Sprache ist keine lokale Spracherkennung verfügbar."
        case .audioExtractionUnavailable:
            return "Die Tonspur konnte nicht für die Spracherkennung vorbereitet werden."
        case .audioExtractionFailed(let message), .recognitionFailed(let message):
            return message
        case .emptyTranscript:
            return "In diesem Ausschnitt wurde keine Sprache erkannt."
        }
    }
}

private final class SpeechExportSessionBox: @unchecked Sendable {
    let session: AVAssetExportSession
    init(_ session: AVAssetExportSession) {
        self.session = session
    }
}

private struct SpeechRecognitionResultBox: @unchecked Sendable {
    let value: SFSpeechRecognitionResult
}

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
        let status = await Self.authorizationStatus { callback in
            SFSpeechRecognizer.requestAuthorization(callback)
        }
        return Self.map(status)
    }

    static func authorizationStatus(
        using request: @escaping (
            @escaping @Sendable (SFSpeechRecognizerAuthorizationStatus) -> Void
        ) -> Void
    ) async -> SFSpeechRecognizerAuthorizationStatus {
        await withCheckedContinuation { continuation in
            request { status in
                continuation.resume(returning: status)
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

        let result = try await recognize(recognizer: recognizer, request: request)
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

        do {
            try await AsyncAVAssetExporter.export(
                exporter,
                to: destination,
                as: .m4a
            )
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw LocalTranscriptionError.audioExtractionFailed(
                error.localizedDescription
            )
        }

        return destination
    }

    private func recognize(
        recognizer: SFSpeechRecognizer,
        request: SFSpeechURLRecognitionRequest
    ) async throws -> SFSpeechRecognitionResult {
        let state = SpeechRecognitionState()
        let box: SpeechRecognitionResultBox = try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                state.install(continuation)
                let task = recognizer.recognitionTask(with: request) { result, error in
                    if let error {
                        state.fail(
                            LocalTranscriptionError.recognitionFailed(
                                Self.recognitionFailureMessage(error)
                            )
                        )
                    } else if let result, result.isFinal {
                        state.succeed(result)
                    }
                }
                state.install(task)
            }
        } onCancel: {
            state.cancel()
        }
        return box.value
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

    static func recognitionFailureMessage(_ error: Error) -> String {
        let original = error.localizedDescription
        let normalized = original.lowercased()
        if normalized.contains("siri")
            && normalized.contains("dictation")
            && normalized.contains("disabled") {
            return "Die lokale Spracherkennung ist in macOS deaktiviert. Aktiviere unter Systemeinstellungen → Tastatur die Diktierfunktion und versuche es danach erneut."
        }
        if normalized.contains("not authorized")
            || normalized.contains("permission") {
            return "Blackstock besitzt keine Freigabe für die Spracherkennung. Erlaube sie unter Systemeinstellungen → Datenschutz & Sicherheit → Spracherkennung."
        }
        return original
    }
}

private final class SpeechRecognitionState: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<SpeechRecognitionResultBox, Error>?
    private var task: SFSpeechRecognitionTask?
    private var completion: Result<SpeechRecognitionResultBox, Error>?
    private var finished = false

    func install(_ continuation: CheckedContinuation<SpeechRecognitionResultBox, Error>) {
        lock.lock()
        if let completion {
            lock.unlock()
            continuation.resume(with: completion)
            return
        }
        self.continuation = continuation
        lock.unlock()
    }

    func install(_ task: SFSpeechRecognitionTask) {
        lock.lock()
        self.task = task
        let shouldCancel = finished
        lock.unlock()
        if shouldCancel { task.cancel() }
    }

    func succeed(_ result: SFSpeechRecognitionResult) {
        finish(.success(SpeechRecognitionResultBox(value: result)), cancelTask: false)
    }

    func fail(_ error: Error) {
        finish(.failure(error), cancelTask: true)
    }

    func cancel() {
        finish(.failure(CancellationError()), cancelTask: true)
    }

    private func finish(
        _ result: Result<SpeechRecognitionResultBox, Error>,
        cancelTask: Bool
    ) {
        lock.lock()
        guard !finished else {
            lock.unlock()
            return
        }
        finished = true
        completion = result
        let continuation = self.continuation
        self.continuation = nil
        let task = self.task
        lock.unlock()

        if cancelTask { task?.cancel() } else { task?.finish() }
        continuation?.resume(with: result)
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
