#if os(macOS)
import AVFoundation
import Combine
import Foundation

@MainActor
final class MicrophoneCaptureRecorder: ObservableObject {
    @Published private(set) var isPreparing = false
    @Published private(set) var isRecording = false
    @Published private(set) var completedRecordingURL: URL?
    @Published private(set) var errorMessage: String?

    private var recorder: AVAudioRecorder?

    func startRecording() async {
        guard !isPreparing, !isRecording else { return }

        completedRecordingURL = nil
        errorMessage = nil

        guard AVCaptureDevice.authorizationStatus(for: .audio)
                == .authorized else {
            errorMessage =
                "Der Mikrofonzugriff ist nicht freigegeben."
            return
        }

        isPreparing = true
        defer { isPreparing = false }

        do {
            let outputURL = FileManager.default.temporaryDirectory
                .appendingPathComponent(
                    "Blackstock-Microphone-\(UUID().uuidString)"
                )
                .appendingPathExtension("m4a")
            try? FileManager.default.removeItem(at: outputURL)

            let settings: [String: Any] = [
                AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
                AVSampleRateKey: 48_000,
                AVNumberOfChannelsKey: 1,
                AVEncoderAudioQualityKey:
                    AVAudioQuality.high.rawValue
            ]

            let recorder = try AVAudioRecorder(
                url: outputURL,
                settings: settings
            )
            recorder.isMeteringEnabled = true

            guard recorder.prepareToRecord() else {
                throw MicrophoneCaptureError.prepareFailed
            }
            guard recorder.record() else {
                throw MicrophoneCaptureError.startFailed
            }

            self.recorder = recorder
            isRecording = true
        } catch {
            recorder = nil
            errorMessage =
                "Mikrofonaufnahme konnte nicht gestartet werden: "
                + error.localizedDescription
        }
    }

    func stopRecording() {
        guard let recorder, recorder.isRecording else {
            return
        }

        let outputURL = recorder.url
        recorder.stop()
        self.recorder = nil
        isRecording = false

        guard FileManager.default.fileExists(
            atPath: outputURL.path
        ) else {
            errorMessage =
                "Mikrofonaufnahme wurde beendet, aber die Datei fehlt."
            return
        }

        completedRecordingURL = outputURL
    }
}

private enum MicrophoneCaptureError:
    Error,
    LocalizedError {
    case prepareFailed
    case startFailed

    var errorDescription: String? {
        switch self {
        case .prepareFailed:
            return "Die lokale Audiodatei konnte nicht vorbereitet werden."
        case .startFailed:
            return "Das aktive Mikrofon konnte nicht gestartet werden."
        }
    }
}
#endif
