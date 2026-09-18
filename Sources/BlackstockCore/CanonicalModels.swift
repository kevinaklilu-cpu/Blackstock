import Foundation

// MARK: - Canonical requirement status

public enum RequirementStatus: String, Codable, Sendable, CaseIterable {
    case pass = "PASS"
    case fail = "FAIL"
    case blockedExternal = "BLOCKED_EXTERNAL"
}

// MARK: - Capability-driven product (Master Prompt §§ 6–7)

public enum CapabilityAuthorizationState: String, Codable, Sendable {
    case authorized
    case unauthorized
    case unavailable
}

public enum CapabilityPolicyState: String, Codable, Sendable {
    case allowed
    case denied
    case unknown
}

public enum CapabilityAvailability: String, Codable, Sendable {
    case available
    case unavailable
    case unknown
}

public enum CapabilityQualityStatus: String, Codable, Sendable {
    case pass
    case fail
}

public enum CapabilityTestStatus: String, Codable, Sendable {
    case pass
    case fail
}

public struct CapabilityRecord: Codable, Sendable, Equatable, Identifiable {
    public var id: String { capabilityId }

    public let capabilityId: String
    public let provider: String
    public let implementationVersion: String
    public let authorizationState: CapabilityAuthorizationState
    public let policyState: CapabilityPolicyState
    public let regionAvailability: CapabilityAvailability
    public let channelAvailability: CapabilityAvailability
    public let requiredScopes: Set<String>
    public let dataAvailability: CapabilityAvailability
    public let qualityStatus: CapabilityQualityStatus
    public let testStatus: CapabilityTestStatus
    public let lastVerifiedAt: Date

    public init(
        capabilityId: String,
        provider: String,
        implementationVersion: String,
        authorizationState: CapabilityAuthorizationState,
        policyState: CapabilityPolicyState,
        regionAvailability: CapabilityAvailability,
        channelAvailability: CapabilityAvailability,
        requiredScopes: Set<String> = [],
        dataAvailability: CapabilityAvailability,
        qualityStatus: CapabilityQualityStatus,
        testStatus: CapabilityTestStatus,
        lastVerifiedAt: Date
    ) {
        self.capabilityId = capabilityId
        self.provider = provider
        self.implementationVersion = implementationVersion
        self.authorizationState = authorizationState
        self.policyState = policyState
        self.regionAvailability = regionAvailability
        self.channelAvailability = channelAvailability
        self.requiredScopes = requiredScopes
        self.dataAvailability = dataAvailability
        self.qualityStatus = qualityStatus
        self.testStatus = testStatus
        self.lastVerifiedAt = lastVerifiedAt
    }

    public var mayBeVisibleToUser: Bool {
        authorizationState == .authorized &&
        policyState == .allowed &&
        regionAvailability == .available &&
        channelAvailability == .available &&
        dataAvailability == .available &&
        qualityStatus == .pass &&
        testStatus == .pass
    }
}

public actor CapabilityRegistry {
    private var records: [String: CapabilityRecord] = [:]

    public init(records: [CapabilityRecord] = []) {
        self.records = Dictionary(uniqueKeysWithValues: records.map { ($0.capabilityId, $0) })
    }

    public func upsert(_ record: CapabilityRecord) {
        records[record.capabilityId] = record
    }

    public func record(for capabilityId: String) -> CapabilityRecord? {
        records[capabilityId]
    }

    public func isVisible(_ capabilityId: String) -> Bool {
        records[capabilityId]?.mayBeVisibleToUser == true
    }

    public func visibleCapabilities() -> [CapabilityRecord] {
        records.values.filter(\.mayBeVisibleToUser).sorted { $0.capabilityId < $1.capabilityId }
    }
}

// MARK: - Strategy (Master Prompt §§ 18–26)

public struct HistoricalChannelProfile: Codable, Sendable, Equatable {
    public var observedTopics: [String]
    public var observedLanguages: [String]
    public var observedFormats: [String]
    public var observedAt: Date

    public init(
        observedTopics: [String] = [],
        observedLanguages: [String] = [],
        observedFormats: [String] = [],
        observedAt: Date
    ) {
        self.observedTopics = observedTopics
        self.observedLanguages = observedLanguages
        self.observedFormats = observedFormats
        self.observedAt = observedAt
    }
}

public enum StrategicObjective: String, Codable, Sendable, CaseIterable {
    case balanced
    case reach
    case watchTime
    case subscribers
    case revenue
}

public struct ExplorationPolicy: Codable, Sendable, Equatable {
    public var coreWeight: Double
    public var adjacentWeight: Double
    public var explorationWeight: Double

    public init(coreWeight: Double = 0.70, adjacentWeight: Double = 0.20, explorationWeight: Double = 0.10) {
        let total = max(coreWeight + adjacentWeight + explorationWeight, 0.0001)
        self.coreWeight = coreWeight / total
        self.adjacentWeight = adjacentWeight / total
        self.explorationWeight = explorationWeight / total
    }
}

public struct ChannelStrategy: Codable, Sendable, Equatable, Identifiable {
    public var id: String { "\(channelId)-v\(version)" }

    public let channelId: String
    public var primaryTopic: String
    public var topicDefinition: String
    public var contentPromise: String
    public var topicPillars: [String]
    public var adjacentTopics: [String]
    public var excludedTopics: [String]
    public var defaultContentLanguage: String
    public var researchLanguages: [String]
    public var regionProfile: String
    public var strategicAudienceHypothesis: String
    public var primaryObjectives: [StrategicObjective]
    public var explorationPolicy: ExplorationPolicy
    public var effectiveFrom: Date
    public var version: Int

    public init(
        channelId: String,
        primaryTopic: String,
        topicDefinition: String,
        contentPromise: String,
        topicPillars: [String],
        adjacentTopics: [String] = [],
        excludedTopics: [String] = [],
        defaultContentLanguage: String,
        researchLanguages: [String],
        regionProfile: String,
        strategicAudienceHypothesis: String,
        primaryObjectives: [StrategicObjective] = [.balanced],
        explorationPolicy: ExplorationPolicy = .init(),
        effectiveFrom: Date,
        version: Int
    ) {
        precondition(version > 0, "Strategy versions start at 1.")
        self.channelId = channelId
        self.primaryTopic = primaryTopic
        self.topicDefinition = topicDefinition
        self.contentPromise = contentPromise
        self.topicPillars = topicPillars
        self.adjacentTopics = adjacentTopics
        self.excludedTopics = excludedTopics
        self.defaultContentLanguage = defaultContentLanguage
        self.researchLanguages = researchLanguages
        self.regionProfile = regionProfile
        self.strategicAudienceHypothesis = strategicAudienceHypothesis
        self.primaryObjectives = primaryObjectives.isEmpty ? [.balanced] : primaryObjectives
        self.explorationPolicy = explorationPolicy
        self.effectiveFrom = effectiveFrom
        self.version = version
    }

    public func revised(effectiveFrom: Date, mutate: (inout ChannelStrategy) -> Void) -> ChannelStrategy {
        var copy = self
        mutate(&copy)
        copy.version = version + 1
        copy.effectiveFrom = effectiveFrom
        return copy
    }
}

// MARK: - Content language strategy (Master Prompt §§ 30–36)

public struct ContentLanguageStrategy: Codable, Sendable, Equatable {
    public var sourceLanguage: String
    public var primaryOutputLanguage: String
    public var titleLanguage: String
    public var descriptionLanguage: String
    public var thumbnailTextLanguage: String
    public var captionLanguage: String
    public var audioLanguage: String
    public var chapterLanguage: String
    public var metadataLanguage: String

    public init(
        sourceLanguage: String,
        primaryOutputLanguage: String,
        titleLanguage: String,
        descriptionLanguage: String,
        thumbnailTextLanguage: String,
        captionLanguage: String,
        audioLanguage: String,
        chapterLanguage: String,
        metadataLanguage: String
    ) {
        self.sourceLanguage = sourceLanguage
        self.primaryOutputLanguage = primaryOutputLanguage
        self.titleLanguage = titleLanguage
        self.descriptionLanguage = descriptionLanguage
        self.thumbnailTextLanguage = thumbnailTextLanguage
        self.captionLanguage = captionLanguage
        self.audioLanguage = audioLanguage
        self.chapterLanguage = chapterLanguage
        self.metadataLanguage = metadataLanguage
    }
}

// MARK: - Provenance and rights (Master Prompt §§ 37–42)

public enum RightsState: String, Codable, Sendable {
    case unknown
    case owned
    case licensed
    case authorized
    case prohibited
}

public enum SourceAuthorizationState: String, Codable, Sendable {
    case unknown
    case publicResearchOnly
    case authorizedResearch
    case authorizedProduction
}

public struct SourceProvenance: Codable, Sendable, Equatable, Identifiable {
    public var id: String { sourceId }

    public let sourceId: String
    public let sourceType: String
    public let platform: String
    public let originalURL: URL?
    public let videoId: String?
    public let channelId: String?
    public let channelName: String?
    public let title: String
    public let publishedAt: Date?
    public let originalLanguage: String?
    public let retrievedAt: Date
    public let rightsState: RightsState
    public let authorizationState: SourceAuthorizationState

    public init(
        sourceId: String,
        sourceType: String,
        platform: String,
        originalURL: URL?,
        videoId: String?,
        channelId: String?,
        channelName: String?,
        title: String,
        publishedAt: Date?,
        originalLanguage: String?,
        retrievedAt: Date,
        rightsState: RightsState,
        authorizationState: SourceAuthorizationState
    ) {
        self.sourceId = sourceId
        self.sourceType = sourceType
        self.platform = platform
        self.originalURL = originalURL
        self.videoId = videoId
        self.channelId = channelId
        self.channelName = channelName
        self.title = title
        self.publishedAt = publishedAt
        self.originalLanguage = originalLanguage
        self.retrievedAt = retrievedAt
        self.rightsState = rightsState
        self.authorizationState = authorizationState
    }
}

public struct AssetRightsEntry: Codable, Sendable, Equatable, Identifiable {
    public let id: UUID
    public var origin: String
    public var license: String?
    public var rightsHolder: String?
    public var commercialUseAllowed: Bool?
    public var attribution: String?
    public var expiresAt: Date?
    public var evidence: [String]

    public init(
        id: UUID = UUID(),
        origin: String,
        license: String? = nil,
        rightsHolder: String? = nil,
        commercialUseAllowed: Bool? = nil,
        attribution: String? = nil,
        expiresAt: Date? = nil,
        evidence: [String] = []
    ) {
        self.id = id
        self.origin = origin
        self.license = license
        self.rightsHolder = rightsHolder
        self.commercialUseAllowed = commercialUseAllowed
        self.attribution = attribution
        self.expiresAt = expiresAt
        self.evidence = evidence
    }

    public func isUsableForCommercialPublication(at date: Date) -> Bool {
        guard commercialUseAllowed == true else { return false }
        if let expiresAt, expiresAt <= date { return false }
        return !evidence.isEmpty
    }
}

// MARK: - Temporal research semantics (Master Prompt §§ 50–54)

public enum TemporalSemantic: String, Codable, Sendable {
    case publishedInWindow = "PUBLISHED_IN_WINDOW"
    case observedInWindow = "OBSERVED_IN_WINDOW"
    case analyticsPeriod = "ANALYTICS_PERIOD"
    case externalTrendPeriod = "EXTERNAL_TREND_PERIOD"
}

public enum ResearchTimeWindow: Codable, Sendable, Equatable {
    case lastHours(Int)
    case lastDays(Int)
    case lastMonths(Int)
    case custom(DateInterval)
    case sinceLastSuccessfulResearch(Date)

    public func interval(endingAt end: Date, calendar: Calendar = .current) -> DateInterval {
        switch self {
        case .lastHours(let hours):
            return DateInterval(start: end.addingTimeInterval(-Double(hours) * 3600), end: end)
        case .lastDays(let days):
            return DateInterval(start: end.addingTimeInterval(-Double(days) * 86400), end: end)
        case .lastMonths(let months):
            let start = calendar.date(byAdding: .month, value: -months, to: end) ?? end
            return DateInterval(start: start, end: end)
        case .custom(let interval):
            return interval
        case .sinceLastSuccessfulResearch(let date):
            return DateInterval(start: min(date, end), end: end)
        }
    }
}

// MARK: - Media capability model (Master Prompt § 93)

public struct MediaCapability: Codable, Sendable, Equatable {
    public var canPlay: Bool
    public var canResearch: Bool
    public var canSemanticAnalyze: Bool
    public var canLocateMoments: Bool
    public var canAnalyzeFrames: Bool
    public var canAnalyzeAudio: Bool
    public var canAcquireProductionMedia: Bool
    public var canEdit: Bool
    public var canRender: Bool
    public var canPublishOutput: Bool

    public init(
        canPlay: Bool = false,
        canResearch: Bool = false,
        canSemanticAnalyze: Bool = false,
        canLocateMoments: Bool = false,
        canAnalyzeFrames: Bool = false,
        canAnalyzeAudio: Bool = false,
        canAcquireProductionMedia: Bool = false,
        canEdit: Bool = false,
        canRender: Bool = false,
        canPublishOutput: Bool = false
    ) {
        self.canPlay = canPlay
        self.canResearch = canResearch
        self.canSemanticAnalyze = canSemanticAnalyze
        self.canLocateMoments = canLocateMoments
        self.canAnalyzeFrames = canAnalyzeFrames
        self.canAnalyzeAudio = canAnalyzeAudio
        self.canAcquireProductionMedia = canAcquireProductionMedia
        self.canEdit = canEdit
        self.canRender = canRender
        self.canPublishOutput = canPublishOutput
    }
}

// MARK: - Editing and jobs (Master Prompt §§ 104–111, 174–175)

public enum BlackstockStage: String, Codable, Sendable, CaseIterable {
    case discovery = "DISCOVERY"
    case research = "RESEARCH"
    case analysis = "ANALYSIS"
    case production = "PRODUCTION"
    case preview = "PREVIEW"
    case storyboard = "STORYBOARD"
    case editing = "EDITING"
    case packaging = "PACKAGING"
    case review = "REVIEW"
    case publishing = "PUBLISHING"
    case published = "PUBLISHED"
}

public enum JobControl: String, Codable, Sendable {
    case pausable = "PAUSABLE"
    case checkpointPausable = "CHECKPOINT_PAUSABLE"
    case resumable = "RESUMABLE"
    case cancelOnly = "CANCEL_ONLY"
    case nonInterruptibleShortStep = "NON_INTERRUPTIBLE_SHORT_STEP"

    public var supportsPauseAction: Bool {
        self == .pausable || self == .checkpointPausable
    }

    public var supportsResumeAction: Bool {
        self == .pausable || self == .checkpointPausable || self == .resumable
    }
}

// MARK: - Action broker and publication safety (Master Prompt §§ 139–145, 191–192)

public enum ActionRiskClass: String, Codable, Sendable {
    case readOnly = "READ_ONLY"
    case localDraft = "LOCAL_DRAFT"
    case localReversible = "LOCAL_REVERSIBLE"
    case remoteReversible = "REMOTE_REVERSIBLE"
    case remoteHighImpact = "REMOTE_HIGH_IMPACT"
}

public struct ActionAuthorization: Codable, Sendable, Equatable {
    public let riskClass: ActionRiskClass
    public let deterministicChecksPassed: Bool
    public let userConfirmed: Bool

    public init(riskClass: ActionRiskClass, deterministicChecksPassed: Bool, userConfirmed: Bool) {
        self.riskClass = riskClass
        self.deterministicChecksPassed = deterministicChecksPassed
        self.userConfirmed = userConfirmed
    }

    public var mayExecute: Bool {
        guard deterministicChecksPassed else { return false }
        if riskClass == .remoteHighImpact { return userConfirmed }
        return true
    }
}

public enum PublicationPreflightError: Error, Equatable, Sendable {
    case missingTargetChannel
    case wrongChannel
    case renderNotValidated
    case rightsNotValidated
    case authorizationMissing
    case quotaUnavailable
    case networkUnavailable
}

public struct PublicationPreflightContext: Sendable, Equatable {
    public var projectTargetChannelId: String?
    public var workspaceChannelId: String
    public var authorizedUploadChannelId: String
    public var renderValidated: Bool
    public var rightsValidated: Bool
    public var authorizationAvailable: Bool
    public var quotaAvailable: Bool
    public var networkAvailable: Bool

    public init(
        projectTargetChannelId: String?,
        workspaceChannelId: String,
        authorizedUploadChannelId: String,
        renderValidated: Bool,
        rightsValidated: Bool,
        authorizationAvailable: Bool,
        quotaAvailable: Bool,
        networkAvailable: Bool
    ) {
        self.projectTargetChannelId = projectTargetChannelId
        self.workspaceChannelId = workspaceChannelId
        self.authorizedUploadChannelId = authorizedUploadChannelId
        self.renderValidated = renderValidated
        self.rightsValidated = rightsValidated
        self.authorizationAvailable = authorizationAvailable
        self.quotaAvailable = quotaAvailable
        self.networkAvailable = networkAvailable
    }

    public func validate() throws {
        guard let target = projectTargetChannelId, !target.isEmpty else {
            throw PublicationPreflightError.missingTargetChannel
        }
        guard target == workspaceChannelId && target == authorizedUploadChannelId else {
            throw PublicationPreflightError.wrongChannel
        }
        guard renderValidated else { throw PublicationPreflightError.renderNotValidated }
        guard rightsValidated else { throw PublicationPreflightError.rightsNotValidated }
        guard authorizationAvailable else { throw PublicationPreflightError.authorizationMissing }
        guard quotaAvailable else { throw PublicationPreflightError.quotaUnavailable }
        guard networkAvailable else { throw PublicationPreflightError.networkUnavailable }
    }
}

// MARK: - Data governance (Master Prompt § 194)

public struct ExternalDataGovernance: Codable, Sendable, Equatable {
    public var source: String
    public var authorizationClass: String
    public var retrievedAt: Date
    public var refreshAt: Date?
    public var expiresAt: Date?
    public var retentionPolicy: String
    public var policyVersion: String

    public init(
        source: String,
        authorizationClass: String,
        retrievedAt: Date,
        refreshAt: Date?,
        expiresAt: Date?,
        retentionPolicy: String,
        policyVersion: String
    ) {
        self.source = source
        self.authorizationClass = authorizationClass
        self.retrievedAt = retrievedAt
        self.refreshAt = refreshAt
        self.expiresAt = expiresAt
        self.retentionPolicy = retentionPolicy
        self.policyVersion = policyVersion
    }
}
