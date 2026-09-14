import Foundation

// MARK: - Blackstock 12 Creator Operating System

enum CreatorOperatingMode: String, Codable, CaseIterable, Identifiable, Hashable {
  case safe = "Safe"
  case copilot = "Copilot"
  case autopilot = "Autopilot"

  var id: String { rawValue }

  var description: String {
    switch self {
    case .safe: "Blackstock analysiert und produziert, du bestätigst Render und Upload."
    case .copilot: "Blackstock baut das komplette Video und wartet nur auf die finale Freigabe."
    case .autopilot: "Blackstock veröffentlicht nur, wenn Quality-, Rechte- und Confidence-Gates erfüllt sind."
    }
  }
}

enum CreatorLoopStage: String, Codable, CaseIterable, Identifiable, Hashable {
  case channel = "Channel verbinden"
  case strategy = "Channel DNA"
  case trend = "Trend Intelligence"
  case source = "Source Analysis"
  case format = "Format Decision"
  case remix = "Remix Director"
  case quality = "Quality Gate"
  case render = "Render"
  case publish = "Upload"
  case learn = "Performance Learning"

  var id: String { rawValue }

  var symbol: String {
    switch self {
    case .channel: "person.crop.rectangle.stack"
    case .strategy: "scope"
    case .trend: "chart.line.uptrend.xyaxis"
    case .source: "waveform.path.ecg.rectangle"
    case .format: "rectangle.3.group"
    case .remix: "timeline.selection"
    case .quality: "checkmark.shield"
    case .render: "film.stack"
    case .publish: "arrow.up.circle"
    case .learn: "brain.head.profile"
    }
  }
}

struct ChannelStrategyV12: Identifiable, Codable, Hashable {
  var id: UUID { channelID }
  var channelID: UUID
  var primaryTopic: String
  var audience: String
  var positioning: String
  var contentPillars: [String]
  var shortWeight: Double
  var longformWeight: Double
  var targetShortSeconds: Int
  var targetLongformSeconds: Int
  var uploadsPerWeek: Int
  var operatingMode: CreatorOperatingMode
  var minimumQualityScore: Double
  var minimumConfidence: Double
  var preferredUploadHour: Int?
  var learningEnabled: Bool
  var updatedAt: Date = Date()

  var normalizedShortWeight: Double {
    let total = max(0.01, shortWeight + longformWeight)
    return max(0, min(1, shortWeight / total))
  }
}

struct TrendDecisionV12: Identifiable, Codable, Hashable {
  var id: UUID = UUID()
  var channelID: UUID
  var chanceID: UUID
  var opportunityScore: Double
  var recommendedFormat: VideoFormat
  var targetDurationSeconds: Int
  var hookAngle: String
  var reason: String
  var trendConfidence: Double
  var sourceConfidence: Double
  var createdAt: Date = Date()
}

struct QualityScoreV12: Codable, Hashable {
  var hook: Double
  var pacing: Double
  var editQuality: Double
  var channelFit: Double
  var transformation: Double
  var packaging: Double
  var rightsConfidence: Double
  var technical: Double
  var predictedRetention: Double
  var blockingReasons: [String]
  var evaluatedAt: Date = Date()

  var overall: Double {
    let weighted = hook * 0.15 + pacing * 0.13 + editQuality * 0.14 + channelFit * 0.14
      + transformation * 0.14 + packaging * 0.10 + rightsConfidence * 0.10 + technical * 0.10
    return max(0, min(100, weighted))
  }

  func isReady(minimum: Double) -> Bool {
    blockingReasons.isEmpty && overall >= minimum && rightsConfidence >= 80 && technical >= 85
  }
}

enum LearningInsightKind: String, Codable, CaseIterable, Identifiable, Hashable {
  case hook = "Hook"
  case duration = "Videolänge"
  case format = "Format"
  case topic = "Thema"
  case packaging = "Packaging"
  case retention = "Retention"
  case timing = "Uploadzeit"

  var id: String { rawValue }
}

struct LearningInsightV12: Identifiable, Codable, Hashable {
  var id: UUID = UUID()
  var channelID: UUID
  var kind: LearningInsightKind
  var summary: String
  var action: String
  var confidence: Double
  var evidenceCount: Int
  var impactScore: Double
  var updatedAt: Date = Date()
}

struct VideoLearningRecordV12: Identifiable, Codable, Hashable {
  var id: UUID = UUID()
  var channelID: UUID
  var productionID: UUID?
  var youtubeVideoID: String?
  var format: VideoFormat
  var publishedAt: Date
  var views: Int
  var views24h: Int
  var averageViewPercentage: Double
  var thumbnailCTR: Double?
  var subscriberNet: Int
  var engagementRate: Double
  var qualityScore: Double
  var learnedAt: Date = Date()
}

struct GoogleConnectionHealthV12: Hashable {
  var oauthConfigured: Bool
  var accountConnected: Bool
  var channelConnected: Bool
  var analyticsAuthorized: Bool
  var uploadAuthorized: Bool
  var liveAuthorized: Bool
  var detail: String

  var score: Double {
    let flags = [oauthConfigured, accountConnected, channelConnected, analyticsAuthorized, uploadAuthorized]
    return Double(flags.filter { $0 }.count) / Double(flags.count) * 100
  }

  var readyForCreatorLoop: Bool {
    oauthConfigured && accountConnected && channelConnected && analyticsAuthorized && uploadAuthorized
  }
}

struct V12State: Codable, Hashable {
  var schemaVersion: Int = 12
  var activeChannelID: UUID? = nil
  var strategies: [ChannelStrategyV12] = []
  var trendDecisions: [TrendDecisionV12] = []
  var qualityScores: [UUID: QualityScoreV12] = [:]
  var learningRecords: [VideoLearningRecordV12] = []
  var insights: [LearningInsightV12] = []
  var lastLearningRunAt: Date? = nil

  enum CodingKeys: String, CodingKey {
    case schemaVersion, activeChannelID, strategies, trendDecisions, qualityScores
    case learningRecords, insights, lastLearningRunAt
  }

  init() {}

  init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    schemaVersion = try c.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 12
    activeChannelID = try c.decodeIfPresent(UUID.self, forKey: .activeChannelID)
    strategies = try c.decodeIfPresent([ChannelStrategyV12].self, forKey: .strategies) ?? []
    trendDecisions = try c.decodeIfPresent([TrendDecisionV12].self, forKey: .trendDecisions) ?? []
    qualityScores = try c.decodeIfPresent([UUID: QualityScoreV12].self, forKey: .qualityScores) ?? [:]
    learningRecords = try c.decodeIfPresent([VideoLearningRecordV12].self, forKey: .learningRecords) ?? []
    insights = try c.decodeIfPresent([LearningInsightV12].self, forKey: .insights) ?? []
    lastLearningRunAt = try c.decodeIfPresent(Date.self, forKey: .lastLearningRunAt)
  }

  func strategy(for channelID: UUID) -> ChannelStrategyV12? {
    strategies.first { $0.channelID == channelID }
  }

  mutating func upsertStrategy(_ strategy: ChannelStrategyV12) {
    if let index = strategies.firstIndex(where: { $0.channelID == strategy.channelID }) {
      strategies[index] = strategy
    } else {
      strategies.append(strategy)
    }
  }

  mutating func upsertDecision(_ decision: TrendDecisionV12) {
    trendDecisions.removeAll { $0.channelID == decision.channelID && $0.chanceID == decision.chanceID }
    trendDecisions.append(decision)
  }
}
