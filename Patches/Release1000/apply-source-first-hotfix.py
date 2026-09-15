from pathlib import Path

repo = Path.cwd()
trends = repo / "Sources/Blackstock/Views/ChancenView.swift"
dashboard = repo / "Sources/Blackstock/Views/CreatorOS1000View.swift"
production = repo / "Sources/Blackstock/Views/ProduktionsDetailView.swift"
store1000 = repo / "Sources/Blackstock/AppStore+V1000.swift"
renderer = repo / "Sources/Blackstock/Services/TimelineRendererService.swift"
audit = repo / "Build/Release-Audit.sh"


def once(path: Path, old: str, new: str):
    text = path.read_text()
    if new in text:
        return
    if old not in text:
        raise SystemExit(f"missing in {path}: {old[:140]!r}")
    path.write_text(text.replace(old, new, 1))


def all_if_present(path: Path, old: str, new: str):
    text = path.read_text()
    if old in text:
        path.write_text(text.replace(old, new))


def section(path: Path, start: str, end: str, new: str):
    text = path.read_text()
    a = text.find(start)
    if a < 0:
        if new.strip() in text:
            return
        raise SystemExit(f"start missing in {path}: {start!r}")
    b = text.find(end, a)
    if b < 0:
        raise SystemExit(f"end missing in {path}: {end!r}")
    path.write_text(text[:a] + new + text[b:])


# macOS-native rights confirmation. Blackstock never claims to certify ownership;
# it requires the user to confirm a permitted local source before Blackstock renders it.
for path in (trends, dashboard):
    text = path.read_text()
    if "import AppKit\n" not in text:
        if "import UniformTypeIdentifiers\n" in text:
            text = text.replace("import UniformTypeIdentifiers\n", "import UniformTypeIdentifiers\nimport AppKit\n", 1)
        else:
            text = text.replace("import SwiftUI\n", "import SwiftUI\nimport AppKit\n", 1)
        path.write_text(text)

# Channel identity is the source of truth. Switching channel also switches the internally
# used topic to that channel's detected Blackstock topic.
once(
    trends,
    '''        .frame(width: 200)\n\n        HStack(spacing: 8) {''',
    '''        .frame(width: 200)\n        .onChange(of: selectedChannelID) { channelID in\n          guard let channelID, let topic = store.blackstockTopic(for: channelID) else { return }\n          store.v10Thema = topic\n        }\n\n        HStack(spacing: 8) {''')

topic_strip = '''  private var topicStrip: some View {\n    HStack(spacing: 9) {\n      Image(systemName: "lock.fill")\n        .font(.system(size: 9, weight: .semibold))\n        .foregroundStyle(Color.bsMuted)\n      if let selectedChannelID, let topic = store.blackstockTopic(for: selectedChannelID) {\n        Text("\\(topic.rawValue) · Kanalthema")\n          .font(.system(size: 10, weight: .semibold))\n          .foregroundStyle(Color.bsText)\n      } else {\n        Text("Kanalthema wird aus dem verbundenen Kanal erkannt")\n          .font(.system(size: 10, weight: .semibold))\n          .foregroundStyle(Color.bsText)\n      }\n      Spacer()\n      Text("automatisch erkannt")\n        .font(.system(size: 9))\n        .foregroundStyle(Color.bsMuted2)\n    }\n    .padding(.horizontal, 10)\n    .padding(.vertical, 8)\n    .background(Color.bsSurface)\n    .clipShape(RoundedRectangle(cornerRadius: 10))\n    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.bsBorder))\n  }\n\n'''
section(trends, "  private var topicStrip: some View {", "  private var resultHeader: some View {", topic_strip)

# Rights confirmation for file-based cutting from Trends.
old_import_source = '''  private func importSource(_ result: Result<[URL], Error>) {\n    switch result {\n    case .success(let urls):\n      guard let sourceURL = urls.first, let channelID = selectedChannelID else { return }\n      isStarting = true\n      let mode = pendingMode\n      Task {\n        _ = await store.v1000ProduktionMitQuelleStarten(chance: chance, channelID: channelID, sourceURL: sourceURL, forcedMode: mode)\n        isStarting = false\n        pendingMode = nil\n      }\n    case .failure(let error):\n      pendingMode = nil\n      store.meldung = error.localizedDescription\n    }\n  }'''
new_import_source = '''  private func importSource(_ result: Result<[URL], Error>) {\n    switch result {\n    case .success(let urls):\n      guard let sourceURL = urls.first, let channelID = selectedChannelID else { return }\n      guard confirmCommercialRights(for: sourceURL) else {\n        pendingMode = nil\n        store.meldung = "Lokaler Export abgebrochen. Blackstock rendert nur Quelldateien, deren Nutzung du bestätigt hast."\n        return\n      }\n      isStarting = true\n      let mode = pendingMode\n      Task {\n        _ = await store.v1000ProduktionMitQuelleStarten(chance: chance, channelID: channelID, sourceURL: sourceURL, forcedMode: mode)\n        isStarting = false\n        pendingMode = nil\n      }\n    case .failure(let error):\n      pendingMode = nil\n      store.meldung = error.localizedDescription\n    }\n  }\n\n  private func confirmCommercialRights(for sourceURL: URL) -> Bool {\n    let alert = NSAlert()\n    alert.alertStyle = .informational\n    alert.messageText = "Nutzungsrechte bestätigen"\n    alert.informativeText = "Ich bestätige, dass ich diese Quelldatei bearbeiten und für den vorgesehenen Zweck verwenden darf. Die Datei bleibt lokal auf diesem Mac und wird von Blackstock nicht als YouTube-Download beschafft."\n    alert.addButton(withTitle: "Bestätigen & schneiden")\n    alert.addButton(withTitle: "Abbrechen")\n    return alert.runModal() == .alertFirstButtonReturn\n  }'''
once(trends, old_import_source, new_import_source)

# Dashboard is an opportunity overview, not a synthetic-video generator.
run_only = '''  private func run(_ mission: CreatorMission1000) {\n    store.ausgewaehltesZiel = .chancen\n    store.meldung = "Blackstock erzeugt hier kein künstliches Ersatzvideo. Öffne den Trend für YouTube Remix oder wähle eine erlaubte Videodatei für den lokalen Schnitt."\n  }\n\n'''
section(dashboard, "  private func run(_ mission: CreatorMission1000) {", "  private func sourceActionLabel(for mission: CreatorMission1000) -> String {", run_only)

old_dashboard_import = '''  private func importLicensedSource(_ result: Result<[URL], Error>) {\n    switch result {\n    case .success(let urls):\n      guard let sourceURL = urls.first,\n            let mission = sourceMission,\n            let channelID = selectedChannelID,\n            let chance = store.chancen.first(where: { $0.id == mission.chanceID })\n      else {\n        sourceMission = nil\n        return\n      }\n      importingLocalSource = true\n      runningMissionID = mission.id\n      Task {\n        _ = await store.v1000ProduktionMitQuelleStarten(\n          chance: chance, channelID: channelID, sourceURL: sourceURL)\n        importingLocalSource = false\n        runningMissionID = nil\n        sourceMission = nil\n      }\n    case .failure(let error):\n      sourceMission = nil\n      store.meldung = error.localizedDescription\n    }\n  }'''
new_dashboard_import = '''  private func importLicensedSource(_ result: Result<[URL], Error>) {\n    switch result {\n    case .success(let urls):\n      guard let sourceURL = urls.first,\n            let mission = sourceMission,\n            let channelID = selectedChannelID,\n            let chance = store.chancen.first(where: { $0.id == mission.chanceID })\n      else {\n        sourceMission = nil\n        return\n      }\n      guard confirmCommercialRights(for: sourceURL) else {\n        sourceMission = nil\n        store.meldung = "Lokaler Export abgebrochen. Blackstock rendert nur Quelldateien, deren Nutzung du bestätigt hast."\n        return\n      }\n      importingLocalSource = true\n      runningMissionID = mission.id\n      Task {\n        _ = await store.v1000ProduktionMitQuelleStarten(\n          chance: chance, channelID: channelID, sourceURL: sourceURL)\n        importingLocalSource = false\n        runningMissionID = nil\n        sourceMission = nil\n      }\n    case .failure(let error):\n      sourceMission = nil\n      store.meldung = error.localizedDescription\n    }\n  }\n\n  private func confirmCommercialRights(for sourceURL: URL) -> Bool {\n    let alert = NSAlert()\n    alert.alertStyle = .informational\n    alert.messageText = "Nutzungsrechte bestätigen"\n    alert.informativeText = "Ich bestätige, dass ich diese Quelldatei bearbeiten und für den vorgesehenen Zweck verwenden darf. Die Datei bleibt lokal auf diesem Mac und wird von Blackstock nicht als YouTube-Download beschafft."\n    alert.addButton(withTitle: "Bestätigen & schneiden")\n    alert.addButton(withTitle: "Abbrechen")\n    return alert.runModal() == .alertFirstButtonReturn\n  }'''
once(dashboard, old_dashboard_import, new_dashboard_import)

# Product language: existing material is cut; Blackstock does not promise synthetic replacement videos.
all_if_present(dashboard,
    "Vom Trend direkt zum fertigen Video – Quelle waehlen, Blackstock schneidet, Untertitel an, fertig.",
    "Bestehende Videos intelligent schneiden – Originalquelle wählen, besten Moment finden, hochwertig exportieren.")
all_if_present(dashboard, 'Label("Video erstellen", systemImage: "wand.and.stars")', 'Label("Video schneiden", systemImage: "scissors")')
all_if_present(production, 'AbschnittTitel(titel: "Erstellen", untertitel: "Originalmaterial → Schnitt → Vorschau → Veröffentlichen")', 'AbschnittTitel(titel: "Schneiden", untertitel: "Originalmaterial → Schnitt → Vorschau → Export")')
all_if_present(production,
    'Text("YouTube-Originalmaterial läuft über Remix/Ausschneiden. Für einen Blackstock-MP4-Export wählst du eine Videodatei, die du verwenden darfst.")',
    'Text("YouTube-Material bleibt im offiziellen Remix/Ausschneiden-Workflow. Für einen lokalen Blackstock-Export wählst du eine erlaubte Videodatei; sie bleibt auf diesem Mac und wird nicht zu Blackstock hochgeladen.")')

# Source-first rendering never forces branding, AI voice or extra music onto source material.
once(store1000, "      produktionen[index].watermarkAktiv = true\n      produktionen[index].naechsterSchritt = \"Originalmaterial analysieren · Schnitt und Export vorbereiten\"", "      produktionen[index].watermarkAktiv = false\n      produktionen[index].naechsterSchritt = \"Originalmaterial analysieren · Schnitt und Export vorbereiten\"")

# Prefer the highest-quality AVFoundation export preset whenever an older fixed/medium preset
# is used by the renderer. Keep a single final render and do not enable network optimization.
if renderer.exists():
    for preset in (
        "AVAssetExportPresetLowQuality",
        "AVAssetExportPresetMediumQuality",
        "AVAssetExportPreset1280x720",
        "AVAssetExportPreset1920x1080",
    ):
        all_if_present(renderer, preset, "AVAssetExportPresetHighestQuality")
    all_if_present(renderer, "shouldOptimizeForNetworkUse = true", "shouldOptimizeForNetworkUse = false")
    text = renderer.read_text()
    marker = "// BLACKSTOCK_SOURCE_FIRST_HIGH_QUALITY: preserve source media and use highest-quality final export.\n"
    if marker not in text:
        renderer.write_text(marker + text)

# Harden the release audit around the new contract.
audit_text = audit.read_text()
audit_marker = "# BLACKSTOCK_SOURCE_FIRST_AUDIT"
if audit_marker not in audit_text:
    audit_text += r'''

# BLACKSTOCK_SOURCE_FIRST_AUDIT
grep -q 'Nutzungsrechte bestätigen' "$ROOT/Sources/Blackstock/Views/ChancenView.swift" || fail "Rechtebestätigung im Trend-Schnitt fehlt"
grep -q 'Die Datei bleibt lokal auf diesem Mac' "$ROOT/Sources/Blackstock/Views/ChancenView.swift" || fail "Local-only-Hinweis fehlt"
grep -q 'Text("\\(topic.rawValue) · Kanalthema")' "$ROOT/Sources/Blackstock/Views/ChancenView.swift" || fail "Kanalthema-Lock fehlt"
! grep -q 'Picker("Thema", selection: \$store.v10Thema)' "$ROOT/Sources/Blackstock/Views/ChancenView.swift" || fail "Manuelle Themenumschaltung ist noch sichtbar"
grep -q 'watermarkAktiv = false' "$ROOT/Sources/Blackstock/AppStore+V1000.swift" || fail "Source-Edit erzwingt noch Branding"
grep -q 'BLACKSTOCK_SOURCE_FIRST_HIGH_QUALITY' "$ROOT/Sources/Blackstock/Services/TimelineRendererService.swift" || fail "High-Quality-Renderer-Guardrail fehlt"
grep -q 'Blackstock erzeugt hier kein künstliches Ersatzvideo' "$ROOT/Sources/Blackstock/Views/CreatorOS1000View.swift" || fail "Source-first Dashboard-Guardrail fehlt"
'''
    audit.write_text(audit_text)

# Reconstruction-time invariants.
assert 'Picker("Thema", selection: $store.v10Thema)' not in trends.read_text()
assert 'Nutzungsrechte bestätigen' in trends.read_text()
assert 'Die Datei bleibt lokal auf diesem Mac' in trends.read_text()
assert 'Blackstock erzeugt hier kein künstliches Ersatzvideo' in dashboard.read_text()
assert 'watermarkAktiv = false' in store1000.read_text()
assert 'voiceover: nil' in (repo / "Sources/Blackstock/AppStore+V11.swift").read_text()
assert 'musik: nil' in (repo / "Sources/Blackstock/AppStore+V11.swift").read_text()
assert 'case .youtubeReference:\n          throw SourceConnectorError.notDownloadableReference' in (repo / "Sources/Blackstock/AppStore+V11.swift").read_text()

print("BLACKSTOCK_SOURCE_FIRST_HOTFIX_OK")
