import Foundation

public enum CaptureKind: String, CaseIterable, Codable, Sendable, Equatable {
    case camera
    case microphone
    case screen
    case systemAudio

    public var germanTitle: String {
        switch self {
        case .camera: return "Kamera"
        case .microphone: return "Mikrofon"
        case .screen: return "Bildschirm"
        case .systemAudio: return "Systemaudio"
        }
    }
}

public enum CaptureAuthorizationState: String, Codable, Sendable, Equatable {
    case authorized
    case denied
    case restricted
    case notDetermined
    case unavailable
}

public struct CaptureCapability: Codable, Sendable, Equatable, Identifiable {
    public var id: CaptureKind { kind }
    public let kind: CaptureKind
    public let authorization: CaptureAuthorizationState
    public let hardwareAvailable: Bool

    public init(
        kind: CaptureKind,
        authorization: CaptureAuthorizationState,
        hardwareAvailable: Bool
    ) {
        self.kind = kind
        self.authorization = authorization
        self.hardwareAvailable = hardwareAvailable
    }

    public var isReady: Bool {
        hardwareAvailable && authorization == .authorized
    }

    public var blockingReason: String? {
        guard hardwareAvailable else {
            return "\(kind.germanTitle) ist auf diesem Mac nicht verfügbar."
        }
        switch authorization {
        case .authorized:
            return nil
        case .denied:
            return "Zugriff auf \(kind.germanTitle) wurde verweigert."
        case .restricted:
            return "Zugriff auf \(kind.germanTitle) ist systemseitig eingeschränkt."
        case .notDetermined:
            return "Zugriff auf \(kind.germanTitle) wurde noch nicht angefragt."
        case .unavailable:
            return "\(kind.germanTitle) kann von Blackstock nicht verwendet werden."
        }
    }
}

public struct CaptureCapabilitySnapshot: Codable, Sendable, Equatable {
    public let capabilities: [CaptureCapability]
    public let inspectedAt: Date

    public init(
        capabilities: [CaptureCapability],
        inspectedAt: Date
    ) {
        self.capabilities = capabilities
        self.inspectedAt = inspectedAt
    }

    public func capability(for kind: CaptureKind) -> CaptureCapability? {
        capabilities.first { $0.kind == kind }
    }

    public var allCanonicalCapturePathsReady: Bool {
        CaptureKind.allCases.allSatisfy {
            capability(for: $0)?.isReady == true
        }
    }
}
