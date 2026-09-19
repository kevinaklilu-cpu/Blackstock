#if os(macOS)
import AVFoundation
import CoreGraphics
import Foundation
import BlackstockCore

struct CaptureCapabilityProbe: Sendable {
    func inspect(now: Date = Date()) -> CaptureCapabilitySnapshot {
        let screenAuthorized = CGPreflightScreenCaptureAccess()

        return CaptureCapabilitySnapshot(
            capabilities: [
                CaptureCapability(
                    kind: .camera,
                    authorization: Self.map(
                        AVCaptureDevice.authorizationStatus(for: .video)
                    ),
                    hardwareAvailable: AVCaptureDevice.default(for: .video) != nil
                ),
                CaptureCapability(
                    kind: .microphone,
                    authorization: Self.map(
                        AVCaptureDevice.authorizationStatus(for: .audio)
                    ),
                    hardwareAvailable: AVCaptureDevice.default(for: .audio) != nil
                ),
                CaptureCapability(
                    kind: .screen,
                    authorization: screenAuthorized
                        ? .authorized
                        : .notDetermined,
                    hardwareAvailable: true
                ),
                CaptureCapability(
                    kind: .systemAudio,
                    authorization: screenAuthorized
                        ? .authorized
                        : .notDetermined,
                    hardwareAvailable: true
                )
            ],
            inspectedAt: now
        )
    }

    func requestAuthorization(for kind: CaptureKind) async -> Bool {
        switch kind {
        case .camera:
            return await Self.requestAVAuthorization(for: .video)
        case .microphone:
            return await Self.requestAVAuthorization(for: .audio)
        case .screen, .systemAudio:
            return CGRequestScreenCaptureAccess()
        }
    }

    private static func requestAVAuthorization(
        for mediaType: AVMediaType
    ) async -> Bool {
        await withCheckedContinuation { continuation in
            AVCaptureDevice.requestAccess(for: mediaType) { granted in
                continuation.resume(returning: granted)
            }
        }
    }

    private static func map(
        _ status: AVAuthorizationStatus
    ) -> CaptureAuthorizationState {
        switch status {
        case .authorized:
            return .authorized
        case .denied:
            return .denied
        case .restricted:
            return .restricted
        case .notDetermined:
            return .notDetermined
        @unknown default:
            return .unavailable
        }
    }
}
#endif
