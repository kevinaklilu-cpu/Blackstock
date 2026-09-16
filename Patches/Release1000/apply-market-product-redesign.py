from pathlib import Path

ROOT = Path.cwd()


def replace_all(path: Path, old: str, new: str) -> None:
    text = path.read_text()
    if old in text:
        path.write_text(text.replace(old, new))


# ---------------------------------------------------------------------------
# Dashboard: fast, action-oriented, no pseudo scores, no file-rights workflow.
# ---------------------------------------------------------------------------
dashboard = ROOT / "Sources/Blackstock/Views/CreatorOS1000View.swift"
dashboard.write_text(r'''import SwiftUI

struct CreatorOS1000View: View {
  @EnvironmentObject private var store: AppStore
  @State private var selectedChannelID: UUID?
  @State private var missions: [CreatorMission1000] = []
  @State private var refreshing = false

  private var selectedChannel: Kanal? { selectedChannelID.flatMap { store.kanal(fuer: $0) } }

  private var channelProductions: [Produktion] {
    guard let selectedChannelID else { return [] }
    return store.produktionen
      .filter { $0.kanalID == selectedChannelID }
      .sorted { ($0.aktualisiertAm ?? $0.erstelltAm) > ($1.aktualisiertAm ?? $1.erstelltAm) }
  }

  private var activeProduction: Produktion? {
    channelProductions.first(where: { store.v11Produktion(for: $0.id).progress < 0.99 })
      ?? channelProductions.first
  }

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 18) {
        PageHeader(
          titel: "Dashboard",
          untertitel: "Was jetzt wichtig ist – klar priorisiert, ohne Scores und ohne Umwege.",
          trailing: AnyView(channelPicker))

        if selectedChannel == nil {
          EmptyState(
            symbol: "person.crop.rectangle.badge.plus",
            titel: "YouTube-Kanal verbinden",
            text: "Danach richtet Blackstock Trends, Produktionen und Analytics automatisch auf deinen Kanal aus.",
            button: "Kanal verbinden") { store.ausgewaehltesZiel = .konten }
        } else {
          primaryActionCard
          if !channelProductions.isEmpty { inProgressCard }
          performanceCard
        }
      }
      .padding(26)
    }
    .onAppear {
      if selectedChannelID == nil {
        selectedChannelID = store.v12ActiveChannelID ?? store.liveKanaele.first?.id
      }
      syncChannelAndReload()
    }
    .onChange(of: selectedChannelID) { _ in syncChannelAndReload() }
    .onChange(of: store.chancen.count) { _ in reloadMissions() }
    .onChange(of: store.produktionen.count) { _ in reloadMissions() }
  }

  private var channelPicker: some View {
    Picker("Kanal", selection: $selectedChannelID) {
      Text("Kanal auswählen").tag(UUID?.none)
      ForEach(store.liveKanaele) { channel in Text(channel.name).tag(Optional(channel.id)) }
    }
    .frame(width: 230)
  }

  @ViewBuilder
  private var primaryActionCard: some View {
    if let production = activeProduction, store.v11Produktion(for: production.id).progress < 0.99 {
      VStack(alignment: .leading, spacing: 12) {
        Label("WEITERARBEITEN", systemImage: "arrow.right.circle.fill")
          .font(.system(size: 9, weight: .bold)).tracking(1.1).foregroundStyle(Color.bsRed)
        Text(production.arbeitstitel)
          .font(.system(size: 21, weight: .semibold)).foregroundStyle(Color.bsText).lineLimit(2)
        Text(production.naechsterSchritt.isEmpty ? production.status.rawValue : production.naechsterSchritt)
          .font(.system(size: 10)).foregroundStyle(Color.bsMuted).lineLimit(2)
        BlackstockFortschritt(wert: store.v11Produktion(for: production.id).progress, farbe: .bsRed)
          .frame(maxWidth: 300)
        HStack {
          Button {
            store.ausgewaehlteProduktionID = production.id
            store.ausgewaehltesZiel = .produktionen
          } label: { Label("Projekt öffnen", systemImage: "film.stack") }
            .buttonStyle(.borderedProminent).tint(Color.bsRed).foregroundStyle(.white)
          Spacer()
          connectionStatus
        }
      }
      .blackstockCard(18, elevated: true)
    } else if let mission = missions.first {
      VStack(alignment: .leading, spacing: 12) {
        Label("JETZT RELEVANT", systemImage: "sparkles.tv.fill")
          .font(.system(size: 9, weight: .bold)).tracking(1.1).foregroundStyle(Color.bsRed)
        Text(mission.title)
          .font(.system(size: 21, weight: .semibold)).foregroundStyle(Color.bsText).lineLimit(2)
        HStack(spacing: 8) {
          Label(mission.formatLabel, systemImage: mission.format == .short ? "rectangle.portrait" : "rectangle")
          Text("·")
          Label(mission.durationLabel, systemImage: "clock")
        }
        .font(.system(size: 9.5, weight: .medium)).foregroundStyle(Color.bsMuted)
        Text(mission.reason)
          .font(.system(size: 10)).foregroundStyle(Color.bsMuted).lineLimit(3)
        HStack {
          Button { store.ausgewaehltesZiel = .chancen } label: {
            Label("Trend öffnen", systemImage: "play.rectangle.fill")
          }
          .buttonStyle(.borderedProminent).tint(Color.bsRed).foregroundStyle(.white)
          Button { Task { await refreshTrends() } } label: {
            if refreshing { ProgressView().controlSize(.small) }
            else { Label("Aktualisieren", systemImage: "arrow.clockwise") }
          }
          .buttonStyle(.bordered).disabled(refreshing || store.istBeschaeftigt)
          Spacer()
          connectionStatus
        }
      }
      .blackstockCard(18, elevated: true)
    } else {
      VStack(alignment: .leading, spacing: 12) {
        Label("NÄCHSTER SCHRITT", systemImage: "sparkles")
          .font(.system(size: 9, weight: .bold)).tracking(1.1).foregroundStyle(Color.bsRed)
        Text("Aktuelle Trends für deinen Kanal laden")
          .font(.system(size: 21, weight: .semibold)).foregroundStyle(Color.bsText)
        Text("Blackstock sucht neue YouTube-Videos und sortiert sie nach Relevanz für deinen Kanal. Die Analyse erscheint erst dort, wo du sie brauchst.")
          .font(.system(size: 10)).foregroundStyle(Color.bsMuted)
        HStack {
          Button { Task { await refreshTrends() } } label: {
            if refreshing { ProgressView().controlSize(.small) }
            else { Label("Trends laden", systemImage: "arrow.clockwise") }
          }
          .buttonStyle(.borderedProminent).tint(Color.bsRed).foregroundStyle(.white)
          Spacer()
          connectionStatus
        }
      }
      .blackstockCard(18, elevated: true)
    }
  }

  private var connectionStatus: some View {
    StatusPunkt(text: "YouTube verbunden", farbe: .bsGreen)
  }

  private var inProgressCard: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack {
        AbschnittTitel(titel: "In Arbeit", untertitel: "Deine zuletzt bearbeiteten Projekte")
        Spacer()
        Button("Alle öffnen") { store.ausgewaehltesZiel = .produktionen }
          .buttonStyle(.bordered).controlSize(.small)
      }
      ForEach(Array(channelProductions.prefix(3))) { production in
        Button {
          store.ausgewaehlteProduktionID = production.id
          store.ausgewaehltesZiel = .produktionen
        } label: {
          HStack(spacing: 11) {
            Image(systemName: production.format == .short ? "rectangle.portrait.fill" : "rectangle.fill")
              .foregroundStyle(Color.bsRed).frame(width: 24)
            VStack(alignment: .leading, spacing: 3) {
              Text(production.arbeitstitel)
                .font(.system(size: 10.5, weight: .semibold)).foregroundStyle(Color.bsText).lineLimit(1)
              Text(production.naechsterSchritt.isEmpty ? production.status.rawValue : production.naechsterSchritt)
                .font(.system(size: 8.5)).foregroundStyle(Color.bsMuted).lineLimit(1)
            }
            Spacer()
            BlackstockFortschritt(wert: store.v11Produktion(for: production.id).progress, farbe: .bsRed)
              .frame(width: 120)
            Image(systemName: "chevron.right").font(.system(size: 9, weight: .semibold)).foregroundStyle(Color.bsMuted2)
          }
          .padding(.vertical, 5)
        }
        .buttonStyle(.plain)
      }
    }
    .blackstockCard(16)
  }

  private var performanceCard: some View {
    let insights = store.blackstockLearningInsights(channelID: selectedChannelID)
    return VStack(alignment: .leading, spacing: 10) {
      HStack {
        AbschnittTitel(titel: "Was funktioniert", untertitel: "Lernsignale aus deinen veröffentlichten Videos")
        Spacer()
        Button("Analytics öffnen") { store.ausgewaehltesZiel = .wachstum }
          .buttonStyle(.bordered).controlSize(.small)
      }
      if insights.isEmpty {
        Text("Sobald veröffentlichte Videos Daten liefern, zeigt Blackstock hier nur die wichtigsten verwertbaren Erkenntnisse.")
          .font(.system(size: 10)).foregroundStyle(Color.bsMuted)
      } else {
        ForEach(Array(insights.prefix(3))) { insight in
          HStack(alignment: .top, spacing: 10) {
            Image(systemName: "chart.line.uptrend.xyaxis").foregroundStyle(Color.bsRed).frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
              Text(insight.title).font(.system(size: 10, weight: .semibold)).foregroundStyle(Color.bsText)
              Text(insight.detail).font(.system(size: 8.8)).foregroundStyle(Color.bsMuted).lineLimit(2)
            }
            Spacer()
            if !insight.value.isEmpty {
              Text(insight.value).font(.system(size: 9.5, weight: .semibold)).foregroundStyle(Color.bsText)
            }
          }
        }
      }
    }
    .blackstockCard(16)
  }

  private func syncChannelAndReload() {
    store.v12ActiveChannelID = selectedChannelID
    reloadMissions()
  }

  private func reloadMissions() {
    guard let selectedChannelID else {
      missions = []
      return
    }
    missions = store.v1000Missions(channelID: selectedChannelID)
  }

  private func refreshTrends() async {
    guard !refreshing else { return }
    refreshing = true
    _ = await store.chancenAktualisieren()
    reloadMissions()
    refreshing = false
  }
}
''')

# ---------------------------------------------------------------------------
# Trends: cache expensive ranking, include Shorts as signals, no fake score UI.
# ---------------------------------------------------------------------------
trends = ROOT / "Sources/Blackstock/Views/ChancenView.swift"
text = trends.read_text()

old_duration = '''private enum TrendSourceDurationFilter: String, CaseIterable, Identifiable {
  case alle = "Alle Längen"
  case fourToTen = "4–10 Min."
  case tenToTwenty = "10–20 Min."
  case twentyToSixty = "20–60 Min."
  case sixtyPlus = "60+ Min."
  var id: String { rawValue }

  func matches(_ seconds: Double?) -> Bool {
    guard let seconds, seconds >= 240 else { return false }
    switch self {
    case .alle: return true
    case .fourToTen: return seconds < 600
    case .tenToTwenty: return seconds >= 600 && seconds < 1_200
    case .twentyToSixty: return seconds >= 1_200 && seconds < 3_600
    case .sixtyPlus: return seconds >= 3_600
    }
  }
}'''
new_duration = '''private enum TrendSourceDurationFilter: String, CaseIterable, Identifiable {
  case alle = "Alle Längen"
  case shorts = "Shorts < 1 Min."
  case oneToFour = "1–4 Min."
  case fourToTen = "4–10 Min."
  case tenToTwenty = "10–20 Min."
  case twentyToSixty = "20–60 Min."
  case sixtyPlus = "60+ Min."
  var id: String { rawValue }

  func matches(_ seconds: Double?) -> Bool {
    guard let seconds else { return self == .alle }
    switch self {
    case .alle: return true
    case .shorts: return seconds < 60
    case .oneToFour: return seconds >= 60 && seconds < 240
    case .fourToTen: return seconds >= 240 && seconds < 600
    case .tenToTwenty: return seconds >= 600 && seconds < 1_200
    case .twentyToSixty: return seconds >= 1_200 && seconds < 3_600
    case .sixtyPlus: return seconds >= 3_600
    }
  }
}'''
if old_duration not in text:
    raise SystemExit("BLACKSTOCK_1_REDESIGN: duration filter block missing")
text = text.replace(old_duration, new_duration, 1)
text = text.replace(
    "  @State private var selectedChanceID: UUID?\n",
    "  @State private var selectedChanceID: UUID?\n  @State private var learnedRank: [UUID: Double] = [:]\n",
    1)

start = text.index("  private var filtered: [Chance] {")
end = text.index("\n  private var selectedChance: Chance? {", start)
new_filtered = r'''  private var filtered: [Chance] {
    let query = suche.trimmingCharacters(in: .whitespacesAndNewlines)
      .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)

    let items = store.chancen.filter { chance in
      guard chance.youtubeVideoID != nil || chance.quellenSchluessel?.hasPrefix("youtube:") == true else { return false }
      if let videoID = chance.youtubeVideoID, store.v100State.hiddenVideoIDs.contains(videoID) { return false }
      guard durationFilter.matches(chance.youtubeDurationSeconds) else { return false }
      guard ageFilter.matches(chance.youtubePublishedAt) else { return false }
      if let videoID = chance.youtubeVideoID {
        switch libraryFilter {
        case .alle: break
        case .gespeichert: guard store.v100State.shortlistedVideoIDs.contains(videoID) else { return false }
        case .ungesehen: guard !store.v100State.watchedVideoIDs.contains(videoID) else { return false }
        }
      }
      let content = "\(chance.titel) \(chance.thema) \(chance.youtubeChannelTitle ?? "")"
        .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
      let inferred = TopicTaxonomy.infer(from: "\(chance.thema) \(chance.titel)")
      let lockedTopic = selectedChannelID.flatMap(store.blackstockTopic(for:))
      let categoryMatches = lockedTopic.map { wanted in
        inferred == wanted || chance.thema.localizedCaseInsensitiveContains(wanted.rawValue)
          || wanted.searchTerms.contains(where: { content.localizedCaseInsensitiveContains($0) })
      } ?? true
      let channelMatches = selectedChannelID.map { id in
        chance.empfohlenerKanalID == nil || chance.empfohlenerKanalID == id
      } ?? true
      return (query.isEmpty || content.contains(query)) && categoryMatches && channelMatches
    }

    return items.sorted { lhs, rhs in
      switch sortierung {
      case .fuerDich:
        let left = learnedRank[lhs.id] ?? lhs.trendScore
        let right = learnedRank[rhs.id] ?? rhs.trendScore
        if left == right { return (lhs.youtubeViews ?? 0) > (rhs.youtubeViews ?? 0) }
        return left > right
      case .trend:
        if lhs.trendScore == rhs.trendScore { return (lhs.youtubeViews ?? 0) > (rhs.youtubeViews ?? 0) }
        return lhs.trendScore > rhs.trendScore
      case .neu:
        return (lhs.youtubePublishedAt ?? lhs.entdecktAm) > (rhs.youtubePublishedAt ?? rhs.entdecktAm)
      case .views:
        return (lhs.youtubeViews ?? 0) > (rhs.youtubeViews ?? 0)
      }
    }
  }

  private func recomputeLearnedRank() {
    guard let channelID = selectedChannelID else {
      learnedRank = [:]
      return
    }
    let items = store.chancen.filter { chance in
      guard chance.youtubeVideoID != nil || chance.quellenSchluessel?.hasPrefix("youtube:") == true else { return false }
      if let videoID = chance.youtubeVideoID, store.v100State.hiddenVideoIDs.contains(videoID) { return false }
      return chance.empfohlenerKanalID == nil || chance.empfohlenerKanalID == channelID
    }
    let opportunities = Dictionary(uniqueKeysWithValues: store.v12RankedDecisions(channelID: channelID).map { ($0.chanceID, $0.opportunityScore) })
    let creatorCounts = Dictionary(grouping: items, by: { $0.youtubeChannelTitle ?? "" }).mapValues(\.count)
    learnedRank = Dictionary(uniqueKeysWithValues: items.map { chance in
      let base = opportunities[chance.id] ?? chance.trendScore
      let videoID = chance.youtubeVideoID ?? ""
      let personalized = TrendFeedScoreService.shared.personalizedScore(
        chance: chance,
        opportunityScore: base,
        watched: store.v100State.watchedVideoIDs.contains(videoID),
        shortlisted: store.v100State.shortlistedVideoIDs.contains(videoID),
        sameCreatorCount: creatorCounts[chance.youtubeChannelTitle ?? "", default: 0])
      let learning = LearningIntelligenceService.shared.topicSourceAffinityScore(
        chance: chance, channelID: channelID, snapshots: store.v100State.performanceSnapshots)
      let exploration = LearningIntelligenceService.shared.explorationBonus(
        chance: chance, channelID: channelID, snapshots: store.v100State.performanceSnapshots)
      return (chance.id, min(100, personalized + learning + exploration))
    })
  }
'''
text = text[:start] + new_filtered + text[end:]

old_lifecycle = '''      syncTopicToChannel()
      keepSelectionValid()
    }
    .onChange(of: selectedChannelID) { _ in
      syncTopicToChannel()
      keepSelectionValid()
    }'''
new_lifecycle = '''      syncTopicToChannel()
      recomputeLearnedRank()
      keepSelectionValid()
    }
    .onChange(of: selectedChannelID) { _ in
      syncTopicToChannel()
      recomputeLearnedRank()
      keepSelectionValid()
    }
    .onChange(of: store.chancen.count) { _ in
      recomputeLearnedRank()
      keepSelectionValid()
    }'''
if old_lifecycle not in text:
    raise SystemExit("BLACKSTOCK_1_REDESIGN: trend lifecycle missing")
text = text.replace(old_lifecycle, new_lifecycle, 1)

old_refresh = '''  private func refresh() async {
    store.v100State.trendRefreshCursor = 0
    _ = await store.chancenAktualisieren(zusaetzlicheMarktThemen: activeDiscoveryTerms)
    keepSelectionValid()
  }

  private func loadMore() async {
    _ = await store.chancenMehrLaden(zusaetzlicheMarktThemen: activeDiscoveryTerms)
    keepSelectionValid()
  }'''
new_refresh = '''  private func refresh() async {
    store.v100State.trendRefreshCursor = 0
    _ = await store.chancenAktualisieren(zusaetzlicheMarktThemen: activeDiscoveryTerms)
    recomputeLearnedRank()
    keepSelectionValid()
  }

  private func loadMore() async {
    _ = await store.chancenMehrLaden(zusaetzlicheMarktThemen: activeDiscoveryTerms)
    recomputeLearnedRank()
    keepSelectionValid()
  }'''
if old_refresh not in text:
    raise SystemExit("BLACKSTOCK_1_REDESIGN: refresh block missing")
text = text.replace(old_refresh, new_refresh, 1)

old_row_call = '''    TrendVideoRow(
      chance: chance,
      selected: selectedChance?.id == chance.id,
      recommendation: selectedChannelID.map { store.v26Recommendation(for: chance, channelID: $0) },
      onSelect: { selectedChanceID = chance.id })'''
new_row_call = '''    TrendVideoRow(
      chance: chance,
      selected: selectedChance?.id == chance.id,
      onSelect: { selectedChanceID = chance.id })'''
if old_row_call not in text:
    raise SystemExit("BLACKSTOCK_1_REDESIGN: trend row call missing")
text = text.replace(old_row_call, new_row_call, 1)
text = text.replace("  let recommendation: ProductionRecommendationV26?\n", "", 1)

old_rec_row = '''          if let recommendation {
            Text("\(recommendation.formatLabel) · \(recommendation.durationLabel)")
              .font(.system(size: 8.5, weight: .semibold))
              .foregroundStyle(Color.bsRed)
              .lineLimit(1)
          }'''
new_rec_row = '''          Text(rowSignal)
            .font(.system(size: 8.5, weight: .semibold))
            .foregroundStyle(Color.bsRed)
            .lineLimit(1)'''
if old_rec_row not in text:
    raise SystemExit("BLACKSTOCK_1_REDESIGN: row recommendation block missing")
text = text.replace(old_rec_row, new_rec_row, 1)
insert_at = text.index("\n  @ViewBuilder\n  private var thumbnail: some View {", text.index("private struct TrendVideoRow"))
row_signal = r'''
  private var rowSignal: String {
    if let duration = chance.youtubeDurationSeconds, duration < 60 { return "Short · Trend-Signal" }
    if let published = chance.youtubePublishedAt {
      let hours = max(1, Date().timeIntervalSince(published) / 3600)
      let velocity = Double(chance.youtubeViews ?? 0) / hours
      if hours <= 72 && velocity >= 5_000 { return "Neu · hohes Tempo" }
    }
    if (chance.youtubeViews ?? 0) >= 1_000_000 { return "Hohe Reichweite" }
    return "YouTube-Video"
  }
'''
text = text[:insert_at] + row_signal + text[insert_at:]

old_detail_state = '''  @State private var pendingMode: ProductionModeV11?
  @State private var pendingRightsStatus: RightsStatus = .owned

  private var recommendation: ProductionRecommendationV26? {
    selectedChannelID.map { store.v26Recommendation(for: chance, channelID: $0) }
  }'''
new_detail_state = '''  @State private var pendingMode: ProductionModeV11?
  @State private var pendingRightsStatus: RightsStatus = .owned
  @State private var recommendation: ProductionRecommendationV26?

  private func refreshRecommendation() {
    recommendation = selectedChannelID.map { store.v26Recommendation(for: chance, channelID: $0) }
  }'''
if old_detail_state not in text:
    raise SystemExit("BLACKSTOCK_1_REDESIGN: detail recommendation state missing")
text = text.replace(old_detail_state, new_detail_state, 1)

old_dialog = '''    }
    .confirmationDialog(
      "Ist das deine Datei oder darfst du sie verwenden?",'''
new_dialog = '''    }
    .onAppear { refreshRecommendation() }
    .onChange(of: chance.id) { _ in refreshRecommendation() }
    .onChange(of: selectedChannelID) { _ in refreshRecommendation() }
    .confirmationDialog(
      "Eigene Datei verwenden?",'''
if old_dialog not in text:
    raise SystemExit("BLACKSTOCK_1_REDESIGN: detail dialog anchor missing")
text = text.replace(old_dialog, new_dialog, 1)
text = text.replace('Button("Lizenzierte Datei · kommerzielle Bearbeitung erlaubt")', 'Button("Andere erlaubte Datei")', 1)
text = text.replace(
    'Text("Blackstock verarbeitet die ausgewählte Datei lokal. Eine YouTube-Referenz wird nicht heruntergeladen oder als MP4 kopiert.")',
    'Text("Diese Option ist nur für Dateien gedacht, die du selbst besitzt oder verwenden darfst. YouTube-Videos bleiben im offiziellen YouTube-Workflow.")',
    1)

old_recommendation = '''  private func recommendationCard(_ value: ProductionRecommendationV26) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack {
        VStack(alignment: .leading, spacing: 3) {
          Text("EMPFOHLEN")
            .font(.system(size: 8, weight: .bold)).tracking(1).foregroundStyle(Color.bsMuted)
          Text("\(value.actionLabel) → \(value.formatLabel) \(value.durationLabel)")
            .font(.system(size: 17, weight: .semibold)).foregroundStyle(Color.bsText)
        }
        Spacer()
        Text("\(Int(value.decision.opportunityScore.rounded()))")
          .font(.system(size: 20, weight: .bold)).monospacedDigit().foregroundStyle(Color.bsRed)
      }
      Text(value.decision.reason)
        .font(.system(size: 9.5)).foregroundStyle(Color.bsMuted)
        .fixedSize(horizontal: false, vertical: true)
      HStack(spacing: 7) {
        Label("YouTube: offizieller Remix", systemImage: "checkmark.shield.fill")
        Text("·")
        Label("MP4: nur eigene/lizenzierte Quelldatei", systemImage: "externaldrive.fill")
      }
      .font(.system(size: 8.5, weight: .medium)).foregroundStyle(Color.bsMuted2)
    }
    .padding(12).background(Color.bsSurface2).clipShape(RoundedRectangle(cornerRadius: 10))
  }'''
new_recommendation = r'''  private func recommendationCard(_ value: ProductionRecommendationV26) -> some View {
    VStack(alignment: .leading, spacing: 9) {
      Text("EMPFEHLUNG")
        .font(.system(size: 8, weight: .bold)).tracking(1).foregroundStyle(Color.bsMuted)
      Text("\(value.formatLabel) · \(value.durationLabel)")
        .font(.system(size: 17, weight: .semibold)).foregroundStyle(Color.bsText)
      Text(value.decision.reason)
        .font(.system(size: 9.5)).foregroundStyle(Color.bsMuted)
        .fixedSize(horizontal: false, vertical: true)
      HStack(spacing: 7) {
        ForEach(signalLabels(for: value), id: \.self) { signal in
          Text(signal)
            .font(.system(size: 8.5, weight: .semibold))
            .foregroundStyle(Color.bsText)
            .padding(.horizontal, 8).frame(height: 24)
            .background(Color.bsSurface).clipShape(Capsule())
            .overlay(Capsule().stroke(Color.bsBorder))
        }
      }
    }
    .padding(12).background(Color.bsSurface2).clipShape(RoundedRectangle(cornerRadius: 10))
  }

  private func signalLabels(for value: ProductionRecommendationV26) -> [String] {
    var result: [String] = [value.decision.recommendedFormat == .short ? "Short-Potenzial" : "Longform-Potenzial"]
    if let published = chance.youtubePublishedAt {
      let hours = max(1, Date().timeIntervalSince(published) / 3600)
      let velocity = Double(chance.youtubeViews ?? 0) / hours
      if hours <= 72 { result.append("Neu") }
      if velocity >= 5_000 { result.append("Hohes View-Tempo") }
    }
    if result.count < 3 { result.append(value.mode == .singleSource ? "Klarer Clip-Ansatz" : "Remix-Ansatz") }
    return Array(result.prefix(3))
  }'''
if old_recommendation not in text:
    raise SystemExit("BLACKSTOCK_1_REDESIGN: recommendation card missing")
text = text.replace(old_recommendation, new_recommendation, 1)

old_action = '''      Menu {
        Button { chooseSource(mode: .singleSource) } label: { Label("Mit eigener Datei schneiden", systemImage: "scissors") }
        Button { chooseSource(mode: .remix) } label: { Label("Mit eigener Datei remixen", systemImage: "rectangle.3.group") }
      } label: {
        if isStarting { ProgressView().controlSize(.small) }
        else { Label("Mit eigener Datei schneiden", systemImage: "scissors") }
      }'''
new_action = '''      Menu {
        Button { chooseSource(mode: .singleSource) } label: { Label("Eigene Datei als Clip", systemImage: "scissors") }
        Button { chooseSource(mode: .remix) } label: { Label("Eigene Datei als Remix", systemImage: "rectangle.3.group") }
      } label: {
        if isStarting { ProgressView().controlSize(.small) }
        else { Label("Weitere Aktionen", systemImage: "ellipsis.circle") }
      }'''
if old_action not in text:
    raise SystemExit("BLACKSTOCK_1_REDESIGN: action menu missing")
text = text.replace(old_action, new_action, 1)
text = text.replace(
    'Text("Originalton als Standard · Captions, Voice, Musik und Branding optional · lokaler Qualitätsrender")',
    'Text("YouTube bleibt der Hauptweg · lokale Produktion nur mit eigener/erlaubter Datei")',
    1)
text = text.replace('titel: "Noch keine Quellvideos geladen"', 'titel: "Noch keine Videos geladen"', 1)
text = text.replace(
    '"Verbinde zuerst deinen YouTube-Kanal. Danach lädt Blackstock passende YouTube-Videos ab 4 Minuten für dein Thema."',
    '"Verbinde zuerst deinen YouTube-Kanal. Danach lädt Blackstock passende Videos und Shorts als aktuelle Signale für dein Thema."',
    1)
text = text.replace('titel: "Keine passenden Quellvideos"', 'titel: "Keine passenden Videos"', 1)
text = text.replace(
    'text: "Wähle links ein Quellvideo. Es wird direkt hier in Blackstock abgespielt."',
    'text: "Wähle links ein Video. Es wird direkt hier in Blackstock abgespielt und erst dann genauer analysiert."',
    1)
trends.write_text(text)

# ---------------------------------------------------------------------------
# Mission reason: explain content relevance, not legal plumbing.
# ---------------------------------------------------------------------------
service = ROOT / "Sources/Blackstock/Services/CreatorOS1000Service.swift"
service_text = service.read_text()
old_reason = '''    let rightsSentence = path == .youtubeNativeRemix
      ? "Das Quellvideo bleibt auf YouTube; Blackstock führt ohne bereitgestellte Nutzungsquelle keinen eigenen MP4-Export daraus aus."
      : "Eine vom Nutzer bestätigte eigene oder lizenzierte Quelldatei ist für den lokalen Schnitt vorhanden."
    let reason = "\(decision.reason) \(rightsSentence)"'''
new_reason = '''    let reason = decision.reason'''
if old_reason not in service_text:
    raise SystemExit("BLACKSTOCK_1_REDESIGN: creator reason block missing")
service.write_text(service_text.replace(old_reason, new_reason, 1))

# ---------------------------------------------------------------------------
# Trend score: Shorts are valid trend signals; duration utility no longer buries them.
# ---------------------------------------------------------------------------
score_service = ROOT / "Sources/Blackstock/Services/TrendFeedScoreService.swift"
score_text = score_service.read_text()
old_switch = '''    switch duration {
    case 240..<600: sourceUtility = 78
    case 600..<1_200: sourceUtility = 94
    case 1_200..<3_600: sourceUtility = 100
    case 3_600...: sourceUtility = 88
    default: sourceUtility = 35
    }'''
new_switch = '''    switch duration {
    case 0..<60: sourceUtility = 76       // Shorts remain useful trend signals.
    case 60..<240: sourceUtility = 80
    case 240..<600: sourceUtility = 86
    case 600..<1_200: sourceUtility = 94
    case 1_200..<3_600: sourceUtility = 100
    case 3_600...: sourceUtility = 88
    default: sourceUtility = 72
    }'''
if old_switch not in score_text:
    raise SystemExit("BLACKSTOCK_1_REDESIGN: score duration switch missing")
score_service.write_text(score_text.replace(old_switch, new_switch, 1))

# ---------------------------------------------------------------------------
# Production detail: reference vs source, qualitative plan, YouTube-first empty state.
# ---------------------------------------------------------------------------
production = ROOT / "Sources/Blackstock/Views/ProduktionsDetailView.swift"
ptext = production.read_text()
ptext = ptext.replace('Text("AUSGEWÄHLTE YOUTUBE-QUELLE")', 'Text("YOUTUBE-REFERENZ")')
ptext = ptext.replace(
    'AbschnittTitel(titel: "Edit Blueprint", untertitel: "Blackstocks begründeter Schnittplan vor dem finalen Render")',
    'AbschnittTitel(titel: "Schnittplan", untertitel: "Was Blackstock mit deinem Material vor dem Render vorhat")')
ptext = ptext.replace('Label("\(blueprint.sourceCount) Quelle(n)", systemImage: "film.stack")', 'Label("\(blueprint.sourceCount) Datei(en)", systemImage: "film.stack")')
ptext = ptext.replace('        Label("Dauerfit \(Int(blueprint.durationFit.rounded()))%", systemImage: "scope")\n', '')
old_diag = '''      HStack(spacing: 10) {
        Label("Dead-air risk \(Int(blueprint.deadAirRisk.rounded()))%", systemImage: "waveform.path")
        Label("Coverage \(Int(blueprint.sourceCoverage.rounded()))%", systemImage: "rectangle.inset.filled")
        Label("Plan confidence \(Int(blueprint.confidence.rounded()))%", systemImage: "checkmark.seal")
      }
      .font(.system(size: 9)).foregroundStyle(blueprint.deadAirRisk > 45 ? Color.bsAmber : Color.bsMuted)'''
new_diag = '''      if blueprint.deadAirRisk > 45 {
        Label("Längere Pausen erkannt – Schnitt wird verdichtet", systemImage: "waveform.path")
          .font(.system(size: 9)).foregroundStyle(Color.bsAmber)
      } else {
        Label("Sprechfluss eignet sich gut für den geplanten Schnitt", systemImage: "checkmark.seal")
          .font(.system(size: 9)).foregroundStyle(Color.bsMuted)
      }'''
if old_diag not in ptext:
    raise SystemExit("BLACKSTOCK_1_REDESIGN: blueprint diagnostics missing")
ptext = ptext.replace(old_diag, new_diag, 1)
ptext = ptext.replace('Text("Hook candidates")', 'Text("Mögliche Hooks")')
ptext = ptext.replace(
    'AbschnittTitel(titel: "Erstellen", untertitel: "Originalmaterial → Schnitt → Vorschau → Veröffentlichen")',
    'AbschnittTitel(titel: "Produktion", untertitel: "Material → Schnitt → Vorschau → Veröffentlichen")')
old_empty = '''            Text("YouTube-Originalmaterial läuft über Remix/Ausschneiden. Für einen Blackstock-MP4-Export wählst du eine Videodatei, die du verwenden darfst.")
              .font(.system(size: 9)).foregroundStyle(Color.bsMuted)'''
new_empty = '''            Text("Für dieses YouTube-Video ist Clip/Remix auf YouTube der schnellste Weg. Für einen eigenen Blackstock-Render kannst du zusätzlich eine eigene oder erlaubte Datei verwenden.")
              .font(.system(size: 9)).foregroundStyle(Color.bsMuted)'''
if old_empty not in ptext:
    raise SystemExit("BLACKSTOCK_1_REDESIGN: production empty copy missing")
ptext = ptext.replace(old_empty, new_empty, 1)
ptext = ptext.replace('Button("Zum Trend")', 'Button("Trend / YouTube öffnen")', 1)
ptext = ptext.replace('else { Label("Videodatei wählen", systemImage: "plus.rectangle.on.folder") }', 'else { Label("Eigene Datei verwenden", systemImage: "plus.rectangle.on.folder") }', 1)
ptext = ptext.replace(
    'titel: "Originalmaterial",\n        untertitel: "Erweiterte Quellenverwaltung für den Blackstock-MP4-Export."',
    'titel: "Eigenes Material",\n        untertitel: "Optional für einen lokalen Blackstock-Render."')
ptext = ptext.replace('Text("REMOTE-QUELLE HINZUFÜGEN")', 'Text("ERWEITERTE QUELLE HINZUFÜGEN")')
production.write_text(ptext)

# ---------------------------------------------------------------------------
# Next action language and source workflow strings.
# ---------------------------------------------------------------------------
next_action = ROOT / "Sources/Blackstock/Services/NextBestActionService.swift"
replace_all(next_action, '"Neue YouTube-Chancen laden"', '"Aktuelle YouTube-Trends laden"')
replace_all(next_action, '"Blackstock aktualisiert den Feed für dein festgelegtes Thema und priorisiert neue, nutzbare Quellen."', '"Blackstock aktualisiert den Feed für dein Kanalthema und priorisiert neue, relevante Videos."')
replace_all(next_action, '"Deine Performance-Lernsignale sind aktiv. Öffne den Feed und wähle die aktuell beste Quelle."', '"Deine Performance-Lernsignale sind aktiv. Öffne den Feed und prüfe die aktuell relevantesten Videos."')
replace_all(next_action, '"Video ansehen und Empfehlung erstellen"', '"Video ansehen und Empfehlung prüfen"')

store1000 = ROOT / "Sources/Blackstock/AppStore+V1000.swift"
replace_all(store1000, '"Blackstock erzeugt aus einem YouTube-Link keine künstliche Kopie. Nutze den offiziellen YouTube-Remix oder wähle eine eigene bzw. lizenzierte Quelldatei für den lokalen High-End-Schnitt."', '"Dieses YouTube-Video bleibt eine Referenz. Öffne Clip/Remix auf YouTube oder nutze optional eine eigene Datei für einen Blackstock-Render."')
replace_all(store1000, '"Diese Chance existiert bereits als Produktion. Blackstock öffnet das vorhandene Projekt."', '"Dieses Video existiert bereits als Projekt. Blackstock öffnet es."')
replace_all(store1000, '"Originalmaterial analysieren · Schnitt, Studio-Layer und Export vorbereiten"', '"Material analysieren · Schnitt, Studio-Layer und Export vorbereiten"')
replace_all(store1000, '"Aktuell gibt es keine ausreichend starke Schnittchance für diesen Kanal."', '"Aktuell gibt es keine neuen relevanten Videos für diesen Kanal."')
replace_all(store1000, '"starke Remix-/Clip-Chancen wurden für den Kanal vorbereitet. Es wurde kein Video generiert oder hochgeladen."', '"relevante Videos wurden für den Kanal vorgemerkt. Es wurde kein Video generiert oder hochgeladen."')

store26 = ROOT / "Sources/Blackstock/AppStore+V26.swift"
replace_all(store26, '"Original-/lizenzierte Videodatei hinzufügen · Ziel: \(label)"', '"Eigene oder erlaubte Videodatei hinzufügen · Ziel: \(label)"')
replace_all(store26, '"Für den Schnitt fehlt noch die Original-/Lizenzdatei. Wähle sie im Projekt unter Schnittquelle aus."', '"Für einen lokalen Blackstock-Schnitt fehlt noch eine eigene oder erlaubte Videodatei."')
replace_all(store26, '"Quelle analysieren · Ziel: \(label)"', '"Material analysieren · Ziel: \(label)"')

# Release contract for the market-facing product.
audit = ROOT / "Build/Release-Audit.sh"
audit_text = audit.read_text()
marker = "# BLACKSTOCK_1_MARKET_PRODUCT_REDESIGN_AUDIT"
if marker not in audit_text:
    audit_text += r'''

# BLACKSTOCK_1_MARKET_PRODUCT_REDESIGN_AUDIT
! grep -q 'CHANCE \\(' "$ROOT/Sources/Blackstock/Views/CreatorOS1000View.swift" || fail "Dashboard zeigt noch pseudo-praezise Chance-Zahl"
! grep -q 'mission.score' "$ROOT/Sources/Blackstock/Views/CreatorOS1000View.swift" || fail "Dashboard zeigt noch internen Mission-Score"
! grep -q 'sourceRightsDialog' "$ROOT/Sources/Blackstock/Views/CreatorOS1000View.swift" || fail "Dashboard enthaelt noch Rechte-/Datei-Workflow"
! grep -q 'private var metrics' "$ROOT/Sources/Blackstock/Views/CreatorOS1000View.swift" || fail "Dashboard enthaelt noch KPI-Kachelreihe"
grep -q 'Was jetzt wichtig ist' "$ROOT/Sources/Blackstock/Views/CreatorOS1000View.swift" || fail "Neues handlungsorientiertes Dashboard fehlt"
grep -q 'Shorts < 1 Min.' "$ROOT/Sources/Blackstock/Views/ChancenView.swift" || fail "Shorts-Trendfilter fehlt"
grep -q '1–4 Min.' "$ROOT/Sources/Blackstock/Views/ChancenView.swift" || fail "Kurze Videos fehlen im Dauerfilter"
! grep -q 'opportunityScore.rounded' "$ROOT/Sources/Blackstock/Views/ChancenView.swift" || fail "Trenddetail zeigt noch Opportunity-Zahl"
grep -q 'recomputeLearnedRank' "$ROOT/Sources/Blackstock/Views/ChancenView.swift" || fail "Gecachtes Trendranking fehlt"
! grep -q 'recommendation: selectedChannelID.map' "$ROOT/Sources/Blackstock/Views/ChancenView.swift" || fail "Feed berechnet Empfehlung noch pro Zeile/Render"
grep -q 'Hohes View-Tempo' "$ROOT/Sources/Blackstock/Views/ChancenView.swift" || fail "Verstaendliche Trend-Signale fehlen"
grep -q 'YOUTUBE-REFERENZ' "$ROOT/Sources/Blackstock/Views/ProduktionsDetailView.swift" || fail "YouTube wird im Projekt noch als lokale Quelle bezeichnet"
grep -q 'Schnittplan' "$ROOT/Sources/Blackstock/Views/ProduktionsDetailView.swift" || fail "Verstaendlicher Schnittplan fehlt"
! grep -q 'Dead-air risk' "$ROOT/Sources/Blackstock/Views/ProduktionsDetailView.swift" || fail "Technischer Prozent-Jargon noch sichtbar"
! grep -q 'Plan confidence' "$ROOT/Sources/Blackstock/Views/ProduktionsDetailView.swift" || fail "Plan-Confidence-Prozent noch sichtbar"
'''
    audit.write_text(audit_text)

print("BLACKSTOCK_1_MARKET_PRODUCT_REDESIGN_OK")
