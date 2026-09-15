from pathlib import Path


def replace_once(path: str, old: str, new: str, label: str) -> None:
    p = Path(path)
    text = p.read_text()
    if old not in text:
        raise SystemExit(f'{label} anchor not found in {path}')
    p.write_text(text.replace(old, new, 1))

# 1) "Ungesehen" must mean actually played, not merely selected/opened.
chancen = 'Sources/Blackstock/Views/ChancenView.swift'
replace_once(
    chancen,
    '    .onChange(of: suche) { _ in keepSelectionValid() }\n    .onChange(of: selectedChanceID) { _ in markSelectedWatched() }\n',
    '    .onChange(of: suche) { _ in keepSelectionValid() }\n',
    'remove selection-as-watched')
replace_once(
    chancen,
    '''  private func markSelectedWatched() {\n    guard let id = selectedChance?.youtubeVideoID else { return }\n    store.v100State.markWatched(id)\n    store.speichern()\n  }\n\n''',
    '',
    'remove markSelectedWatched')
replace_once(
    chancen,
    '''        TextField("Videos, Creator oder Thema", text: $suche)\n          .textFieldStyle(.plain)\n          .onSubmit { rememberSearch() }\n''',
    '''        TextField("Videos, Creator oder Thema", text: $suche)\n          .textFieldStyle(.plain)\n          .onSubmit {\n            rememberSearch()\n            Task { await refresh() }\n          }\n''',
    'live search submit')
replace_once(
    chancen,
    '''  private func refresh() async {\n    store.v100State.trendRefreshCursor = 0\n    _ = await store.chancenAktualisieren(zusaetzlicheMarktThemen: discoveryTerms)\n    keepSelectionValid()\n  }\n\n  private func loadMore() async {\n    _ = await store.chancenMehrLaden(zusaetzlicheMarktThemen: discoveryTerms)\n    keepSelectionValid()\n  }\n''',
    '''  private var activeDiscoveryTerms: [String] {\n    let query = suche.trimmingCharacters(in: .whitespacesAndNewlines)\n    guard !query.isEmpty else { return discoveryTerms }\n    var seen = Set<String>()\n    return ([query] + discoveryTerms).filter { term in\n      let key = term.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)\n      return seen.insert(key).inserted\n    }\n  }\n\n  private func refresh() async {\n    store.v100State.trendRefreshCursor = 0\n    _ = await store.chancenAktualisieren(zusaetzlicheMarktThemen: activeDiscoveryTerms)\n    keepSelectionValid()\n  }\n\n  private func loadMore() async {\n    _ = await store.chancenMehrLaden(zusaetzlicheMarktThemen: activeDiscoveryTerms)\n    keepSelectionValid()\n  }\n''',
    'active search discovery terms')
replace_once(
    chancen,
    '''          YouTubeInlinePlayer(videoID: id) { available, errorCode in\n            updateSourceHealth(videoID: id, available: available, errorCode: errorCode)\n          }\n''',
    '''          YouTubeInlinePlayer(\n            videoID: id,\n            onHealthChange: { available, errorCode in\n              updateSourceHealth(videoID: id, available: available, errorCode: errorCode)\n            },\n            onPlaybackStarted: { markWatched() })\n''',
    'playback watched callback')
replace_once(
    chancen,
    '        .font(.system(size: 8.5)).foregroundStyle(Color.bsMuted)\n        .onAppear { markWatched() }\n',
    '        .font(.system(size: 8.5)).foregroundStyle(Color.bsMuted)\n',
    'remove open-as-watched')

player = 'Sources/Blackstock/Views/YouTubePlayerView.swift'
replace_once(
    player,
    '''struct YouTubeInlinePlayer: View {\n  let videoID: String\n  var onHealthChange: ((Bool, Int?) -> Void)? = nil\n''',
    '''struct YouTubeInlinePlayer: View {\n  let videoID: String\n  var onHealthChange: ((Bool, Int?) -> Void)? = nil\n  var onPlaybackStarted: (() -> Void)? = nil\n''',
    'player playback callback property')
replace_once(
    player,
    '''        case .playing:\n          status = .playing\n          onHealthChange?(true, nil)\n''',
    '''        case .playing:\n          status = .playing\n          onHealthChange?(true, nil)\n          onPlaybackStarted?()\n''',
    'player playback callback fire')

# 2) Explicit UI searches must survive the planner and stay first.
appstore = 'Sources/Blackstock/AppStore.swift'
replace_once(
    appstore,
    '''      let planned = TrendDiscoveryPlannerService.shared.queries(\n        profile: profile, fallbackTopics: marktThemen, history: v100State.queryHistory, cursor: v100State.trendRefreshCursor)\n      let plannedTerms = Array(planned.prefix(12).map(\\.text))\n      var neue = try await youtube.trendChancen(\n        fuer: liveKanaele,\n        zusaetzlicheThemen: plannedTerms.isEmpty ? marktThemen : plannedTerms,\n        discoveryCursor: v100State.trendRefreshCursor)\n''',
    '''      let planned = TrendDiscoveryPlannerService.shared.queries(\n        profile: profile, fallbackTopics: marktThemen, history: v100State.queryHistory, cursor: v100State.trendRefreshCursor)\n      let explicitTerms = zusaetzlicheMarktThemen\n        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }\n        .filter { $0.count >= 2 }\n      var seenTerms = Set<String>()\n      let plannedTerms = (explicitTerms + planned.map(\\.text)).filter { term in\n        let key = term.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)\n        return seenTerms.insert(key).inserted\n      }\n      let discoveryTerms = Array(plannedTerms.prefix(12))\n      var neue = try await youtube.trendChancen(\n        fuer: liveKanaele,\n        zusaetzlicheThemen: discoveryTerms.isEmpty ? marktThemen : discoveryTerms,\n        discoveryCursor: v100State.trendRefreshCursor)\n''',
    'preserve explicit search priority')

# 3) YouTubeService must preserve ranking order instead of alphabetically sorting a Set.
youtube = 'Sources/Blackstock/Services/YouTubeService.swift'
replace_once(
    youtube,
    '''    let alleThemen = Array(\n      Set(\n        (kanaele.map(\\.thema) + zusaetzlicheThemen)\n          .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }\n          .filter { !$0.isEmpty })\n    ).sorted()\n    // Sechs Suchabfragen pro Lauf halten das YouTube-Quota kontrollierbar.\n    // Bei vielen Themen rotiert Blackstock alle drei Stunden durch die Kategorien,\n    // statt dauerhaft nur dieselben sechs Themen zu bevorzugen.\n    let themen: [String] = {\n      guard alleThemen.count > 6 else { return alleThemen }\n      let slot = Int(Date().timeIntervalSince1970 / (3 * 3600))\n      let start = ((slot + discoveryCursor) * 6) % alleThemen.count\n      return (0..<6).map { alleThemen[(start + $0) % alleThemen.count] }\n    }()\n''',
    '''    var seenTopics = Set<String>()\n    let alleThemen = (zusaetzlicheThemen + kanaele.map(\\.thema)).compactMap { raw -> String? in\n      let clean = raw.trimmingCharacters(in: .whitespacesAndNewlines)\n      guard !clean.isEmpty else { return nil }\n      let key = clean.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)\n      guard seenTopics.insert(key).inserted else { return nil }\n      return clean\n    }\n    // Sechs Suchabfragen pro Lauf halten das YouTube-Quota kontrollierbar.\n    // Die Reihenfolge kommt aus dem Discovery-Planner bzw. direkt aus der Nutzersuche;\n    // "Mehr entdecken" rotiert über den Cursor in den nächsten Block.\n    let themen: [String] = {\n      guard alleThemen.count > 6 else { return alleThemen }\n      let start = (discoveryCursor * 6) % alleThemen.count\n      return (0..<6).map { alleThemen[(start + $0) % alleThemen.count] }\n    }()\n''',
    'preserve youtube topic priority')

print('BLACKSTOCK_100_PRODUCT_HOTFIX_APPLIED')
