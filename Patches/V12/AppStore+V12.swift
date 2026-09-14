import AppKit
import Foundation
import UniformTypeIdentifiers

@MainActor
extension AppStore {
  // MARK: - Blackstock 12 Creator Intelligence

  var v12ActiveChannelID: UUID? {
    get { v12State.activeChannelID ?? ausgewaehlterKanalID ?? liveKanaele.first?.id }
    set {
      v12State.activeChannelID = newValue
      ausgewaehlterKanalID = newValue
      speichern()
    }
  }

  func v12Strategy(for channelID: UUID) -> ChannelStrategyV12 {
    if let strategy = v12State.strategy(for: channelID) { return strategy }
    guard let channel = kanal(fuer: channelID) else {
      return ChannelStrategyV12(
        channelID: channelID,
        primaryTopic: "Kanalthema festlegen",
        audience: "Zielgruppe festlegen",
        positioning: "Positionierung festlegen",
        contentPillars: ["Trend", "Erklärung", "Highlights"],
        shortWeight: 0.62,
        longformWeight: 0.38,
        targetShortSeconds: 42,
        targetLongformSeconds: 300,
        uploadsPerWeek: 7,
        operatingMode: .copilot,
        minimumQualityScore: 88,
        minimumConfidence: 0.78,
        preferredUploadHour: nil,
        learningEnabled: true)
    }
    return CreatorIntelligenceV12Service.shared.defaultStrategy(
      channel: channel,
      profile: channelProfile(for: channelID),
      videos: videos)
  }

  @discardableResult
  func v12EnsureStrategy(for channelID: UUID) -> ChannelStrategyV12 {
    let strategy = v12Strategy(for: channelID)
    if v12State.strategy(for: channelID) == nil {
      v12State.upsertStrategy(strategy)
      speichern()
    }
    return strategy
  }

  func v12StrategySpeichern(_ strategy: ChannelStrategyV12) {
    var normalized = strategy
    normalized.shortWeight = max(0.05, min(0.95, normalized.shortWeight))
    normalized.longformWeight = max(0.05, min(0.95, normalized.longformWeight))
    normalized.targetShortSeconds = max(15, min(180, normalized.targetShortSeconds))
    normalized.targetLongformSeconds = max(120, min(1_200, normalized.targetLongformSeconds))
    normalized.uploadsPerWeek = max(1, min(35, normalized.uploadsPerWeek))
    normalized.minimumQualityScore = max(75, min(99, normalized.minimumQualityScore))
    normalized.minimumConfidence = max(0.50, min(0.99, normalized.minimumConfidence))
    normalized.updatedAt = Date()
    v12State.upsertStrategy(normalized)
    v12State.activeChannelID = normalized.channelID

    if let channelIndex = kanaele.firstIndex(where: { $0.id == normalized.channelID }) {
      kanaele[channelIndex].thema = normalized.primaryTopic
    }
    var profile = channelProfile(for: normalized.channelID)
    profile.customTopics = Array(Set(([normalized.primaryTopic] + normalized.contentPillars).filter { !$0.isEmpty })).sorted()
    profile.desiredFormats = normalized.shortWeight >= normalized.longformWeight
      ? [.short, .longform] : [.longform, .short]
    profile.preferredUploadHour = normalized.preferredUploadHour
    profile.reviewBeforePublish = normalized.operatingMode != .autopilot
    v11State.upsertProfile(profile)
    speichern()
  }


  func v12OAuthDateiAuswaehlen() {
    let panel = NSOpenPanel()
    panel.title = "Google Desktop OAuth auswählen"
    panel.message = "Wähle die JSON-Datei eines Google OAuth Clients vom Typ Desktop-App."
    panel.allowedContentTypes = [.json]
    panel.allowsMultipleSelection = false
    panel.canChooseDirectories = false
    guard panel.runModal() == .OK, let url = panel.url else { return }
    do {
      try youtube.importiereDesktopOAuthDatei(url)
      meldung = "Google Desktop OAuth wurde sicher eingerichtet. Du kannst den Channel jetzt verbinden."
    } catch {
      meldung = error.localizedDescription
    }
  }

  func v12GoogleVerbindungReparieren(channelID: UUID?) async {
    if youtube.oauthKonfigurationsstatus().zustand == .fehlt {
      meldung = "Für diesen Build fehlt noch die Google Desktop OAuth-Konfiguration. Wähle zuerst die OAuth-JSON-Datei aus."
      return
    }
    if googleZugaenge.isEmpty || channelID == nil {
      _ = await googleZugangHinzufuegen()
      return
    }
    if let channelID {
      let health = v12GoogleHealth(channelID: channelID)
      if !health.uploadAuthorized {
        await uploadBerechtigungVerbinden(channelID: channelID)
      }
      await liveDatenAktualisieren()
    }
  }

  func v12GoogleHealth(channelID: UUID?) -> GoogleConnectionHealthV12 {
    let oauth = youtube.oauthKonfigurationsstatus()
    guard let channelID, let channel = kanal(fuer: channelID) else {
      return GoogleConnectionHealthV12(
        oauthConfigured: oauth.zustand == .eingebaut || oauth.zustand == .importiert,
        accountConnected: !googleZugaenge.isEmpty,
        channelConnected: false,
        analyticsAuthorized: false,
        uploadAuthorized: false,
        liveAuthorized: false,
        detail: googleZugaenge.isEmpty ? "Google-Konto noch nicht verbunden" : "YouTube-Kanal auswählen oder synchronisieren")
    }
    let connectionID = channel.verbindungsID
      ?? v11State.channelConnections.first(where: { $0.localChannelID == channelID })?.googleAccountID
    let profile = channelProfile(for: channelID)
    let upload = connectionID.map { youtube.featureAutorisiert(.upload, verbindungID: $0) } ?? profile.uploadAuthorized
    let live = connectionID.map { youtube.featureAutorisiert(.live, verbindungID: $0) } ?? profile.liveAuthorized
    let analytics = profile.analyticsAuthorized || v11State.analyticsDaily.contains { $0.channelID == channelID }
    let connected = channel.youtubeChannelID != nil
    let ready = connected && upload && analytics
    return GoogleConnectionHealthV12(
      oauthConfigured: oauth.zustand == .eingebaut || oauth.zustand == .importiert,
      accountConnected: connectionID != nil,
      channelConnected: connected,
      analyticsAuthorized: analytics,
      uploadAuthorized: upload,
      liveAuthorized: live,
      detail: ready ? "Creator Loop bereit: Lesen, Analytics und Upload sind verbunden." : "Verbindung ist teilweise eingerichtet. Blackstock zeigt die fehlenden Berechtigungen separat an.")
  }

  func v12RankedDecisions(channelID: UUID) -> [TrendDecisionV12] {
    let strategy = v12Strategy(for: channelID)
    return chancen
      .filter { !$0.istDemo && ($0.empfohlenerKanalID == nil || $0.empfohlenerKanalID == channelID) }
      .map { CreatorIntelligenceV12Service.shared.decide(chance: $0, channelID: channelID, strategy: strategy) }
      .filter { $0.trendConfidence >= max(0.30, strategy.minimumConfidence * 0.70) }
      .sorted { lhs, rhs in
        if lhs.opportunityScore == rhs.opportunityScore { return lhs.trendConfidence > rhs.trendConfidence }
        return lhs.opportunityScore > rhs.opportunityScore
      }
  }

  func v12Decision(for chance: Chance, channelID: UUID) -> TrendDecisionV12 {
    let decision = CreatorIntelligenceV12Service.shared.decide(
      chance: chance, channelID: channelID, strategy: v12Strategy(for: channelID))
    v12State.upsertDecision(decision)
    speichern()
    return decision
  }

  @discardableResult
  func v12ProduktionStarten(chance: Chance, channelID: UUID, forcedFormat: VideoFormat? = nil) async -> UUID? {
    let strategy = v12EnsureStrategy(for: channelID)
    var decision = CreatorIntelligenceV12Service.shared.decide(chance: chance, channelID: channelID, strategy: strategy)
    if let forcedFormat {
      decision.recommendedFormat = forcedFormat
      decision.targetDurationSeconds = forcedFormat == .short
        ? strategy.targetShortSeconds : strategy.targetLongformSeconds
    }
    v12State.upsertDecision(decision)
    v12State.activeChannelID = channelID

    var adaptedChance = chance
    adaptedChance.empfohlenerKanalID = channelID
    adaptedChance.empfohleneFormate = [decision.recommendedFormat]
    let mode: ProductionModeV11 = decision.recommendedFormat == .short ? .short : .longform
    let productionID = await v11ProduktionStartenAusChance(
      adaptedChance,
      mode: mode,
      targetDurationSeconds: decision.targetDurationSeconds)

    guard let productionID else {
      speichern()
      return nil
    }
    if let index = produktionen.firstIndex(where: { $0.id == productionID }) {
      if produktionen[index].hook.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        produktionen[index].hook = decision.hookAngle
      }
      produktionen[index].zielDauerSekunden = decision.targetDurationSeconds
      produktionen[index].konfidenz = min(1, (decision.trendConfidence * 0.7) + (decision.sourceConfidence * 0.3))
      produktionen[index].naechsterSchritt = "V12 Creator Loop · Source Analysis / Remix"
      produktionen[index].aktualisiertAm = Date()
    }
    _ = v12QualityAktualisieren(productionID)
    speichern()
    return productionID
  }

  @discardableResult
  func v12QualityAktualisieren(_ productionID: UUID) -> QualityScoreV12? {
    guard let production = produktionen.first(where: { $0.id == productionID }) else { return nil }
    let strategy = v12Strategy(for: production.kanalID)
    let score = CreatorIntelligenceV12Service.shared.qualityScore(
      production: production,
      state: v11State.productionState(for: productionID),
      sources: v11Sources(for: productionID),
      strategy: strategy,
      previousVideos: videos.filter { $0.kanalID == production.kanalID })
    v12State.qualityScores[productionID] = score
    speichern()
    return score
  }

  func v12QualityReady(_ productionID: UUID) -> Bool {
    guard let production = produktionen.first(where: { $0.id == productionID }) else { return false }
    let strategy = v12Strategy(for: production.kanalID)
    let score = v12State.qualityScores[productionID] ?? v12QualityAktualisieren(productionID)
    return score?.isReady(minimum: strategy.minimumQualityScore) == true
  }

  func v12LearningAktualisieren(channelID: UUID) {
    let strategy = v12EnsureStrategy(for: channelID)
    guard strategy.learningEnabled else { return }
    let service = CreatorIntelligenceV12Service.shared
    let records = service.learningRecords(videos: videos, channelID: channelID)
    v12State.learningRecords.removeAll { $0.channelID == channelID }
    v12State.learningRecords.append(contentsOf: records)
    v12State.insights.removeAll { $0.channelID == channelID }
    v12State.insights.append(contentsOf: service.insights(records: records, channelID: channelID))
    v12State.lastLearningRunAt = Date()
    speichern()
  }

  func v12Insights(channelID: UUID) -> [LearningInsightV12] {
    let existing = v12State.insights.filter { $0.channelID == channelID }.sorted { $0.impactScore > $1.impactScore }
    if !existing.isEmpty { return existing }
    let records = CreatorIntelligenceV12Service.shared.learningRecords(videos: videos, channelID: channelID)
    return CreatorIntelligenceV12Service.shared.insights(records: records, channelID: channelID)
  }

  func v12LoopStage(for productionID: UUID?) -> CreatorLoopStage {
    guard let productionID,
      let production = produktionen.first(where: { $0.id == productionID })
    else { return liveKanaele.isEmpty ? .channel : .trend }
    let state = v11Produktion(for: productionID)
    switch state.phase {
    case .draft: return .format
    case .discoveringSources, .analyzingSources, .fetchingMedia: return .source
    case .planning, .editing: return .remix
    case .rendering: return .render
    case .review, .ready: return .quality
    case .uploading, .scheduled: return .publish
    case .published: return .learn
    case .failed: return production.lokaleDatei == nil ? .render : .quality
    }
  }
}
