#if os(macOS)
import SwiftUI
import BlackstockCore

struct CaptureCapabilityPanel: View {
    let onRecordedMedia: (URL, CaptureKind) -> Void

    @State private var snapshot = CaptureCapabilityProbe().inspect()
    @State private var requesting: CaptureKind?
    @StateObject private var cameraRecorder = CameraCaptureRecorder()

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
                            Text(statusText(capability))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        if capability?.authorization == .notDetermined {
                            permissionButton(for: kind)
                        } else if kind == .camera,
                                  capability?.isReady == true {
                            cameraRecordingButton
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
                    Label(
                        error,
                        systemImage: "exclamationmark.triangle"
                    )
                    .font(.caption)
                    .foregroundStyle(.red)
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
    }

    @ViewBuilder
    private func permissionButton(
        for kind: CaptureKind
    ) -> some View {
        Button {
            Task {
                requesting = kind
                _ = await CaptureCapabilityProbe()
                    .requestAuthorization(for: kind)
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
        .disabled(requesting != nil)
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
            .disabled(cameraRecorder.isPreparing)
        }
    }

    private var captureProgressText: String {
        if cameraRecorder.isRecording {
            return "Kameraaufnahme läuft lokal. Nach „Aufnahme stoppen“ wird die Datei erst nach deiner Rechtebestätigung in den Projekt-Arbeitsbereich übernommen."
        }

        if snapshot.allCanonicalCapturePathsReady {
            return "Alle vier Capture-Berechtigungen sind verfügbar. Kameraaufnahme ist aktiv implementiert; Mikrofon-, Bildschirm- und Systemaudio-Aufzeichnung folgen auf derselben Grundlage."
        }

        return "Kameraaufnahme ist verfügbar, sobald Kamera-Hardware und Berechtigung bereit sind. Datei-Import bleibt weiterhin verfügbar."
    }

    private func statusText(
        _ capability: CaptureCapability?
    ) -> String {
        guard let capability else {
            return "Status nicht verfügbar"
        }

        if let reason = capability.blockingReason {
            return reason
        }
        return "Hardware vorhanden und von macOS autorisiert."
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
