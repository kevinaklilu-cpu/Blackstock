import Foundation

@main
struct V12CoreTests {
  struct Failure: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
  }

  static func main() throws {
    try v12StatePersistsAlongsideLegacyEnvelope()
    try trendDecisionPrefersFastTrendAsShort()
    try fiveMinuteTargetIsHonoredByPlanner()
    try qualityGateBlocksUnresolvedSources()
    try learningProducesActionableInsights()
    print("BLACKSTOCK_V12_CORE_TESTS_OK")
  }

  static func v12StatePersistsAlongsideLegacyEnvelope() throws {
    let channelID = UUID()
    var v12 = V12State()
    v12.activeChannelID = channelID
    v12.upsertStrategy(ChannelStrategyV12(
      channelID: channelID,
      primaryTopic: "Tech",
      audience: "Tech Zuschauer",
      positioning: "Schnell und hochwertig",
      contentPillars: ["AI", "Hardware"],
      shortWeight: 0.6,
      longformWeight: 0.4,
      targetShortSeconds: 40,
      targetLongformSeconds: 300,
      uploadsPerWeek: 7,
      operatingMode: .copilot,
      minimumQualityScore: 88,
      minimumConfidence: 0.78,
      preferredUploadHour: 18,
      learningEnabled: true))
    let state = AppZustand(
      onboardingAbgeschlossen: true,
      demoModus: false,
      ausgewaehltesZiel: .command,
      kanaele: [],
      chancen: [],
      produktionen: [],
      videos: [],
      provider: [],
      v11: V11State(),
      v12: v12)
    let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
    let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
    let decoded = try decoder.decode(AppZustand.self, from: encoder.encode(state))
    guard decoded.v12?.activeChannelID == channelID else { throw Failure("V12 active channel wurde nicht persistiert") }
    guard decoded.v12?.strategies.first?.targetLongformSeconds == 300 else { throw Failure("V12 strategy wurde nicht persistiert") }
  }

  static func trendDecisionPrefersFastTrendAsShort() throws {
    let channelID = UUID()
    let q = Qualitaetsprofil(story: 0, hook: 0, visuals: 0, schnitt: 0, stimme: 0, audio: 0, thumbnail: 0, titel: 0, originalitaet: 0, fakten: 0, rechte: 0, policy: 0, technisch: 0)
    _ = q
    let chance = Chance(
      titel: "Breaking Trend",
      thema: "Tech",
      empfohlenerKanalID: channelID,
      trendScore: 91,
      qualitaetsPotenzial: 88,
      abonnentenPotenzial: 80,
      viralitaetsWahrscheinlichkeit: 0.84,
      konfidenz: 0.92,
      risiko: .niedrig,
      quellenAnzahl: 5,
      primaerquellen: 2,
      widersprueche: 0,
      trendHalbwertszeitStunden: 12,
      empfohleneFormate: [.short, .longform],
      begruendung: "schnell",
      entdecktAm: Date(),
      momentum: 94,
      nachfrageScore: 90,
      wettbewerbScore: 40,
      contentGapScore: 82,
      umsatzPotenzial: 60,
      evergreenScore: 25,
      phase: .beschleunigend)
    let strategy = ChannelStrategyV12(
      channelID: channelID, primaryTopic: "Tech", audience: "Tech", positioning: "Fast",
      contentPillars: ["AI"], shortWeight: 0.5, longformWeight: 0.5,
      targetShortSeconds: 42, targetLongformSeconds: 300, uploadsPerWeek: 7,
      operatingMode: .copilot, minimumQualityScore: 88, minimumConfidence: 0.75,
      preferredUploadHour: nil, learningEnabled: true)
    let decision = CreatorIntelligenceV12Service.shared.decide(chance: chance, channelID: channelID, strategy: strategy)
    guard decision.recommendedFormat == .short else { throw Failure("Schneller Trend wurde nicht als Short priorisiert") }
    guard decision.targetDurationSeconds == 42 else { throw Failure("Short-Zieldauer stimmt nicht") }
    guard decision.opportunityScore >= 70 else { throw Failure("Opportunity Score ist für starken Trend zu niedrig") }
  }

  static func fiveMinuteTargetIsHonoredByPlanner() throws {
    let asset = SourceAsset(
      provider: .directHTTPS,
      remoteURL: "https://example.com/a.mp4",
      title: "Long source",
      duration: 700,
      licenseType: "User-owned media",
      rightsStatus: .owned,
      allowedUses: [.edit, .publish],
      channelOwnership: true,
      transcript: String(repeating: "wichtiger moment überraschung kontext erklärung ", count: 60))
    let timeline = try RemixPlannerService().plan(
      sources: [asset],
      mode: .longform,
      requestedFormat: .longform,
      targetDuration: 300)
    guard timeline.duration <= 301 else { throw Failure("Planner überschreitet 5-Minuten-Ziel") }
    guard timeline.duration > 0 else { throw Failure("Planner hat keine Timeline erzeugt") }
  }

  static func qualityGateBlocksUnresolvedSources() throws {
    let channelID = UUID()
    let quality = Qualitaetsprofil(story: 0, hook: 0, visuals: 0, schnitt: 0, stimme: 0, audio: 0, thumbnail: 0, titel: 0, originalitaet: 0, fakten: 0, rechte: 0, policy: 0, technisch: 0)
    var production = Produktion(
      kanalID: channelID,
      chanceID: nil,
      arbeitstitel: "Starker Titel für den Trend",
      format: .short,
      status: .qualitaet,
      erstelltAm: Date(),
      geplantFuer: nil,
      zielDauerSekunden: 42,
      skript: "",
      hook: "Das ist der Moment, den fast alle übersehen!",
      thumbnailIdee: "Moment",
      voiceDirection: "",
      storyboardNotizen: "",
      qualitaet: quality,
      konfidenz: 0.9,
      erwarteteViews24h: 0,
      erwarteteAbonnenten: 0,
      erwarteterUmsatz: 0)
    production.beschreibung = "Beschreibung"
    let unknown = SourceAsset(
      provider: .youtubeReference,
      providerAssetID: "abc",
      remoteURL: nil,
      title: "Trend reference",
      duration: 60,
      rightsStatus: .unknown,
      allowedUses: [])
    let timeline = RemixTimeline(
      format: .short,
      duration: 30,
      segments: [RemixSegment(sourceAssetID: unknown.id, startTime: 0, endTime: 30, cropMode: .smartReframe, order: 0)],
      captions: true)
    let state = ProductionV11State(productionID: production.id, mode: .short, phase: .review, sourceAssetIDs: [unknown.id], timeline: timeline)
    let strategy = ChannelStrategyV12(
      channelID: channelID, primaryTopic: "Tech", audience: "Tech", positioning: "Fast",
      contentPillars: ["AI"], shortWeight: 0.6, longformWeight: 0.4,
      targetShortSeconds: 42, targetLongformSeconds: 300, uploadsPerWeek: 7,
      operatingMode: .autopilot, minimumQualityScore: 88, minimumConfidence: 0.75,
      preferredUploadHour: nil, learningEnabled: true)
    let score = CreatorIntelligenceV12Service.shared.qualityScore(
      production: production, state: state, sources: [unknown], strategy: strategy, previousVideos: [])
    guard !score.blockingReasons.isEmpty else { throw Failure("Ungeklärte Quelle muss V12 Quality Gate blockieren") }
    guard !score.isReady(minimum: 88) else { throw Failure("Ungeklärte Quelle darf nicht Autopilot-ready sein") }
  }

  static func learningProducesActionableInsights() throws {
    let channelID = UUID()
    let records = [
      VideoLearningRecordV12(channelID: channelID, productionID: nil, youtubeVideoID: "1", format: .short, publishedAt: Date(), views: 10_000, views24h: 7_000, averageViewPercentage: 78, thumbnailCTR: 6.5, subscriberNet: 35, engagementRate: 5.2, qualityScore: 91),
      VideoLearningRecordV12(channelID: channelID, productionID: nil, youtubeVideoID: "2", format: .short, publishedAt: Date(), views: 8_000, views24h: 5_000, averageViewPercentage: 73, thumbnailCTR: 5.8, subscriberNet: 22, engagementRate: 4.9, qualityScore: 89),
      VideoLearningRecordV12(channelID: channelID, productionID: nil, youtubeVideoID: "3", format: .longform, publishedAt: Date(), views: 2_000, views24h: 900, averageViewPercentage: 41, thumbnailCTR: 3.2, subscriberNet: 5, engagementRate: 2.1, qualityScore: 82),
    ]
    let insights = CreatorIntelligenceV12Service.shared.insights(records: records, channelID: channelID)
    guard insights.contains(where: { $0.kind == .format }) else { throw Failure("Format-Learning fehlt") }
    guard insights.contains(where: { $0.kind == .retention }) else { throw Failure("Retention-Learning fehlt") }
  }
}
