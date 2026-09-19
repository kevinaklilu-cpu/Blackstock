#if os(macOS)
import AVFoundation
import Combine
import Foundation
import ScreenCaptureKit

@MainActor
final class ScreenCaptureRecorder: ObservableObject {
    @Published private(set) var isPreparing = false
    @Published private(set) var isRecording = false
    @Published private(set) var completedRecordingURL: URL?
    @Published private(set) var errorMessage: String?

    private var implementation: AnyObject?

    var isSupportedOnCurrentOS: Bool {
        if #available(macOS 15.0, *) {
            return true
        }
        return false
    }

    func startRecording() async {
        guard !isPreparing, !isRecording else { return }

        completedRecordingURL = nil
        errorMessage = nil

        guard #available(macOS 15.0, *) else {
            errorMessage = "Direkte ScreenCaptureKit-Dateiaufzeichnung benötigt in diesem Build macOS 15 oder neuer."
            return
        }

        isPreparing = true
        defer { isPreparing = false }

        do {
            let recorder = ScreenCaptureRecordingImplementation(
                owner: self
            )
            implementation = recorder
            try await recorder.start()
        } catch {
            implementation = nil
            errorMessage =
                "Bildschirmaufnahme konnte nicht gestartet werden: "
                + error.localizedDescription
        }
    }

    func stopRecording() async {
        guard #available(macOS 15.0, *),
              let recorder = implementation
                as? ScreenCaptureRecordingImplementation else {
            return
        }

        do {
            try await recorder.stop()
        } catch {
            errorMessage =
                "Bildschirmaufnahme konnte nicht sauber beendet werden: "
                + error.localizedDescription
        }
    }

    fileprivate func recordingDidStart() {
        isRecording = true
        errorMessage = nil
    }

    fileprivate func recordingDidFinish(
        outputURL: URL
    ) {
        isRecording = false
        implementation = nil

        guard FileManager.default.fileExists(
            atPath: outputURL.path
        ) else {
            errorMessage =
                "Bildschirmaufnahme wurde beendet, aber die Datei fehlt."
            return
        }

        completedRecordingURL = outputURL
    }

    fileprivate func recordingDidFail(
        description: String,
        outputURL: URL?
    ) {
        isRecording = false
        implementation = nil
        if let outputURL {
            try? FileManager.default.removeItem(
                at: outputURL
            )
        }
        errorMessage =
            "Bildschirmaufnahme wurde nicht gespeichert: "
            + description
    }
}

@available(macOS 15.0, *)
@MainActor
private final class ScreenCaptureRecordingImplementation:
    NSObject,
    SCRecordingOutputDelegate,
    SCStreamDelegate {

    private weak var owner: ScreenCaptureRecorder?
    private var stream: SCStream?
    private var recordingOutput: SCRecordingOutput?
    private var outputURL: URL?

    init(owner: ScreenCaptureRecorder) {
        self.owner = owner
        super.init()
    }

    func start() async throws {
        let content = try await SCShareableContent
            .excludingDesktopWindows(
                false,
                onScreenWindowsOnly: true
            )

        guard let display = content.displays.first else {
            throw ScreenCaptureRecordingError.noDisplay
        }

        let filter = SCContentFilter(
            display: display,
            excludingWindows: []
        )

        let configuration = SCStreamConfiguration()
        configuration.width = display.width
        configuration.height = display.height
        configuration.minimumFrameInterval = CMTime(
            value: 1,
            timescale: 30
        )
        configuration.queueDepth = 5
        configuration.showsCursor = true
        configuration.capturesAudio = true
        configuration.sampleRate = 48_000
        configuration.channelCount = 2
        configuration.excludesCurrentProcessAudio = true

        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "Blackstock-Screen-\(UUID().uuidString)"
            )
            .appendingPathExtension("mp4")
        try? FileManager.default.removeItem(at: outputURL)
        self.outputURL = outputURL

        let recordingConfiguration =
            SCRecordingOutputConfiguration()
        recordingConfiguration.outputURL = outputURL
        recordingConfiguration.outputFileType = .mp4

        let recordingOutput = SCRecordingOutput(
            configuration: recordingConfiguration,
            delegate: self
        )
        self.recordingOutput = recordingOutput

        let stream = SCStream(
            filter: filter,
            configuration: configuration,
            delegate: self
        )
        self.stream = stream

        try stream.addRecordingOutput(recordingOutput)
        try await stream.startCapture()
    }

    func stop() async throws {
        guard let stream else { return }
        try await stream.stopCapture()
    }

    nonisolated func recordingOutputDidStartRecording(
        _ recordingOutput: SCRecordingOutput
    ) {
        Task { @MainActor [weak self] in
            self?.owner?.recordingDidStart()
        }
    }

    nonisolated func recordingOutputDidFinishRecording(
        _ recordingOutput: SCRecordingOutput
    ) {
        Task { @MainActor [weak self] in
            guard let self,
                  let outputURL = self.outputURL else {
                return
            }
            self.owner?.recordingDidFinish(
                outputURL: outputURL
            )
        }
    }

    nonisolated func recordingOutput(
        _ recordingOutput: SCRecordingOutput,
        didFailWithError error: any Error
    ) {
        let description = error.localizedDescription

        Task { @MainActor [weak self] in
            guard let self else { return }
            self.owner?.recordingDidFail(
                description: description,
                outputURL: self.outputURL
            )
        }
    }

    nonisolated func stream(
        _ stream: SCStream,
        didStopWithError error: any Error
    ) {
        let description = error.localizedDescription

        Task { @MainActor [weak self] in
            guard let self else { return }
            self.owner?.recordingDidFail(
                description: description,
                outputURL: self.outputURL
            )
        }
    }
}

private enum ScreenCaptureRecordingError:
    Error,
    LocalizedError {
    case noDisplay

    var errorDescription: String? {
        switch self {
        case .noDisplay:
            return "Es wurde kein aufnehmbarer Bildschirm gefunden."
        }
    }
}
#endif
