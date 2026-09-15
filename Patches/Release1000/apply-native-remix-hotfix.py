from pathlib import Path

repo = Path.cwd()


def once(path: Path, old: str, new: str):
    text = path.read_text()
    if new in text:
        return
    if old not in text:
        raise SystemExit(f"missing in {path}: {old[:120]!r}")
    path.write_text(text.replace(old, new, 1))


def all_(path: Path, old: str, new: str):
    text = path.read_text()
    if old in text:
        path.write_text(text.replace(old, new))
    elif new not in text:
        raise SystemExit(f"missing in {path}: {old!r}")

player = repo / "Sources/Blackstock/Views/YouTubePlayerView.swift"
trends = repo / "Sources/Blackstock/Views/ChancenView.swift"
dashboard = repo / "Sources/Blackstock/Views/CreatorOS1000View.swift"
store1000 = repo / "Sources/Blackstock/AppStore+V1000.swift"
store11 = repo / "Sources/Blackstock/AppStore+V11.swift"
store26 = repo / "Sources/Blackstock/AppStore+V26.swift"
models11 = repo / "Sources/Blackstock/Models/V11Models.swift"
metadata = repo / "Sources/Blackstock/Services/FinalMetadataService.swift"
production = repo / "Sources/Blackstock/Views/ProduktionsDetailView.swift"

# Keep YouTube content inside the official iframe and expose only playback time for handoff.
once(player,
     '  var onPlaybackStarted: (() -> Void)? = nil\n',
     '  var onPlaybackStarted: (() -> Void)? = nil\n  var onPlaybackTime: ((Double) -> Void)? = nil\n')
once(player,
     '        case .paused: status = .paused\n        case .failed(let message, let code):',
     '        case .paused: status = .paused\n        case .time(let seconds): onPlaybackTime?(seconds)\n        case .failed(let message, let code):')
once(player,
     '    case paused\n    case failed(String, Int?)\n',
     '    case paused\n    case time(Double)\n    case failed(String, Int?)\n')
once(player,
     "                onReady: function() { post('ready'); },",
     "                onReady: function() {\n                  post('ready');\n                  setInterval(function() {\n                    try { if (player && player.getCurrentTime) post('time', String(player.getCurrentTime())); } catch(e) {}\n                  }, 750);\n                },")
once(player,
     '        case "paused": self.onEvent(.paused)\n        case "error":',
     '        case "paused": self.onEvent(.paused)\n        case "time":\n          if let raw = body["value"] as? String, let seconds = Double(raw) { self.onEvent(.time(seconds)) }\n        case "error":')

# Trends: cleaner wording, aligned rows, official Remix handoff + direct file edit.
once(trends, 'import SwiftUI\n', 'import SwiftUI\nimport UniformTypeIdentifiers\n')
all_(trends, 'English-first', 'Originalsprache')
all_(trends, 'passende englische Videos ab 4 Minuten', 'passende YouTube-Videos ab 4 Minuten')
once(trends,
     '      .contentShape(Rectangle())\n',
     '      .frame(maxWidth: .infinity, minHeight: 102, alignment: .leading)\n      .contentShape(Rectangle())\n')
once(trends,
     '  @State private var isStarting = false\n',
     '  @State private var isStarting = false\n  @State private var playbackTime: Double = 0\n  @State private var localSourceImporter = false\n  @State private var pendingMode: ProductionModeV11?\n')
once(trends,
     '            onPlaybackStarted: { markWatched() })',
     '            onPlaybackStarted: { markWatched() },\n            onPlaybackTime: { playbackTime = $0 })')
once(trends,
     '''    }\n  }\n\n  private func updateSourceHealth''',
     '''    }\n    .fileImporter(\n      isPresented: $localSourceImporter,\n      allowedContentTypes: [.movie],\n      allowsMultipleSelection: false\n    ) { result in\n      importSource(result)\n    }\n  }\n\n  private func updateSourceHealth''')
once(trends,
     '      Text("Das YouTube-Video dient als Referenz. Für Clip oder Remix wählst du eine eigene oder lizenzierte Videodatei. Ohne Schnittquelle erstellt Blackstock ein neues Video zum Thema.")',
     '      Text("Originalmaterial ohne Download: Nutze YouTubes eigene Remix-/Ausschneiden-Funktion. Für einen vollständigen Blackstock-MP4-Export wählst du eine Videodatei, die du verwenden darfst.")')

old_action = '''  private func actionBar(_ value: ProductionRecommendationV26) -> some View {\n    HStack(spacing: 9) {\n      Button {\n        startCreatorOS()\n      } label: {\n        if isStarting {\n          ProgressView().controlSize(.small)\n        } else {\n          Label("Video erstellen", systemImage: "wand.and.stars")\n        }\n      }\n      .buttonStyle(.borderedProminent).tint(Color.bsRed).foregroundStyle(.white)\n      .disabled(isStarting || selectedChannelID == nil)\n\n      Menu {\n        Button { start(mode: .singleSource) } label: {\n          Label("Als Clip schneiden", systemImage: "scissors")\n        }\n        Button { start(mode: .remix) } label: {\n          Label("Als Remix schneiden", systemImage: "rectangle.3.group")\n        }\n      } label: {\n        Label("Schnittart wählen", systemImage: "slider.horizontal.3")\n      }\n      .menuStyle(.borderlessButton)\n      .disabled(isStarting || selectedChannelID == nil)\n\n      Spacer()\n      Text("English · Captions · Auto-Länge")\n        .font(.system(size: 8.5, weight: .medium)).foregroundStyle(Color.bsMuted)\n    }\n  }\n\n  private func startCreatorOS() {\n    guard let channelID = selectedChannelID else {\n      store.ausgewaehltesZiel = .konten\n      return\n    }\n    isStarting = true\n    Task {\n      let id = await store.v1000ProduktionStarten(chance: chance, channelID: channelID)\n      isStarting = false\n      if id == nil { store.meldung = "Das Video konnte nicht erstellt werden." }\n    }\n  }\n\n  private func start(mode: ProductionModeV11?) {\n    guard let channelID = selectedChannelID else {\n      store.ausgewaehltesZiel = .konten\n      return\n    }\n    isStarting = true\n    Task {\n      let id = await store.v26ProduktionStarten(\n        chance: chance,\n        channelID: channelID,\n        forcedMode: mode)\n      isStarting = false\n      if id == nil {\n        store.meldung = "Die Produktion konnte nicht angelegt werden. Prüfe den verbundenen Channel."\n      }\n    }\n  }'''
new_action = '''  private func actionBar(_ value: ProductionRecommendationV26) -> some View {\n    HStack(spacing: 9) {\n      Button { openNativeRemix() } label: {\n        Label("Auf YouTube remixen", systemImage: "play.rectangle.fill")\n      }\n      .buttonStyle(.borderedProminent).tint(Color.bsRed).foregroundStyle(.white)\n      .disabled(chance.youtubeVideoID == nil)\n\n      Menu {\n        Button { chooseSource(mode: .singleSource) } label: { Label("Clip aus Videodatei", systemImage: "scissors") }\n        Button { chooseSource(mode: .remix) } label: { Label("Remix aus Videodatei", systemImage: "rectangle.3.group") }\n      } label: {\n        if isStarting { ProgressView().controlSize(.small) }\n        else { Label("In Blackstock schneiden", systemImage: "scissors") }\n      }\n      .menuStyle(.borderlessButton)\n      .disabled(isStarting || selectedChannelID == nil)\n\n      Spacer()\n      Text("Originalton · Originalsprache · keine KI-Stimme")\n        .font(.system(size: 8.5, weight: .medium)).foregroundStyle(Color.bsMuted)\n    }\n  }\n\n  private func openNativeRemix() {\n    guard let videoID = chance.youtubeVideoID else { return }\n    let start = max(0, Int(playbackTime.rounded(.down)))\n    var components = URLComponents(string: "https://www.youtube.com/watch")\n    components?.queryItems = [URLQueryItem(name: "v", value: videoID), URLQueryItem(name: "t", value: "\\(start)s")]\n    if let url = components?.url { openURL(url) }\n    store.meldung = start > 0\n      ? "YouTube ist bei \\(durationText(Double(start))) geöffnet. Nutze dort Remix → Ausschneiden."\n      : "YouTube ist geöffnet. Nutze dort Remix → Ausschneiden."\n  }\n\n  private func chooseSource(mode: ProductionModeV11) {\n    pendingMode = mode\n    localSourceImporter = true\n  }\n\n  private func importSource(_ result: Result<[URL], Error>) {\n    switch result {\n    case .success(let urls):\n      guard let sourceURL = urls.first, let channelID = selectedChannelID else { return }\n      isStarting = true\n      let mode = pendingMode\n      Task {\n        _ = await store.v1000ProduktionMitQuelleStarten(chance: chance, channelID: channelID, sourceURL: sourceURL, forcedMode: mode)\n        isStarting = false\n        pendingMode = nil\n      }\n    case .failure(let error):\n      pendingMode = nil\n      store.meldung = error.localizedDescription\n    }\n  }'''
once(trends, old_action, new_action)

# Dashboard: overview only. No source-less AI production buttons in the primary workflow.
once(dashboard, '        hero\n        metrics\n', '        hero\n')
once(dashboard, '          missionsCard\n          productionLane\n          learningCard\n', '          missionsCard\n          productionLane\n')
old_auto = '''          Button {\n            run(mission)\n          } label: {\n            if runningMissionID == mission.id && !importingLocalSource { ProgressView().controlSize(.small) }\n            else { Label("Video erstellen", systemImage: "wand.and.stars") }\n          }\n          .buttonStyle(.borderedProminent).tint(Color.bsRed).foregroundStyle(.white)\n          .disabled(runningMissionID != nil || runningAutopilot || importingLocalSource)'''
new_auto = '''          Button { store.ausgewaehltesZiel = .chancen } label: {\n            Label("Trend ansehen", systemImage: "play.rectangle")\n          }\n          .buttonStyle(.borderedProminent).tint(Color.bsRed).foregroundStyle(.white)'''
once(dashboard, old_auto, new_auto)
old_top3 = '''        Button {\n          guard let channelID = selectedChannelID else { return }\n          runningAutopilot = true\n          Task {\n            await store.v1000AutopilotRun(channelID: channelID)\n            runningAutopilot = false\n          }\n        } label: {\n          if runningAutopilot { ProgressView().controlSize(.small) }\n          else { Label("Top 3 automatisch erstellen", systemImage: "arrow.triangle.2.circlepath") }\n        }\n        .buttonStyle(.bordered)\n        .disabled(selectedChannelID == nil || runningMissionID != nil || runningAutopilot)'''
once(dashboard, old_top3, '')
once(dashboard, '        ForEach(Array(snapshot.missions.prefix(6))) { mission in', '        ForEach(Array(snapshot.missions.prefix(4))) { mission in')
once(dashboard, '            Button("Erstellen") { run(mission) }', '            Button("Ansehen") { store.ausgewaehltesZiel = .chancen }')
all_(dashboard, '.disabled(runningMissionID != nil || runningAutopilot || importingLocalSource)', '.disabled(runningMissionID != nil || importingLocalSource)')

# File-based source edits can choose Clip or Remix directly and never synthesize voice/music.
once(store1000,
     '    sourceURL: URL\n  ) async -> UUID? {',
     '    sourceURL: URL,\n    forcedMode: ProductionModeV11? = nil\n  ) async -> UUID? {')
once(store1000,
     '''    let recommendation = v26Recommendation(for: chance, channelID: channelID)\n    let mission = CreatorOS1000Service.shared.mission(\n      chance: chance,\n      decision: recommendation.decision,\n      hasUsableSource: true,\n      preferredEditMode: recommendation.mode)\n\n    guard let id = await v26ProduktionStarten(\n      chance: chance,\n      channelID: channelID,\n      forcedMode: recommendation.mode,''',
     '''    let recommendation = v26Recommendation(for: chance, channelID: channelID)\n    let editMode = forcedMode ?? recommendation.mode\n    let mission = CreatorOS1000Service.shared.mission(\n      chance: chance,\n      decision: recommendation.decision,\n      hasUsableSource: true,\n      preferredEditMode: editMode)\n\n    guard let id = await v26ProduktionStarten(\n      chance: chance,\n      channelID: channelID,\n      forcedMode: editMode,''')
once(store1000,
     '''      produktionen[index].captionsAktiv = true\n      produktionen[index].watermarkAktiv = true\n      produktionen[index].naechsterSchritt = "\\(mission.executionPath.rawValue) · Quelle analysieren und Master bauen"''',
     '''      produktionen[index].captionsAktiv = true\n      produktionen[index].voiceoverDatei = nil\n      produktionen[index].musikAssetID = nil\n      produktionen[index].watermarkAktiv = true\n      produktionen[index].naechsterSchritt = "Originalmaterial analysieren · Schnitt und Export vorbereiten"''')
once(store11,
     '''      // Blackstock-Standard: jeder neu erzeugte Clip enthält Captions.\n      timeline.captions = true\n      v11TimelineSetzen(timeline, fuer: productionID)''',
     '''      // Source-first: preserve original source audio/language; captions follow the transcript.\n      timeline.captions = true\n      timeline.voiceoverPath = nil\n      timeline.musicSourceAssetID = nil\n      v11TimelineSetzen(timeline, fuer: productionID)''')

# Source language determines metadata; captions already use the original transcript cues.
once(metadata,
     '    let english = profile.language.lowercased().contains("english") || profile.language.lowercased().hasPrefix("en")\n',
     '''    let sourceLanguage = used.compactMap(\\.language)\n      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }\n      .first(where: { !$0.isEmpty }) ?? profile.language\n    let languageKey = sourceLanguage.lowercased()\n    let english = languageKey.contains("english") || languageKey.hasPrefix("en")\n''')
all_(models11, 'Englische Burn-in-Captions sind für Blackstock-Produktionen Pflicht.', 'Burn-in-Captions in der Originalsprache sind für geschnittene Blackstock-Videos Pflicht.')
all_(store26, 'detail: "Englisches Zeittranskript aktualisiert"', 'detail: "Zeittranskript in Originalsprache aktualisiert"')
all_(production, 'setzt englische Captions', 'setzt Captions in der Originalsprache')
all_(production, 'titel: "Schnittquelle",', 'titel: "Originalmaterial",')
all_(production, 'Original-/Lizenzdatei auswählen', 'Videodatei auswählen')

# Hard invariants: no YouTube downloader, no synthetic voice/music on the source-edit renderer.
assert 'case .youtubeReference:\n          throw SourceConnectorError.notDownloadableReference' in store11.read_text()
assert 'voiceover: nil' in store11.read_text()
assert 'musik: nil' in store11.read_text()
assert 'Label("Auf YouTube remixen"' in trends.read_text()
assert 'Originalton · Originalsprache · keine KI-Stimme' in trends.read_text()
assert 'onPlaybackTime' in player.read_text()

print("BLACKSTOCK_NATIVE_REMIX_HOTFIX_OK")
