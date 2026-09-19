import XCTest
@testable import BlackstockCore

final class CaptureCapabilityTests: XCTestCase {
    func testAllCanonicalCaptureKindsAreRepresented() {
        XCTAssertEqual(
            Set(CaptureKind.allCases),
            Set([.camera, .microphone, .screen, .systemAudio])
        )
    }

    func testReadyRequiresHardwareAndAuthorization() {
        XCTAssertTrue(
            CaptureCapability(
                kind: .camera,
                authorization: .authorized,
                hardwareAvailable: true
            ).isReady
        )
        XCTAssertFalse(
            CaptureCapability(
                kind: .camera,
                authorization: .authorized,
                hardwareAvailable: false
            ).isReady
        )
        XCTAssertFalse(
            CaptureCapability(
                kind: .camera,
                authorization: .denied,
                hardwareAvailable: true
            ).isReady
        )
    }

    func testSnapshotRequiresEveryCanonicalPathReady() {
        let ready = CaptureCapabilitySnapshot(
            capabilities: CaptureKind.allCases.map {
                CaptureCapability(
                    kind: $0,
                    authorization: .authorized,
                    hardwareAvailable: true
                )
            },
            inspectedAt: Date(timeIntervalSince1970: 1)
        )
        XCTAssertTrue(ready.allCanonicalCapturePathsReady)

        var incomplete = ready.capabilities
        incomplete.removeLast()
        XCTAssertFalse(
            CaptureCapabilitySnapshot(
                capabilities: incomplete,
                inspectedAt: Date(timeIntervalSince1970: 2)
            ).allCanonicalCapturePathsReady
        )
    }

    func testBlockingReasonNeverPretendsDeniedAccessIsReady() {
        let capability = CaptureCapability(
            kind: .microphone,
            authorization: .denied,
            hardwareAvailable: true
        )
        XCTAssertNotNil(capability.blockingReason)
        XCTAssertFalse(capability.isReady)
    }
}
