import Foundation

final class CreatorIntelligenceV12Service {
  static let shared = CreatorIntelligenceV12Service()

  func defaultStrategy(
    channel: Kanal,
    profile: ChannelContentProfile,
    videos: [VideoLeistung]
  ) -> ChannelStrategyV12 {
    let topic = profile.customTopics.first ?? profile.topics.first?.rawValue ?? channel.thema
    let channelVideos = videos.filter { $0.kanalID == channel.id && !$0.istDemo }
    let shortVideos = channelVideos.filter { $0.format == .short }
    let longVideos = channelVideos.filter { $0.format == .longform || $0.format == .serie }
    let shortSignal = performanceSignal(shortVideos)
    let longSignal = performanceSignal(longVideos)
    let total = max(0.01, shortSignal + longSignal)
    let shortWeight = channelVideos.isEmpty ? 0.62 : shortSignal / total
    let longWeight = channelVideos.isEmpty ? 0.38 : longSignal / total

    let pillars = uniqueNonEmpty(
      profile.topics.prefix(3).map(\.rawValue) + profile.customTopics.prefix(3) + [channel.thema]
    )

    return ChannelStrategyV12(
      channelID: channel.id,
      primaryTopic: topic.isEmpty ? "Kanalthema festlegen" : topic,
      audience: "Zuschauer, die schnelle Relevanz und klaren Mehrwert zu \(topic.isEmpty ? channel.name : topic) suchen",
      positioning: "Schnelle Trend-Reaktion mit hochwertigem Remix, klarer Einordnung und wiedererkennbarem Packaging.",
      contentPillars: pillars.isEmpty ? ["Trend", "Erklärung", "Highlights"] : pillars,
      shortWeight: max(0.2, min(0.8, shortWeight)),
      longformWeight: max(0.2, min(0.8, longWeight)),
      targetShortSeconds: 42,
      targetLongformSeconds: 300,
      uploadsPerWeek: max(3, min(14, channelVideos.isEmpty ? 7 : 7)),
      operatingMode: .copilot,
      minimumQualityScore: 88,
      minimumConfidence: 0.78,
      preferredUploadHour: profile.preferredUploadHour,
      learningEnabled: true
    )
  }

  func decide(
    chance: Chance,
    channelID: UUID,
    strategy: ChannelStrategyV12
  ) -> TrendDecisionV12 {
    let format = recommendedFormat(chance: chance, strategy: strategy)
    let duration = format == .short ? strategy.targetShortSeconds : strategy.targetLongformSeconds
    let sourceConfidence = chance.quellenAnzahl > 0
      ? min(1, 0.48 + Double(chance.primaerquellen) * 0.10 + Double(chance.quellenAnzahl) * 0.025)
      : 0.30
    let opportunity = opportunityScore(chance: chance, strategy: strategy)
    let hook = hookAngle(for: chance, format: format)
    let reason = decisionReason(chance: chance, format: format, opportunity: opportunity)

    return TrendDecisionV12(
      channelID: channelID,
      chanceID: chance.id,
      opportunityScore: opportunity,
      recommendedFormat: format,
      targetDurationSeconds: duration,
      hookAngle: hook,
      reason: reason,
      trendConfidence: max(0, min(1, chance.konfidenz)),
      sourceConfidence: sourceConfidence
    )
  }

  func qualityScore(
    production: Produktion,
    state: ProductionV11State?,
    sources: [SourceAsset],
    strategy: ChannelStrategyV12,
    previousVideos: [VideoLeistung]
  ) -> QualityScoreV12 {
    let timeline = state?.timeline
    let segmentCount = timeline?.segments.count ?? 0
    let duration = timeline?.duration ?? Double(production.zielDauerSekunden)
    let desired = Double(production.format == .short ? strategy.targetShortSeconds : strategy.targetLongformSeconds)
    let durationDelta = desired > 0 ? abs(duration - desired) / desired : 0

    let hook = production.hook.trimmingCharacters(in: .whitespacesAndNewlines)
    let hookScore: Double = {
      guard !hook.isEmpty else { return 62 }
      var value = 82.0
      if hook.count >= 18 && hook.count <= 125 { value += 10 }
      if hook.lowercased().hasPrefix("in diesem video") { value -= 10 }
      if hook.contains("?") || hook.contains("!") { value += 3 }
      return clamp(value)
    }()

    let pacing: Double = {
      guard duration > 0 else { return 60 }
      let cutsPerMinute = Double(segmentCount) / max(duration / 60, 0.25)
      let target = production.format == .short ? 12.0 : 6.0
      let distance = abs(cutsPerMinute - target)
      return clamp(96 - distance * 3.4 - durationDelta * 22)
    }()

    let editQuality = clamp(78 + min(16, Double(segmentCount) * 1.8) + (timeline?.captions == true ? 4 : 0))
    let channelFit = clamp(72 + production.konfidenz * 18 + (production.chanceSnapshot?.empfohleneFormate.contains(production.format) == true ? 8 : 0))

    let uniqueSources = Set(timeline?.segments.map(\.sourceAssetID) ?? state?.sourceAssetIDs ?? []).count
    let transformation = clamp(
      66 + min(16, Double(segmentCount) * 2.0) + min(8, Double(uniqueSources) * 2.5)
        + (timeline?.captions == true ? 4 : 0)
    )

    var packaging = 72.0
    if production.arbeitstitel.count >= 24 && production.arbeitstitel.count <= 75 { packaging += 10 }
    if !(production.thumbnailIdee.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) { packaging += 8 }
    if !(production.beschreibung ?? "").isEmpty { packaging += 5 }
    packaging = clamp(packaging)

    let usedIDs = Set(timeline?.segments.map(\.sourceAssetID) ?? state?.sourceAssetIDs ?? [])
    let usedSources = sources.filter { usedIDs.contains($0.id) }
    var blockers: [String] = []
    if usedSources.isEmpty { blockers.append("Keine verifizierte Schnittquelle in der Timeline") }
    let blockedSources = usedSources.filter { !$0.canPublish || !$0.canEdit || $0.isExpired }
    if !blockedSources.isEmpty { blockers.append("Mindestens eine verwendete Quelle ist nicht vollständig für Bearbeitung/Upload freigegeben") }
    let rights = usedSources.isEmpty ? 45.0 : (blockedSources.isEmpty ? 100.0 : 48.0)

    let technical: Double = {
      guard let validation = state?.renderValidation else { return state?.phase == .rendering ? 78 : 68 }
      var score = 74.0
      if validation.hasVideo { score += 10 }
      if validation.hasAudio { score += 8 }
      if validation.matches(production.format) { score += 8 }
      return clamp(score)
    }()
    if let validation = state?.renderValidation, !validation.matches(production.format) {
      blockers.append("Render-Seitenverhältnis passt nicht zum gewählten Format")
    }

    let retentionBaseline = retentionBaseline(for: production.format, videos: previousVideos)
    let predictedRetention = clamp(retentionBaseline + (hookScore - 80) * 0.17 + (pacing - 80) * 0.12)

    return QualityScoreV12(
      hook: hookScore,
      pacing: pacing,
      editQuality: editQuality,
      channelFit: channelFit,
      transformation: transformation,
      packaging: packaging,
      rightsConfidence: rights,
      technical: technical,
      predictedRetention: predictedRetention,
      blockingReasons: blockers
    )
  }

  func learningRecords(videos: [VideoLeistung], channelID: UUID) -> [VideoLearningRecordV12] {
    videos.filter { $0.kanalID == channelID && !$0.istDemo }.map { video in
      let interactions = video.likes + video.kommentare + video.shares
      let engagement = video.views > 0 ? Double(interactions) / Double(video.views) * 100 : 0
      return VideoLearningRecordV12(
        channelID: channelID,
        productionID: nil,
        youtubeVideoID: video.youtubeVideoID,
        format: video.format,
        publishedAt: video.veroeffentlichtAm,
        views: video.views,
        views24h: video.views24h,
        averageViewPercentage: video.durchschnittlicheWiedergabeProzent,
        thumbnailCTR: video.thumbnailCTR,
        subscriberNet: video.abonnentenGewonnen - video.abonnentenVerloren,
        engagementRate: engagement,
        qualityScore: video.qualitaetsScore
      )
    }
  }

  func insights(records: [VideoLearningRecordV12], channelID: UUID) -> [LearningInsightV12] {
    guard !records.isEmpty else {
      return [
        LearningInsightV12(
          channelID: channelID,
          kind: .retention,
          summary: "Noch keine belastbare Performance-Historie",
          action: "Die ersten Uploads sammeln. Blackstock passt Trend- und Formatentscheidungen danach automatisch an.",
          confidence: 0.35,
          evidenceCount: 0,
          impactScore: 65)
      ]
    }

    var result: [LearningInsightV12] = []
    let shorts = records.filter { $0.format == .short }
    let longs = records.filter { $0.format == .longform || $0.format == .serie }
    if !shorts.isEmpty || !longs.isEmpty {
      let shortPerf = performanceSignal(shorts)
      let longPerf = performanceSignal(longs)
      let winner: VideoFormat = shortPerf >= longPerf ? .short : .longform
      let evidence = winner == .short ? shorts.count : longs.count
      result.append(
        LearningInsightV12(
          channelID: channelID,
          kind: .format,
          summary: "\(winner.rawValue) liefert aktuell das stärkere Performance-Signal",
          action: winner == .short
            ? "Trend-Chancen zuerst als Short testen; starke Gewinner danach in Longform ausbauen."
            : "Starke Trends bevorzugt als 3–5-Minuten-Video ausbauen; Shorts als Hook/Distribution nutzen.",
          confidence: confidence(evidence),
          evidenceCount: evidence,
          impactScore: 92))
    }

    let avgRetention = records.map(\.averageViewPercentage).average
    result.append(
      LearningInsightV12(
        channelID: channelID,
        kind: .retention,
        summary: String(format: "Ø Wiedergabe %.1f %%", avgRetention),
        action: avgRetention < 55
          ? "Hooks kürzer machen, tote Zeit entfernen und früher zum stärksten Moment schneiden."
          : "Retention ist solide; erfolgreiche Schnittmuster für die nächsten Remixes wiederverwenden.",
        confidence: confidence(records.count),
        evidenceCount: records.count,
        impactScore: avgRetention < 55 ? 96 : 82))

    let ctrValues = records.compactMap(\.thumbnailCTR)
    if !ctrValues.isEmpty {
      let avgCTR = ctrValues.average
      result.append(
        LearningInsightV12(
          channelID: channelID,
          kind: .packaging,
          summary: String(format: "Ø Thumbnail CTR %.1f %%", avgCTR),
          action: avgCTR < 5
            ? "Titel/Thumbnail als eigenes Experiment behandeln; weniger Text, stärkerer visueller Konflikt."
            : "Packaging-Muster mit hoher CTR als Vorlage für ähnliche Trends speichern.",
          confidence: confidence(ctrValues.count),
          evidenceCount: ctrValues.count,
          impactScore: avgCTR < 5 ? 90 : 76))
    }

    let subscriberRate = records.reduce(0) { $0 + $1.subscriberNet }
    result.append(
      LearningInsightV12(
        channelID: channelID,
        kind: .topic,
        summary: subscriberRate >= 0 ? "+\(subscriberRate) Netto-Abos aus synchronisierten Videos" : "\(subscriberRate) Netto-Abos",
        action: "Trends nicht nur nach Views bewerten, sondern Themen mit überdurchschnittlichem Abo-Impact höher ranken.",
        confidence: confidence(records.count),
        evidenceCount: records.count,
        impactScore: 84))

    return result.sorted { $0.impactScore > $1.impactScore }
  }

  private func recommendedFormat(chance: Chance, strategy: ChannelStrategyV12) -> VideoFormat {
    let shortRecommended = chance.empfohleneFormate.contains(.short)
    let longRecommended = chance.empfohleneFormate.contains(.longform) || chance.empfohleneFormate.contains(.serie)
    if shortRecommended && !longRecommended { return .short }
    if longRecommended && !shortRecommended { return .longform }

    let fastTrend = chance.trendHalbwertszeitStunden > 0 && chance.trendHalbwertszeitStunden < 30
    let viral = chance.viralitaetsWahrscheinlichkeit >= 0.68 || chance.momentum >= 70
    if fastTrend || viral { return .short }
    return strategy.normalizedShortWeight >= 0.58 ? .short : .longform
  }

  private func opportunityScore(chance: Chance, strategy: ChannelStrategyV12) -> Double {
    let speed = min(100, max(0, chance.trendScore * 0.65 + chance.momentum * 0.35))
    let demand = chance.nachfrageScore > 0 ? chance.nachfrageScore : chance.trendScore
    let gap = chance.contentGapScore > 0 ? chance.contentGapScore : max(0, 100 - chance.wettbewerbScore)
    let confidence = max(0, min(100, chance.konfidenz * 100))
    let quality = chance.qualitaetsPotenzial
    let formatBias = strategy.normalizedShortWeight >= 0.55 ? 4.0 : 2.0
    return clamp(speed * 0.24 + demand * 0.20 + gap * 0.16 + confidence * 0.16 + quality * 0.20 + formatBias)
  }

  private func hookAngle(for chance: Chance, format: VideoFormat) -> String {
    if format == .short {
      return "Stärksten Moment sofort zeigen → Kontext in einem Satz → schnelle Payoff-Sequenz"
    }
    return "Cold Open mit stärkstem Moment → Warum der Trend gerade explodiert → Highlights → klare Einordnung"
  }

  private func decisionReason(chance: Chance, format: VideoFormat, opportunity: Double) -> String {
    let phase = chance.phase.rawValue
    return "Opportunity \(Int(opportunity))/100 · \(phase) · Momentum \(Int(chance.momentum)) · als \(format.rawValue) passt die Trendgeschwindigkeit am besten zur Channel-DNA."
  }

  private func retentionBaseline(for format: VideoFormat, videos: [VideoLeistung]) -> Double {
    let matching = videos.filter { $0.format == format && $0.durchschnittlicheWiedergabeProzent > 0 }
    if !matching.isEmpty { return matching.map(\.durchschnittlicheWiedergabeProzent).average }
    return format == .short ? 72 : 54
  }

  private func performanceSignal(_ videos: [VideoLeistung]) -> Double {
    guard !videos.isEmpty else { return 1 }
    let viewSignal = videos.map { log10(Double(max(1, $0.views24h)) + 10) }.average * 20
    let retention = videos.map(\.durchschnittlicheWiedergabeProzent).average
    let subs = videos.map { Double($0.abonnentenGewonnen - $0.abonnentenVerloren) }.average
    return max(1, viewSignal * 0.45 + retention * 0.45 + max(0, subs) * 0.10)
  }

  private func performanceSignal(_ records: [VideoLearningRecordV12]) -> Double {
    guard !records.isEmpty else { return 0 }
    let viewSignal = records.map { log10(Double(max(1, $0.views24h)) + 10) }.average * 20
    let retention = records.map(\.averageViewPercentage).average
    let engagement = records.map(\.engagementRate).average * 5
    return viewSignal * 0.45 + retention * 0.45 + engagement * 0.10
  }

  private func confidence(_ count: Int) -> Double {
    min(0.96, 0.40 + Double(max(0, count)) * 0.07)
  }

  private func uniqueNonEmpty(_ values: [String]) -> [String] {
    var seen = Set<String>()
    return values.compactMap { raw in
      let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !value.isEmpty else { return nil }
      let key = value.lowercased()
      guard seen.insert(key).inserted else { return nil }
      return value
    }
  }

  private func clamp(_ value: Double) -> Double { max(0, min(100, value)) }
}

private extension Array where Element == Double {
  var average: Double {
    guard !isEmpty else { return 0 }
    return reduce(0, +) / Double(count)
  }
}
