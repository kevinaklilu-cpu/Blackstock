#if os(macOS)
import AVFoundation
import Combine
import CoreMedia
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
        true
    }

    func startRecording() async {
        guard !isPreparing, !isRecording else { return }

        completedRecordingURL = nil
        errorMessage = nil
        isPreparing = true
        defer { isPreparing = false }

        do {
            if #available(macOS 15.0, *) {
                let recorder = ScreenCaptureRecordingImplementation(
                    owner: self
                )
                implementation = recorder
                try await recorder.start()
            } else {
                let recorder = LegacyScreenCaptureRecordingImplementation(
                    owner: self
                )
                implementation = recorder
                try await recorder.start()
            }
        } catch {
            implementation = nil
            errorMessage =
                "Bildschirmaufnahme konnte nicht gestartet werden: "
                + error.localizedDescription
        }
    }

    func stopRecording() async {
        do {
            if #available(macOS 15.0, *),
               let recorder = implementation
                    as? ScreenCaptureRecordingImplementation {
                try await recorder.stop()
            } else if let recorder = implementation
                        as? LegacyScreenCaptureRecordingImplementation {
                try await recorder.stop()
            }
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

private func screenCaptureSetup() async throws -> (
    filter: SCContentFilter,
    configuration: SCStreamConfiguration,
    outputURL: URL,
    width: Int,
    height: Int
) {
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

    return (
        filter,
        configuration,
        outputURL,
        display.width,
        display.height
    )
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
        let setup = try await screenCaptureSetup()
        outputURL = setup.outputURL

        let recordingConfiguration =
            SCRecordingOutputConfiguration()
        recordingConfiguration.outputURL = setup.outputURL
        recordingConfiguration.outputFileType = .mp4

        let recordingOutput = SCRecordingOutput(
            configuration: recordingConfiguration,
            delegate: self
        )
        self.recordingOutput = recordingOutput

        let stream = SCStream(
            filter: setup.filter,
            configuration: setup.configuration,
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

private final class LegacyScreenCaptureRecordingImplementation:
    NSObject,
    SCStreamOutput,
    SCStreamDelegate,
    @unchecked Sendable {

    private weak var owner: ScreenCaptureRecorder?
    private let sampleQueue = DispatchQueue(
        label: "de.blackstock.capture.screen.samples"
    )

    private var stream: SCStream?
    private var writer: AVAssetWriter?
    private var videoInput: AVAssetWriterInput?
    private var audioInput: AVAssetWriterInput?
    private var outputURL: URL?
    private var sessionStarted = false
    private var stopping = false

    init(owner: ScreenCaptureRecorder) {
        self.owner = owner
        super.init()
    }

    func start() async throws {
        let setup = try await screenCaptureSetup()
        outputURL = setup.outputURL

        let writer = try AVAssetWriter(
            outputURL: setup.outputURL,
            fileType: .mp4
        )

        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: setup.width,
            AVVideoHeightKey: setup.height
        ]
        let videoInput = AVAssetWriterInput(
            mediaType: .video,
            outputSettings: videoSettings
        )
        videoInput.expectsMediaDataInRealTime = true

        let audioSettings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 48_000,
            AVNumberOfChannelsKey: 2,
            AVEncoderBitRateKey: 192_000
        ]
        let audioInput = AVAssetWriterInput(
            mediaType: .audio,
            outputSettings: audioSettings
        )
        audioInput.expectsMediaDataInRealTime = true

        guard writer.canAdd(videoInput) else {
            throw ScreenCaptureRecordingError.cannotAddVideoWriterInput
        }
        writer.add(videoInput)

        guard writer.canAdd(audioInput) else {
            throw ScreenCaptureRecordingError.cannotAddAudioWriterInput
        }
        writer.add(audioInput)

        self.writer = writer
        self.videoInput = videoInput
        self.audioInput = audioInput

        let stream = SCStream(
            filter: setup.filter,
            configuration: setup.configuration,
            delegate: self
        )
        self.stream = stream

        try stream.addStreamOutput(
            self,
            type: .screen,
            sampleHandlerQueue: sampleQueue
        )
        try stream.addStreamOutput(
            self,
            type: .audio,
            sampleHandlerQueue: sampleQueue
        )

        try await stream.startCapture()

        await MainActor.run { [weak self] in
            self?.owner?.recordingDidStart()
        }
    }

    func stop() async throws {
        guard !stopping else { return }
        stopping = true

        if let stream {
            try await stream.stopCapture()
        }

        try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<Void, Error>) in
            sampleQueue.async { [weak self] in
                guard let self else {
                    continuation.resume()
                    return
                }

                self.videoInput?.markAsFinished()
                self.audioInput?.markAsFinished()

                guard let writer = self.writer else {
                    continuation.resume(
                        throwing: ScreenCaptureRecordingError.writerMissing
                    )
                    return
                }

                guard self.sessionStarted else {
                    writer.cancelWriting()
                    continuation.resume(
                        throwing: ScreenCaptureRecordingError.noVideoFrames
                    )
                    return
                }

                writer.finishWriting { [weak self] in
                    guard let self else {
                        continuation.resume()
                        return
                    }

                    if writer.status == .completed,
                       let outputURL = self.outputURL {
                        Task { @MainActor [weak self] in
                            self?.owner?.recordingDidFinish(
                                outputURL: outputURL
                            )
                        }
                        continuation.resume()
                    } else {
                        let error = writer.error
                            ?? ScreenCaptureRecordingError.writerFailed
                        continuation.resume(throwing: error)
                    }
                }
            }
        }
    }

    func stream(
        _ stream: SCStream,
        didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
        of outputType: SCStreamOutputType
    ) {
        guard sampleBuffer.isValid,
              CMSampleBufferDataIsReady(sampleBuffer),
              !stopping else {
            return
        }

        switch outputType {
        case .screen:
            appendVideo(sampleBuffer)
        case .audio:
            appendAudio(sampleBuffer)
        @unknown default:
            break
        }
    }

    func stream(
        _ stream: SCStream,
        didStopWithError error: any Error
    ) {
        let description = error.localizedDescription
        let outputURL = outputURL

        Task { @MainActor [weak self] in
            self?.owner?.recordingDidFail(
                description: description,
                outputURL: outputURL
            )
        }
    }

    private func appendVideo(
        _ sampleBuffer: CMSampleBuffer
    ) {
        guard let writer,
              let videoInput else {
            return
        }

        if !sessionStarted {
            guard writer.startWriting() else {
                failWriter(
                    writer.error
                        ?? ScreenCaptureRecordingError.writerFailed
                )
                return
            }

            let timestamp = CMSampleBufferGetPresentationTimeStamp(
                sampleBuffer
            )
            writer.startSession(atSourceTime: timestamp)
            sessionStarted = true
        }

        guard writer.status == .writing else {
            failWriter(
                writer.error
                    ?? ScreenCaptureRecordingError.writerFailed
            )
            return
        }

        if videoInput.isReadyForMoreMediaData,
           !videoInput.append(sampleBuffer) {
            failWriter(
                writer.error
                    ?? ScreenCaptureRecordingError.writerFailed
            )
        }
    }

    private func appendAudio(
        _ sampleBuffer: CMSampleBuffer
    ) {
        guard sessionStarted,
              let writer,
              writer.status == .writing,
              let audioInput,
              audioInput.isReadyForMoreMediaData else {
            return
        }

        if !audioInput.append(sampleBuffer) {
            failWriter(
                writer.error
                    ?? ScreenCaptureRecordingError.writerFailed
            )
        }
    }

    private func failWriter(
        _ error: Error
    ) {
        guard !stopping else { return }
        stopping = true
        writer?.cancelWriting()

        let description = error.localizedDescription
        let outputURL = outputURL

        Task { @MainActor [weak self] in
            self?.owner?.recordingDidFail(
                description: description,
                outputURL: outputURL
            )
        }
    }
}

private enum ScreenCaptureRecordingError:
    Error,
    LocalizedError {
    case noDisplay
    case cannotAddVideoWriterInput
    case cannotAddAudioWriterInput
    case writerMissing
    case noVideoFrames
    case writerFailed

    var errorDescription: String? {
        switch self {
        case .noDisplay:
            return "Es wurde kein aufnehmbarer Bildschirm gefunden."
        case .cannotAddVideoWriterInput:
            return "Der Video-Encoder konnte nicht vorbereitet werden."
        case .cannotAddAudioWriterInput:
            return "Der Systemaudio-Encoder konnte nicht vorbereitet werden."
        case .writerMissing:
            return "Der lokale Screen-Recorder ist nicht initialisiert."
        case .noVideoFrames:
            return "Die Aufnahme enthielt keine vollständigen Bildschirmframes."
        case .writerFailed:
            return "Die lokale MP4-Datei konnte nicht finalisiert werden."
        }
    }
}
#endif
