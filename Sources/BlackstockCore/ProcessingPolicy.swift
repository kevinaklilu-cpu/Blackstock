import Foundation

public enum ProviderCostClass: String, Codable, Sendable {
    case localNoAPI = "LOCAL_NO_API"
    case freeQuota = "FREE_QUOTA"
    case paid = "PAID"
}

public enum ProcessingCapability: String, Codable, Sendable, CaseIterable {
    case youtubeDiscovery = "YOUTUBE_DISCOVERY"
    case remoteVideoIngest = "REMOTE_VIDEO_INGEST"
    case transcription = "TRANSCRIPTION"
    case semanticAnalysis = "SEMANTIC_ANALYSIS"
    case clipping = "CLIPPING"
    case reframing = "REFRAMING"
    case captions = "CAPTIONS"
    case rendering = "RENDERING"
    case upload = "UPLOAD"
}

public struct ProcessingProviderDescriptor: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let displayName: String
    public let capabilities: Set<ProcessingCapability>
    public let costClass: ProviderCostClass
    public let requiresPaymentMethod: Bool
    public let freeQuotaDescription: String?
    public let available: Bool
    public let lastVerifiedAt: Date

    public init(
        id: String,
        displayName: String,
        capabilities: Set<ProcessingCapability>,
        costClass: ProviderCostClass,
        requiresPaymentMethod: Bool,
        freeQuotaDescription: String?,
        available: Bool,
        lastVerifiedAt: Date
    ) {
        self.id = id
        self.displayName = displayName
        self.capabilities = capabilities
        self.costClass = costClass
        self.requiresPaymentMethod = requiresPaymentMethod
        self.freeQuotaDescription = freeQuotaDescription
        self.available = available
        self.lastVerifiedAt = lastVerifiedAt
    }
}

public struct ZeroCostProcessingPolicy: Codable, Sendable, Equatable {
    public let allowFreeExternalProviders: Bool
    public let allowPaidProviders: Bool

    public init(
        allowFreeExternalProviders: Bool = true,
        allowPaidProviders: Bool = false
    ) {
        self.allowFreeExternalProviders = allowFreeExternalProviders
        self.allowPaidProviders = allowPaidProviders
    }

    public func permits(_ provider: ProcessingProviderDescriptor) -> Bool {
        guard provider.available else { return false }
        switch provider.costClass {
        case .localNoAPI:
            return true
        case .freeQuota:
            return allowFreeExternalProviders && !provider.requiresPaymentMethod
        case .paid:
            return allowPaidProviders
        }
    }
}

public enum ProcessingRouteStatus: String, Codable, Sendable {
    case ready = "READY"
    case freeQuotaUnavailable = "FREE_QUOTA_UNAVAILABLE"
    case externalProviderRequired = "EXTERNAL_PROVIDER_REQUIRED"
}

public struct ProcessingRoute: Codable, Sendable, Equatable {
    public let capability: ProcessingCapability
    public let providerID: String?
    public let status: ProcessingRouteStatus
    public let explanation: String

    public init(
        capability: ProcessingCapability,
        providerID: String?,
        status: ProcessingRouteStatus,
        explanation: String
    ) {
        self.capability = capability
        self.providerID = providerID
        self.status = status
        self.explanation = explanation
    }
}

public struct ZeroCostProviderSelector: Sendable {
    public init() {}

    public func select(
        capability: ProcessingCapability,
        providers: [ProcessingProviderDescriptor],
        policy: ZeroCostProcessingPolicy = .init()
    ) -> ProcessingRoute {
        let candidates = providers.filter {
            $0.capabilities.contains(capability) && policy.permits($0)
        }

        if let local = candidates.first(where: { $0.costClass == .localNoAPI }) {
            return .init(
                capability: capability,
                providerID: local.id,
                status: .ready,
                explanation: "Blackstock verarbeitet diese Funktion lokal ohne laufende API-Kosten."
            )
        }

        if let free = candidates.first(where: { $0.costClass == .freeQuota }) {
            return .init(
                capability: capability,
                providerID: free.id,
                status: .ready,
                explanation: "Blackstock nutzt ein kostenloses externes Kontingent und fällt bei Nichtverfügbarkeit nicht automatisch auf kostenpflichtige Nutzung zurück."
            )
        }

        let hasAnyFreeCandidate = providers.contains {
            $0.capabilities.contains(capability)
            && $0.costClass == .freeQuota
        }
        if hasAnyFreeCandidate {
            return .init(
                capability: capability,
                providerID: nil,
                status: .freeQuotaUnavailable,
                explanation: "Das kostenlose Kontingent ist derzeit nicht nutzbar. Blackstock startet keine kostenpflichtige Verarbeitung automatisch."
            )
        }

        return .init(
            capability: capability,
            providerID: nil,
            status: .externalProviderRequired,
            explanation: "Für diese Funktion ist derzeit kein lokaler oder kostenloser freigegebener Provider verfügbar."
        )
    }
}

public enum BuiltInProcessingProviders {
    public static let localNative = ProcessingProviderDescriptor(
        id: "blackstock.local",
        displayName: "Blackstock Local",
        capabilities: [.clipping, .rendering],
        costClass: .localNoAPI,
        requiresPaymentMethod: false,
        freeQuotaDescription: "Lokaler AVFoundation-Schnitt und Render ohne externe API.",
        available: true,
        lastVerifiedAt: Date(timeIntervalSince1970: 1_789_776_000)
    )

    public static let plannedLocalIntelligence = ProcessingProviderDescriptor(
        id: "blackstock.local.intelligence",
        displayName: "Blackstock Local Intelligence",
        capabilities: [.transcription, .semanticAnalysis, .reframing, .captions],
        costClass: .localNoAPI,
        requiresPaymentMethod: false,
        freeQuotaDescription: "Geplante lokale Speech/Vision/Core-ML-Pipeline; noch nicht freigegeben.",
        available: false,
        lastVerifiedAt: Date(timeIntervalSince1970: 1_789_776_000)
    )

    public static let youtubeOfficial = ProcessingProviderDescriptor(
        id: "youtube.official",
        displayName: "YouTube Official API",
        capabilities: [.youtubeDiscovery, .upload],
        costClass: .freeQuota,
        requiresPaymentMethod: false,
        freeQuotaDescription: "Offizielles API-Kontingent; kein Pay-as-you-go-Fallback durch Blackstock.",
        available: true,
        lastVerifiedAt: Date(timeIntervalSince1970: 1_789_776_000)
    )

    public static let cloudflareWorkersAIFree = ProcessingProviderDescriptor(
        id: "cloudflare.workers-ai.free",
        displayName: "Cloudflare Workers AI Free",
        capabilities: [.transcription, .semanticAnalysis],
        costClass: .freeQuota,
        requiresPaymentMethod: false,
        freeQuotaDescription: "Workers-Free-Kontingent; Adapter noch nicht implementiert.",
        available: false,
        lastVerifiedAt: Date(timeIntervalSince1970: 1_789_776_000)
    )

    public static let groqFree = ProcessingProviderDescriptor(
        id: "groq.free",
        displayName: "Groq Free Tier",
        capabilities: [.transcription, .semanticAnalysis],
        costClass: .freeQuota,
        requiresPaymentMethod: false,
        freeQuotaDescription: "Free-Tier-Ratenlimits; Adapter noch nicht implementiert.",
        available: false,
        lastVerifiedAt: Date(timeIntervalSince1970: 1_789_776_000)
    )

    public static let opusClipAPI = ProcessingProviderDescriptor(
        id: "opusclip.api",
        displayName: "OpusClip API",
        capabilities: [.remoteVideoIngest, .clipping, .reframing, .captions],
        costClass: .paid,
        requiresPaymentMethod: true,
        freeQuotaDescription: nil,
        available: true,
        lastVerifiedAt: Date(timeIntervalSince1970: 1_789_776_000)
    )
}
