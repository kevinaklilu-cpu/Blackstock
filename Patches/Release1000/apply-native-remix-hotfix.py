from pathlib import Path

repo = Path.cwd()


def replace_once(path: Path, old: str, new: str):
    text = path.read_text()
    if new in text:
        return
    if old not in text:
        raise SystemExit(f"Expected block missing in {path}: {old[:140]!r}")
    path.write_text(text.replace(old, new, 1))


def replace_all(path: Path, old: str, new: str):
    text = path.read_text()
    if old not in text:
        if new in text:
            return
        raise SystemExit(f"Expected text missing in {path}: {old!r}")
    path.write_text(text.replace(old, new))

player = repo / "Sources/Blackstock/Views/YouTubePlayerView.swift"
trends = repo / "Sources/Blackstock/Views/ChancenView.swift"
dashboard = repo / "Sources/Blackstock/Views/CreatorOS1000View.swift"
store1000 = repo / "Sources/Blackstock/AppStore+V1000.swift"
store26 = repo / "Sources/Blackstock/AppStore+V26.swift"
store11 = repo / "Sources/Blackstock/AppStore+V11.swift"
models11 = repo / "Sources/Blackstock/Models/V11Models.swift"
metadata = repo / "Sources/Blackstock/Services/FinalMetadataService.swift"
production = repo / "Sources/Blackstock/Views/ProduktionsDetailView.swift"

# Official YouTube iframe stays the only YouTube media access. We only report playback time
# so Blackstock can hand the user back to YouTube's own Remix/Cut creation surface.
replace_once(
    player,
    '  var onPlaybackStarted: (() -> Void)? = nil\n',
    '  var onPlaybackStarted: (() -> Void)? = nil\n  var onPlaybackTime: ((Double) -> Void)? = nil\n')
replace_once(
    player,
    '        case .paused: status = .paused\n        case .failed(let message, let code):',
    '        case .paused: status = .paused\n        case .time(let seconds): onPlaybackTime?(seconds)\n        case .failed(let message, let code):')
replace_once(
    player,
    '    case paused\n    case failed(String, Int?)\n',
    '    case paused\n    case time(Double)\n    case failed(String, Int?)\n')
replace_once(
    player,
    "                onReady: function() { post('ready'); },",
    "                onReady: function() {\n                  post('ready');\n                  setInterval(function() {\n                    try {\n                      if (player && player.getCurrentTime) post('time', String(player.getCurrentTime()));\n                    } catch(e) {}\n                  }, 750);\n                },")
replace_once(
    player,
    '        case "paused": self.onEvent(.paused)\n        case "error":',
    '        case "paused": self.onEvent(.paused)\n        case "time":\n          if let raw = body["value"] as? String, let seconds = Double(raw) { self.onEvent(.time(seconds)) }\n        case "error":')

# Trend browser: simpler controls, aligned rows and two honest creation paths.
replace_once(trends, 'import SwiftUI\n', 'import SwiftUI\nimport UniformTypeIdentifiers\n')
replace_all(trends, 'English-first', 'Originalsprache')
replace_all(trends, 'passende englische Videos ab 4 Minuten', 'passende YouTube-Videos ab 4 Minuten')
replace_once(
    trends,
    '''  private var controls: some View {\n    HStack(spacing: 10) {''',
    '''  private var controls: some View {\n    VStack(spacing: 8) {\n      HStack(spacing: 10) {''')
replace_once(
    trends,
    '''      HStack(spacing: 8) {\n        Image(systemName: "magnifyingglass").foregroundStyle(Color.bsMuted)''',
    '''      HStack(spacing: 8) {\n        Image(systemName: "magnifyingglass").foregroundStyle(Color.bsMuted)''')
# Close the first row before the filter menus and move filters to a second, calmer line.
old_controls_mid = '''      Menu {\n        ForEach(TrendSourceDurationFilter.allCases) { item in\n          Button(item.rawValue) { durationFilter = item }\n        }\n      } label: {\n        Label(durationFilter.rawValue, systemImage: "clock")\n          .frame(minWidth: 100)\n      }\n      .menuStyle(.borderlessButton).fixedSize()\n\n      Menu {\n        ForEach(TrendLibraryFilter.allCases) { item in\n          Button(item.rawValue) { libraryFilter = item }\n        }\n      } label: {\n        Label(libraryFilter.rawValue, systemImage: "bookmark")\n      }\n      .menuStyle(.borderlessButton).fixedSize()\n\n      Menu {\n        ForEach(TrendAgeFilter.allCases) { item in\n          Button(item.rawValue) { ageFilter = item }\n        }\n      } label: {\n        Label(ageFilter.rawValue, systemImage: "calendar")\n      }\n      .menuStyle(.borderlessButton).fixedSize()\n\n      Menu {\n        ForEach(TrendSortierung.allCases) { item in\n          Button(item.rawValue) { sortierung = item }\n        }\n      } label: {\n        Label(sortierung.rawValue, systemImage: "arrow.up.arrow.down")\n      }\n      .menuStyle(.borderlessButton).fixedSize()\n\n      HStack(spacing: 8) {'''
new_controls_mid = '''      HStack(spacing: 8) {'''
replace_once(trends, old_controls_mid, new_controls_mid)
old_controls_end = '''      .padding(.horizontal, 11).frame(maxWidth: .infinity, minHeight: 36)\n      .background(Color.bsSurface2).clipShape(RoundedRectangle(cornerRadius: 9))\n    }\n    .padding(10)'''
new_controls_end = '''      .padding(.horizontal, 11).frame(maxWidth: .infinity, minHeight: 36)\n      .background(Color.bsSurface2).clipShape(RoundedRectangle(cornerRadius: 9))\n      }\n\n      HStack(spacing: 14) {\n        Menu {\n          ForEach(TrendSourceDurationFilter.allCases) { item in Button(item.rawValue) { durationFilter = item } }\n        } label: { Label(durationFilter.rawValue, systemImage: "clock") }\n        .menuStyle(.borderlessButton).fixedSize()\n\n        Menu {\n          ForEach(TrendAgeFilter.allCases) { item in Button(item.rawValue) { ageFilter = item } }\n        } label: { Label(ageFilter.rawValue, systemImage: "calendar") }\n        .menuStyle(.borderlessButton).fixedSize()\n\n        Menu {\n          ForEach(TrendLibraryFilter.allCases) { item in Button(item.rawValue) { libraryFilter = item } }\n        } label: { Label(libraryFilter.rawValue, systemImage: "bookmark") }\n        .menuStyle(.borderlessButton).fixedSize()\n\n        Menu {\n          ForEach(TrendSortierung.allCases) { item in Button(item.rawValue) { sortierung = item } }\n        } label: { Label(sortierung.rawValue, systemImage: "arrow.up.arrow.down") }\n        .menuStyle(.borderlessButton).fixedSize()\n        Spacer()\n      }\n      .font(.system(size: 9.5))\n    }\n    .padding(10)'''
replace_once(trends, old_controls_end, new_controls_end)
replace_once(
    trends,
    '      .contentShape(Rectangle())\n',
    '      .frame(maxWidth: .infinity, minHeight: 102, alignment: .leading)\n      .contentShape(Rectangle())\n')

replace_once(
    trends,
    '  @State private var isStarting = false\n',
    '  @State private var isStarting = false\n  @State private var playbackTime: Double = 0\n  @State private var localSourceImporter = false\n  @State private var pendingMode: ProductionModeV11?\n')
replace_once(
    trends,
    '            onPlaybackStarted: { markWatched() })',
    '            onPlaybackStarted: { markWatched() },\n            onPlaybackTime: { playbackTime = $0 })')
replace_once(
    trends,
    '''    }\n  }\n\n  private func updateSourceHealth''',
    '''    }\n    .fileImporter(\n      isPresented: $localSourceImporter,\n      allowedContentTypes: [.movie],\n      allowsMultipleSelection: false\n    ) { result in\n      importSource(result)\n    }\n  }\n\n  private func updateSourceHealth''')
replace_once(
    trends,
    '      Text("Das YouTube-Video dient als Referenz. Für Clip oder Remix wählst du eine eigene oder lizenzierte Videodatei. Ohne Schnittquelle erstellt Blackstock ein neues Video zum Thema.")',
    '      Text("Originalmaterial ohne Download: Nutze YouTubes eigene Remix-/Ausschneiden-Funktion. Für einen vollständigen Blackstock-MP4-Export wählst du eine Videodatei, die du verwenden darfst.")')
replace_once(
    trends,
    '''  private func actionBar(_ value: ProductionRecommendationV26) -> some View {\n    HStack(spacing: 9) {\n      Button {\n        startCreatorOS()\n      } label: {\n        if isStarting {\n          ProgressView().controlSize(.small)\n        } else {\n          Label("Video erstellen", systemImage: "wand.and.stars")\n        }\n      }\n      .buttonStyle(.borderedProminent).tint(Color.bsRed).foregroundStyle(.white)\n      .disabled(isStarting || selectedChannelID == nil)\n\n      Menu {\n        Button { start(mode: .singleSource) } label: {\n          Label("Als Clip schneiden", systemImage: "scissors")\n        }\n        Button { start(mode: .remix) } label: {\n          Label("Als Remix schneiden", systemImage: "rectangle.3.group")\n        }\n      } label: {\n        Label("Schnittart wählen", systemImage: "slider.horizontal.3")\n      }\n      .menuStyle(.borderlessButton)\n      .disabled(isStarting || selectedChannelID == nil)\n\n      Spacer()\n      Text("English · Captions · Auto-Länge")\n        .font(.system(size: 8.5, weight: .medium)).foregroundStyle(Color.bsMuted)\n    }\n  }\n\n  private func startCreatorOS() {\n    guard let channelID = selectedChannelID else {\n      store.ausgewaehltesZiel = .konten\n      return\n    }\n    isStarting = true\n    Task {\n      let id = await store.v1000ProduktionStarten(chance: chance, channelID: channelID)\n      isStarting = false\n      if id == nil { store.meldung = "Das Video konnte nicht erstellt werden." }\n    }\n  }\n\n  private func start(mode: ProductionModeV11?) {\n    guard let channelID = selectedChannelID else {\n      store.ausgewaehltesZiel = .konten\n      return\n    }\n    isStarting = true\n    Task {\n      let id = await store.v26ProduktionStarten(\n        chance: chance,\n        channelID: channelID,\n        forcedMode: mode)\n      isStarting = false\n      if id == nil {\n        store.meldung = "Die Produktion konnte nicht angelegt werden. Prüfe den verbundenen Channel."\n      }\n    }\n  }''',
    '''  private func actionBar(_ value: ProductionRecommendationV26) -> some View {\n    HStack(spacing: 9) {\n      Button {\n        openNativeRemix()\n      } label: {\n        Label("Auf YouTube remixen", systemImage: "play.rectangle.fill")\n      }\n      .buttonStyle(.borderedProminent).tint(Color.bsRed).foregroundStyle(.white)\n      .disabled(chance.youtubeVideoID == nil)\n\n      Menu {\n        Button { chooseSource(mode: .singleSource) } label: {\n          Label("Clip aus Videodatei", systemImage: "scissors")\n        }\n        Button { chooseSource(mode: .remix) } label: {\n          Label("Remix aus Videodatei", systemImage: "rectangle.3.group")\n        }\n      } label: {\n        if isStarting { ProgressView().controlSize(.small) }\n        else { Label("In Blackstock schneiden", systemImage: "scissors") }\n      }\n      .menuStyle(.borderlessButton)\n      .disabled(isStarting || selectedChannelID == nil)\n\n      Spacer()\n      Text("Originalton · Originalsprache · keine KI-Stimme")\n        .font(.system(size: 8.5, weight: .medium)).foregroundStyle(Color.bsMuted)\n    }\n  }\n\n  private func openNativeRemix() {\n    guard let videoID = chance.youtubeVideoID else { return }\n    let start = max(0, Int(playbackTime.rounded(.down)))\n    var components = URLComponents(string: "https://www.youtube.com/watch")\n    components?.queryItems = [\n      URLQueryItem(name: "v", value: videoID),\n      URLQueryItem(name: "t", value: "\\(start)s")\n    ]\n    if let url = components?.url { openURL(url) }\n    store.meldung = start > 0\n      ? "YouTube ist bei \\(durationText(Double(start))) geöffnet. Nutze dort Remix → Ausschneiden. Das Original bleibt mit dem Quellvideo verknüpft."\n      : "YouTube ist geöffnet. Nutze dort Remix → Ausschneiden. Blackstock lädt das fremde Video dafür nicht herunter."\n  }\n\n  private func chooseSource(mode: ProductionModeV11) {\n    pendingMode = mode\n    localSourceImporter = true\n  }\n\n  private func importSource(_ result: Result<[URL], Error>) {\n    switch result {\n    case .success(let urls):\n      guard let sourceURL = urls.first, let channelID = selectedChannelID else { return }\n      let mode = pendingMode\n      isStarting = true\n      Task {\n        _ = await store.v1000ProduktionMitQuelleStarten(\n          chance: chance, channelID: channelID, sourceURL: sourceURL, forcedMode: mode)\n        isStarting = false\n        pendingMode = nil\n      }\n    case .failure(let error):\n      pendingMode = nil\n      store.meldung = error.localizedDescription\n    }\n  }''')

# Dashboard becomes a thin launch surface rather than another production console.
replace_once(dashboard, 'struct CreatorOS1000View: View {\n  @EnvironmentObject private var store: AppStore\n', 'struct CreatorOS1000View: View {\n  @EnvironmentObject private var store: AppStore\n  @Environment(\\.openURL) private var openURL\n')
replace_once(dashboard, '        hero\n        metrics\n', '        hero\n')
replace_once(dashboard, '          missionsCard\n          productionLane\n          learningCard\n', '          missionsCard\n          productionLane\n')
replace_once(
    dashboard,
    '''        Text("CHANCE \\(Int(snapshot.bestMission?.score.rounded() ?? snapshot.systemScore.rounded()))")\n          .font(.system(size: 22, weight: .bold)).monospacedDigit().foregroundStyle(Color.bsRed)\n        if let mission = snapshot.bestMission {\n          Button {\n            run(mission)\n          } label: {\n            if runningMissionID == mission.id && !importingLocalSource { ProgressView().controlSize(.small) }\n            else { Label("Video erstellen", systemImage: "wand.and.stars") }\n          }\n          .buttonStyle(.borderedProminent).tint(Color.bsRed).foregroundStyle(.white)\n          .disabled(runningMissionID != nil || runningAutopilot || importingLocalSource)\n\n          Button {\n            chooseLicensedSource(for: mission)\n          } label: {\n            if runningMissionID == mission.id && importingLocalSource { ProgressView().controlSize(.small) }\n            else { Label(sourceActionLabel(for: mission), systemImage: "scissors") }\n          }\n          .buttonStyle(.bordered)\n          .disabled(runningMissionID != nil || runningAutopilot || importingLocalSource)\n        }\n        Button {\n          guard let channelID = selectedChannelID else { return }\n          runningAutopilot = true\n          Task {\n            await store.v1000AutopilotRun(channelID: channelID)\n            runningAutopilot = false\n          }\n        } label: {\n          if runningAutopilot { ProgressView().controlSize(.small) }\n          else { Label("Top 3 automatisch erstellen", systemImage: "arrow.triangle.2.circlepath") }\n        }\n        .buttonStyle(.bordered)\n        .disabled(selectedChannelID == nil || runningMissionID != nil || runningAutopilot)''',
    '''        if let mission = snapshot.bestMission {\n          Text("CHANCE \\(Int(mission.score.rounded()))")\n            .font(.system(size: 18, weight: .bold)).monospacedDigit().foregroundStyle(Color.bsRed)\n          Button { openNativeRemix(mission) } label: {\n            Label("Auf YouTube remixen", systemImage: "play.rectangle.fill")\n          }\n          .buttonStyle(.borderedProminent).tint(Color.bsRed).foregroundStyle(.white)\n\n          Button { chooseLicensedSource(for: mission) } label: {\n            if runningMissionID == mission.id && importingLocalSource { ProgressView().controlSize(.small) }\n            else { Label(sourceActionLabel(for: mission), systemImage: "scissors") }\n          }\n          .buttonStyle(.bordered)\n          .disabled(runningMissionID != nil || importingLocalSource)\n        }''')
replace_once(dashboard, '        ForEach(Array(snapshot.missions.prefix(6))) { mission in', '        ForEach(Array(snapshot.missions.prefix(4))) { mission in')
replace_all(dashboard, 'Text("\\(mission.executionPath.rawValue) · \\(mission.formatLabel) · \\(mission.durationLabel)")', 'Text("\\(mission.formatLabel) · \\(mission.durationLabel)")')
replace_once(
    dashboard,
    '''            Button("Erstellen") { run(mission) }\n              .buttonStyle(.borderedProminent).tint(Color.bsRed).foregroundStyle(.white).controlSize(.small)\n              .disabled(runningMissionID != nil || runningAutopilot || importingLocalSource)\n            Button { chooseLicensedSource(for: mission) } label: {''',
    '''            Button("YouTube") { openNativeRemix(mission) }\n              .buttonStyle(.borderedProminent).tint(Color.bsRed).foregroundStyle(.white).controlSize(.small)\n            Button { chooseLicensedSource(for: mission) } label: {''')
replace_all(dashboard, '.disabled(runningMissionID != nil || runningAutopilot || importingLocalSource)', '.disabled(runningMissionID != nil || importingLocalSource)')
replace_once(
    dashboard,
    '  private func run(_ mission: CreatorMission1000) {',
    '''  private func openNativeRemix(_ mission: CreatorMission1000) {\n    guard let chance = store.chancen.first(where: { $0.id == mission.chanceID }),\n          let url = chance.youtubeWatchURL else {\n      store.ausgewaehltesZiel = .chancen\n      return\n    }\n    openURL(url)\n    store.meldung = "Nutze in YouTube Remix → Ausschneiden. Für einen Blackstock-MP4-Export wähle stattdessen eine Videodatei, die du verwenden darfst."\n  }\n\n  private func run(_ mission: CreatorMission1000) {''')

# File-based clipping is always source-first: no synthetic voice/music, explicit edit mode.
replace_once(
    store1000,
    '''    sourceURL: URL\n  ) async -> UUID? {''',
    '''    sourceURL: URL,\n    forcedMode: ProductionModeV11? = nil\n  ) async -> UUID? {''')
replace_once(
    store1000,
    '''    let recommendation = v26Recommendation(for: chance, channelID: channelID)\n    let mission = CreatorOS1000Service.shared.mission(\n      chance: chance,\n      decision: recommendation.decision,\n      hasUsableSource: true,\n      preferredEditMode: recommendation.mode)\n\n    guard let id = await v26ProduktionStarten(\n      chance: chance,\n      channelID: channelID,\n      forcedMode: recommendation.mode,''',
    '''    let recommendation = v26Recommendation(for: chance, channelID: channelID)\n    let editMode = forcedMode ?? recommendation.mode\n    let mission = CreatorOS1000Service.shared.mission(\n      chance: chance,\n      decision: recommendation.decision,\n      hasUsableSource: true,\n      preferredEditMode: editMode)\n\n    guard let id = await v26ProduktionStarten(\n      chance: chance,\n      channelID: channelID,\n      forcedMode: editMode,''')
replace_once(
    store1000,
    '''      produktionen[index].captionsAktiv = true\n      produktionen[index].watermarkAktiv = true\n      produktionen[index].naechsterSchritt = "\\(mission.executionPath.rawValue) · Quelle analysieren und Master bauen"''',
    '''      produktionen[index].captionsAktiv = true\n      produktionen[index].voiceoverDatei = nil\n      produktionen[index].musikAssetID = nil\n      produktionen[index].watermarkAktiv = true\n      produktionen[index].naechsterSchritt = "Originalmaterial analysieren · Schnitt und Export vorbereiten"''')
replace_once(
    store11,
    '''      // Blackstock-Standard: jeder neu erzeugte Clip enthält Captions.\n      timeline.captions = true\n      v11TimelineSetzen(timeline, fuer: productionID)''',
    '''      // Source-first edit: preserve the selected video's original audio and language.\n      timeline.captions = true\n      timeline.voiceoverPath = nil\n      timeline.musicSourceAssetID = nil\n      v11TimelineSetzen(timeline, fuer: productionID)''')

# Source language, not UI language, drives final metadata for source-based edits.
replace_once(
    metadata,
    '''    let english = profile.language.lowercased().contains("english") || profile.language.lowercased().hasPrefix("en")\n''',
    '''    let sourceLanguage = used.compactMap(\\.language)\n      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }\n      .first(where: { !$0.isEmpty }) ?? profile.language\n    let languageKey = sourceLanguage.lowercased()\n    let english = languageKey.contains("english") || languageKey.hasPrefix("en")\n''')
replace_all(models11, 'Englische Burn-in-Captions sind für Blackstock-Produktionen Pflicht.', 'Burn-in-Captions in der Originalsprache sind für geschnittene Blackstock-Videos Pflicht.')
replace_all(store26, 'detail: "Englisches Zeittranskript aktualisiert"', 'detail: "Zeittranskript in Originalsprache aktualisiert"')
replace_all(production, 'setzt englische Captions', 'setzt Captions in der Originalsprache')
replace_all(production, 'AbschnittTitel(titel: "Schnittquelle",', 'AbschnittTitel(titel: "Originalmaterial",')
replace_all(production, 'Original-/Lizenzdatei auswählen', 'Videodatei auswählen')

# Release guardrails: no downloader and no synthetic voice in the source-based render path.
assert 'voiceover: nil' in store11.read_text()
assert 'musik: nil' in store11.read_text()
assert 'case .youtubeReference:\n          throw SourceConnectorError.notDownloadableReference' in store11.read_text()
assert 'Label("Auf YouTube remixen"' in trends.read_text()
assert 'Originalton · Originalsprache · keine KI-Stimme' in trends.read_text()
assert 'onPlaybackTime' in player.read_text()

print("BLACKSTOCK_NATIVE_REMIX_HOTFIX_OK")
