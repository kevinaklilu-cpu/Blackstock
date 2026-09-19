#if os(macOS)
import SwiftUI
import BlackstockCore

struct CaptureCapabilityPanel: View {
    @State private var snapshot = CaptureCapabilityProbe().inspect()
    @State private var requesting: CaptureKind?

    var body: some View {
        GroupBox("Direkte Aufnahme") {
            VStack(alignment: .leading, spacing: 10) {
                Text("Blackstock prüft die vier kanonischen Capture-Pfade getrennt. Eine Freigabe bedeutet noch nicht, dass bereits aufgenommen wird.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                ForEach(CaptureKind.allCases, id: \.self) { kind in
                    let capability = snapshot.capability(for: kind)

                    HStack(spacing: 10) {
                        Image(
                            systemName: icon(for: kind)
                        )
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
                        } else {
                            Label(
                                capability?.isReady == true
                                    ? "Bereit"
                                    : "Nicht bereit",
                                systemImage: capability?.isReady == true
                                    ? "checkmark.circle.fill"
                                    : "exclamationmark.triangle"
                            )
                            .font(.caption)
                        }
                    }
                    .accessibilityElement(children: .combine)
                }

                Divider()

                Text(
                    snapshot.allCanonicalCapturePathsReady
                        ? "Alle Capture-Berechtigungen sind verfügbar. Die eigentliche Aufnahme-Pipeline wird als nächster Schritt freigeschaltet."
                        : "Mindestens ein Capture-Pfad ist noch nicht bereit. Datei-Import bleibt weiterhin verfügbar."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 4)
        }
        .task {
            snapshot = CaptureCapabilityProbe().inspect()
        }
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
