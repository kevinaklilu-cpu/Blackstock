#if os(macOS)
import SwiftUI
import BlackstockCore

struct CaptureCapabilityPanel: View {
    let onRecordedMedia: (URL, CaptureKind) -> Void

    @State private var snapshot = CaptureCapabilityProbe().inspect()
    @State private var requesting: CaptureKind?
    @StateObject private var cameraRecorder = CameraCaptureRecorder()
    @StateObject private var microphoneRecorder = MicrophoneCaptureRecorder()
    @StateObject private var screenRecorder = ScreenCaptureRecorder()

    var body: some View {
        GroupBox("Direkte Aufnahme") {
            VStack(alignment: .leading, spacing: 10) {
                Text("Blackstock prüft die vier kanonischen Capture-Pfade getrennt. Aufzeichnungen werden lokal erzeugt und anschließend durch dieselbe Rechteprüfung wie importierte Medien geführt.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                ForEach(CaptureKind.allCases, id: \.self) { kind in
                    let capability = snapshot.capability(for: kind)

                    HStack(spacing: 10) {
                        Image(systemName: icon(for: kind))
                            .frame(width: 22)
                            .accessibilityHidden(true)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(kind.germanTitle)
                                .font(.callout.weight(.semibold))
                            Text(statusText(capability, kind: kind))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        if capability?.authorization == .notDetermined {
                            permissionButton(for: kind)
                        } else if kind == .camera,
                                  capability?.isReady == true {
                            cameraRecordingButton
                        } else if kind == .microphone,
                                  capability?.isReady == true {
                            microphoneRecordingButton
                        } else if kind == .screen,
                                  capability?.isReady == true {
                            screenRecordingButton
                        } else {
                            Label(
                                capability?.isReady == true
                                    ? "Berechtigung bereit"
                                    : "Nicht bereit",
                                systemImage: capability?.isReady == true
                                    ? "checkmark.circle.fill"
                                    : "exclamationmark.triangle"
                            )
                            .font(.caption)
                        }
                    }
                }

                if let error = cameraRecorder.errorMessage {
                    captureError(error)
                }
                if let error = microphoneRecorder.errorMessage {
                    captureError(error)
                }
                if let error = screenRecorder.errorMessage {
                    captureError(error)
                }

                Divider()

                Text(captureProgressText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 4)
        }
        .task {
            snapshot = CaptureCapabilityProbe().inspect()
        }
        .onChange(
            of: cameraRecorder.completedRecordingURL
        ) { url in
            guard let url else { return }
            onRecordedMedia(url, .camera)
        }
        .onChange(
            of: microphoneRecorder.completedRecordingURL
        ) { url in
            guard let url else { return }
            onRecordedMedia(url, .microphone)
        }
        .onChange(
            of: screenRecorder.completedRecordingURL
        ) { url in
            guard let url else { return }
            onRecordedMedia(url, .screen)
        }
    }

    @ViewBuilder
    private func permissionButton(
        for kind: CaptureKind
    ) -> some View {
        Button {
            Task {
                requesting = kind
                let granted =
                    await CaptureCapabilityProbe()
                        .requestAuthorization(
                            for: kind
                        )
                if !granted {
                    BlackstockCaptureHardwareAudit
                        .recordDeniedPermission(
                            for: kind
                        )
                }
                snapshot = CaptureCapabilityProbe()
                    .inspect()
                requesting = nil
            }
        } label: {
            HStack {
                if requesting == kind {
                    ProgressView()
                        .controlSize(.small)
                }
                Text(
                    requesting == kind
                        ? "Wird angefragt …"
                        : "Zugriff anfragen"
                )
            }
        }
        .disabled(
            requesting != nil
            || cameraRecorder.isRecording
            || microphoneRecorder.isRecording
            || screenRecorder.isRecording
        )
    }

    @ViewBuilder
    private var cameraRecordingButton: some View {
        if cameraRecorder.isRecording {
            Button(role: .destructive) {
                cameraRecorder.stopRecording()
            } label: {
                Label(
                    "Aufnahme stoppen",
                    systemImage: "stop.circle.fill"
                )
            }
        } else {
            Button {
                Task {
                    await cameraRecorder.startRecording()
                }
            } label: {
                HStack {
                    if cameraRecorder.isPreparing {
                        ProgressView()
                            .controlSize(.small)
                    }
                    Label(
                        cameraRecorder.isPreparing
                            ? "Kamera wird vorbereitet …"
                            : "Kamera aufnehmen",
                        systemImage: "record.circle"
                    )
                }
            }
            .disabled(
                cameraRecorder.isPreparing
                || microphoneRecorder.isPreparing
                || microphoneRecorder.isRecording
                || screenRecorder.isPreparing
                || screenRecorder.isRecording
            )
        }
    }

    @ViewBuilder
    private var microphoneRecordingButton: some View {
        if microphoneRecorder.isRecording {
            Button(role: .destructive) {
                microphoneRecorder.stopRecording()
            } label: {
                Label(
                    "Mikrofon stoppen",
                    systemImage: "stop.circle.fill"
                )
            }
        } else {
            Button {
                Task {
                    await microphoneRecorder.startRecording()
                }
            } label: {
                HStack {
                    if microphoneRecorder.isPreparing {
                        ProgressView()
                            .controlSize(.small)
                    }
                    Label(
                        microphoneRecorder.isPreparing
                            ? "Mikrofon wird vorbereitet …"
                            : "Mikrofon aufnehmen",
                        systemImage: "record.circle"
                    )
                }
            }
            .disabled(
                microphoneRecorder.isPreparing
                || cameraRecorder.isPreparing
                || cameraRecorder.isRecording
                || screenRecorder.isPreparing
                || screenRecorder.isRecording
            )
        }
    }

    @ViewBuilder
    private var screenRecordingButton: some View {
        if screenRecorder.isRecording {
            Button(role: .destructive) {
                Task {
                    await screenRecorder.stopRecording()
                }
            } label: {
                Label(
                    "Bildschirm stoppen",
                    systemImage: "stop.circle.fill"
                )
            }
        } else {
            Button {
                Task {
                    await screenRecorder.startRecording()
                }
            } label: {
                HStack {
                    if screenRecorder.isPreparing {
                        ProgressView()
                            .controlSize(.small)
                    }
                    Label(
                        screenRecorder.isPreparing
                            ? "Bildschirm wird vorbereitet …"
                            : "Bildschirm aufnehmen",
                        systemImage: "record.circle"
                    )
                }
            }
            .disabled(
                !screenRecorder.isSupportedOnCurrentOS
                || screenRecorder.isPreparing
                || cameraRecorder.isPreparing
                || cameraRecorder.isRecording
                || microphoneRecorder.isPreparing
                || microphoneRecorder.isRecording
            )
        }
    }

    @ViewBuilder
    private func captureError(
        _ message: String
    ) -> some View {
        Label(
            message,
            systemImage: "exclamationmark.triangle"
        )
        .font(.caption)
        .foregroundStyle(.red)
    }

    private var captureProgressText: String {
        if cameraRecorder.isRecording {
            return "Kameraaufnahme läuft lokal. Ein freigegebenes Mikrofon wird in dieselbe Movie-Aufnahme eingebettet. Nach dem Stoppen folgt die Rechtebestätigung."
        }

        if microphoneRecorder.isRecording {
            return "Mikrofonaufnahme läuft lokal als zusätzliche Audioquelle. Nach dem Stoppen folgt die Rechtebestätigung; der Hauptvideo-Slot wird nicht überschrieben."
        }

        if screenRecorder.isRecording {
            return "Bildschirmaufnahme läuft lokal. ScreenCaptureKit zeichnet Systemaudio mit auf und schließt Blackstocks eigenen Prozess aus. Nach dem Stoppen folgt die Rechtebestätigung."
        }

        if !screenRecorder.isSupportedOnCurrentOS {
            return "Kamera- und Mikrofonaufnahme sind implementiert. Die direkte Bildschirm-/Systemaudio-Dateiaufzeichnung benötigt in diesem Build macOS 15 oder neuer; die Berechtigungen werden trotzdem getrennt und ehrlich ausgewiesen."
        }

        if snapshot.allCanonicalCapturePathsReady {
            return "Kamera, eigenständiges Mikrofon sowie Bildschirm inklusive Systemaudio können lokal aufgezeichnet werden. Alle Ergebnisse durchlaufen vor der Projektübernahme die Rechtebestätigung."
        }

        return "Direkte Aufnahme wird nur angeboten, wenn die jeweilige Hardware und macOS-Berechtigung bereit sind. Datei-Import bleibt weiterhin verfügbar."
    }

    private func statusText(
        _ capability: CaptureCapability?,
        kind: CaptureKind
    ) -> String {
        guard let capability else {
            return "Status nicht verfügbar"
        }

        if let reason = capability.blockingReason {
            return reason
        }

        switch kind {
        case .microphone:
            return "Autorisiert. Eigenständige Audioaufnahme ist verfügbar; bei Kameraaufnahme kann das Mikrofon zusätzlich eingebettet werden."
        case .systemAudio:
            return screenRecorder.isSupportedOnCurrentOS
                ? "Autorisiert. Wird gemeinsam mit der Bildschirmaufnahme aufgezeichnet."
                : "Autorisiert; direkte Dateiaufzeichnung benötigt in diesem Build macOS 15 oder neuer."
        case .camera, .screen:
            return "Hardware vorhanden und von macOS autorisiert."
        }
    }

    private func icon(for kind: CaptureKind) -> String {
        switch kind {
        case .camera:
            return "video"
        case .microphone:
            return "mic"
        case .screen:
            return "rectangle.on.rectangle"
        case .systemAudio:
            return "speaker.wave.2"
        }
    }
}
#endif
