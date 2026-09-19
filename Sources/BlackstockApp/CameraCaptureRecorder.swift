#if os(macOS)
import AVFoundation
import Combine
import Foundation

@MainActor
final class CameraCaptureRecorder: NSObject, ObservableObject {
    @Published private(set) var isPreparing = false
    @Published private(set) var isRecording = false
    @Published private(set) var completedRecordingURL: URL?
    @Published private(set) var errorMessage: String?

    private let session = AVCaptureSession()
    private let movieOutput = AVCaptureMovieFileOutput()
    private var configured = false
    private var configuredWithMicrophone = false

    func startRecording() async {
        guard !isPreparing, !isRecording else { return }

        completedRecordingURL = nil
        errorMessage = nil
        isPreparing = true
        defer { isPreparing = false }

        do {
            try configureIfNeeded()

            let outputURL = FileManager.default.temporaryDirectory
                .appendingPathComponent(
                    "Blackstock-Camera-\(UUID().uuidString)"
                )
                .appendingPathExtension("mov")
            try? FileManager.default.removeItem(at: outputURL)

            if !session.isRunning {
                session.startRunning()
            }

            movieOutput.startRecording(
                to: outputURL,
                recordingDelegate: self
            )
        } catch {
            if session.isRunning {
                session.stopRunning()
            }
            errorMessage = "Kameraaufnahme konnte nicht gestartet werden: \(error.localizedDescription)"
        }
    }

    func stopRecording() {
        guard movieOutput.isRecording else { return }
        movieOutput.stopRecording()
    }

    func discardCompletedRecording() {
        if let completedRecordingURL {
            try? FileManager.default.removeItem(
                at: completedRecordingURL
            )
        }
        completedRecordingURL = nil
    }

    private func configureIfNeeded() throws {
        let microphoneAuthorized =
            AVCaptureDevice.authorizationStatus(for: .audio)
                == .authorized

        if configured,
           configuredWithMicrophone == microphoneAuthorized {
            return
        }

        guard AVCaptureDevice.authorizationStatus(for: .video)
                == .authorized else {
            throw CameraCaptureError.cameraNotAuthorized
        }
        guard let camera = AVCaptureDevice.default(for: .video) else {
            throw CameraCaptureError.cameraUnavailable
        }

        session.beginConfiguration()
        defer { session.commitConfiguration() }
        session.sessionPreset = .high

        for input in session.inputs {
            session.removeInput(input)
        }
        for output in session.outputs {
            session.removeOutput(output)
        }

        let cameraInput = try AVCaptureDeviceInput(device: camera)
        guard session.canAddInput(cameraInput) else {
            throw CameraCaptureError.cannotAddCameraInput
        }
        session.addInput(cameraInput)

        if microphoneAuthorized,
           let microphone = AVCaptureDevice.default(for: .audio) {
            let microphoneInput = try AVCaptureDeviceInput(
                device: microphone
            )
            if session.canAddInput(microphoneInput) {
                session.addInput(microphoneInput)
            }
        }

        guard session.canAddOutput(movieOutput) else {
            throw CameraCaptureError.cannotAddMovieOutput
        }
        session.addOutput(movieOutput)
        movieOutput.movieFragmentInterval = CMTime(
            seconds: 2,
            preferredTimescale: 600
        )

        configured = true
        configuredWithMicrophone = microphoneAuthorized
    }
}

extension CameraCaptureRecorder:
    AVCaptureFileOutputRecordingDelegate {
    nonisolated func fileOutput(
        _ output: AVCaptureFileOutput,
        didStartRecordingTo fileURL: URL,
        from connections: [AVCaptureConnection]
    ) {
        Task { @MainActor [weak self] in
            self?.isRecording = true
            self?.errorMessage = nil
        }
    }

    nonisolated func fileOutput(
        _ output: AVCaptureFileOutput,
        didFinishRecordingTo outputFileURL: URL,
        from connections: [AVCaptureConnection],
        error: Error?
    ) {
        let errorDescription = error?.localizedDescription

        Task { @MainActor [weak self] in
            guard let self else { return }

            isRecording = false
            if session.isRunning {
                session.stopRunning()
            }

            if let errorDescription {
                try? FileManager.default.removeItem(
                    at: outputFileURL
                )
                self.errorMessage =
                    "Kameraaufnahme wurde nicht gespeichert: "
                    + errorDescription
                return
            }

            guard FileManager.default.fileExists(
                atPath: outputFileURL.path
            ) else {
                self.errorMessage =
                    "Kameraaufnahme wurde beendet, aber die Datei fehlt."
                return
            }

            completedRecordingURL = outputFileURL
        }
    }
}

private enum CameraCaptureError: Error, LocalizedError {
    case cameraNotAuthorized
    case cameraUnavailable
    case cannotAddCameraInput
    case cannotAddMovieOutput

    var errorDescription: String? {
        switch self {
        case .cameraNotAuthorized:
            return "Der Kamerazugriff ist nicht freigegeben."
        case .cameraUnavailable:
            return "Auf diesem Mac wurde keine Kamera gefunden."
        case .cannotAddCameraInput:
            return "Die Kamera konnte nicht zur Aufnahme-Session hinzugefügt werden."
        case .cannotAddMovieOutput:
            return "Die Videoausgabe konnte nicht zur Aufnahme-Session hinzugefügt werden."
        }
    }
}
#endif
