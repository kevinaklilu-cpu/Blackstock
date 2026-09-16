from pathlib import Path

ROOT = Path.cwd()


def replace_once(path: Path, old: str, new: str, label: str) -> None:
    text = path.read_text()
    if new in text:
        return
    if old not in text:
        raise SystemExit(f"{label}: expected source block not found in {path}")
    path.write_text(text.replace(old, new, 1))


# 1) Integrate optional creative layers into the rights-aware source timeline.
path = ROOT / "Sources/Blackstock/AppStore+V11.swift"
replace_once(
    path,
    '''      // Source-first: preserve original source audio/language; captions follow the transcript.\n      timeline.captions = true\n      timeline.voiceoverPath = nil\n      timeline.musicSourceAssetID = nil\n''',
    '''      // Blackstock Next keeps source audio as the default while allowing optional creative layers.\n      timeline.captions = produktionen[pIndex].captionsAktiv ?? true\n      timeline.voiceoverPath = produktionen[pIndex].voiceoverDatei\n      timeline.musicSourceAssetID = produktionen[pIndex].musikAssetID\n''',
    "timeline creative layers",
)
replace_once(
    path,
    '''      let captionScenes = CaptionTimelineService().scenes(sources: currentSources, timeline: timeline)\n      let render = try await MasterVideoService.shared.rendern(\n        timeline: timeline,\n        sourceURLs: resolvedURLs,\n        optionen: .init(\n          format: timeline.format,\n          voiceover: nil,\n          musik: nil,\n          szenen: captionScenes,\n          captions: timeline.captions && !captionScenes.isEmpty,\n          watermark: watermark),\n        ziel: output)\n''',
    '''      let captionScenes = CaptionTimelineService().scenes(sources: currentSources, timeline: timeline)\n      let voiceoverURL: URL? = {\n        guard let path = produktionen[pIndex].voiceoverDatei,\n          FileManager.default.fileExists(atPath: path)\n        else { return nil }\n        return URL(fileURLWithPath: path)\n      }()\n      let musicURL: URL? = {\n        guard let assetID = produktionen[pIndex].musikAssetID,\n          let asset = medien.first(where: { $0.id == assetID && $0.typ == .audio }),\n          FileManager.default.fileExists(atPath: asset.lokalerPfad)\n        else { return nil }\n        return URL(fileURLWithPath: asset.lokalerPfad)\n      }()\n      let render = try await MasterVideoService.shared.rendern(\n        timeline: timeline,\n        sourceURLs: resolvedURLs,\n        optionen: .init(\n          format: timeline.format,\n          voiceover: voiceoverURL,\n          musik: musicURL,\n          szenen: captionScenes,\n          captions: timeline.captions && !captionScenes.isEmpty,\n          watermark: watermark),\n        ziel: output)\n''',
    "render creative layers",
)
replace_once(
    path,
    '''  func v11ProduktionFortsetzen(_ productionID: UUID) async {\n''',
    '''  func vNextMasterNeuRendern(_ productionID: UUID) async {\n    guard let index = produktionen.firstIndex(where: { $0.id == productionID }) else { return }\n    produktionen[index].lokaleDatei = nil\n    produktionen[index].masterRenderDatum = nil\n    produktionen[index].letzterFehler = nil\n    produktionen[index].naechsterSchritt = "Master wird mit den aktuellen Studio-Layern neu gerendert"\n    produktionen[index].aktualisiertAm = Date()\n    var state = v11Produktion(for: productionID)\n    state.phase = .planning\n    state.renderValidation = nil\n    v11State.upsertProductionState(state)\n    speichern()\n    await v11ProduktionFortsetzen(productionID)\n  }\n\n  func v11ProduktionFortsetzen(_ productionID: UUID) async {\n''',
    "studio rerender",
)

# 2) New projects keep safe defaults but no longer forcibly erase optional layers.
path = ROOT / "Sources/Blackstock/AppStore+V1000.swift"
replace_once(
    path,
    '''      produktionen[index].captionsAktiv = true\n      produktionen[index].voiceoverDatei = nil\n      produktionen[index].musikAssetID = nil\n      produktionen[index].watermarkAktiv = false\n      produktionen[index].publikationsmodus = .review\n      produktionen[index].naechsterSchritt = "Originalmaterial lokal analysieren · hochwertigen Schnitt und Export vorbereiten"\n''',
    '''      produktionen[index].captionsAktiv = true\n      produktionen[index].watermarkAktiv = false\n      produktionen[index].publikationsmodus = .review\n      produktionen[index].naechsterSchritt = "Originalmaterial analysieren · Schnitt, Studio-Layer und Export vorbereiten"\n''',
    "next project defaults",
)

# 3) Make the trend-to-production promise match the integrated product.
path = ROOT / "Sources/Blackstock/Views/ChancenView.swift"
replace_once(
    path,
    'Originalton · Originalsprache · keine KI-Stimme · lokaler Qualitätsrender',
    'Originalton als Standard · Captions, Voice, Musik und Branding optional · lokaler Qualitätsrender',
    "trend studio copy",
)

# 4) Put creator tools directly into the production workspace.
path = ROOT / "Sources/Blackstock/Views/ProduktionsDetailView.swift"
replace_once(
    path,
    '''          productionFlowCard(production)\n          if production.lokaleDatei != nil { reviewCard(production) }\n''',
    '''          productionFlowCard(production)\n          if !sources.isEmpty { creativeStudioCard(production) }\n          if production.lokaleDatei != nil { reviewCard(production) }\n''',
    "studio card placement",
)
replace_once(
    path,
    '''  private func reviewCard(_ p: Produktion) -> some View {\n''',
    '''  private func creativeStudioCard(_ p: Produktion) -> some View {\n    VStack(alignment: .leading, spacing: 12) {\n      AbschnittTitel(\n        titel: "Creator Studio",\n        untertitel: "Originalton bleibt Standard. Zusätzliche Layer sind optional und werden im selben Master gerendert.")\n\n      HStack(spacing: 18) {\n        Toggle("Captions", isOn: Binding(\n          get: { p.captionsAktiv ?? true },\n          set: { store.captionsSetzen(produktionID, aktiv: $0) }))\n          .toggleStyle(.switch)\n        Toggle("Kanal-Branding", isOn: Binding(\n          get: { p.watermarkAktiv ?? false },\n          set: { store.watermarkSetzen(produktionID, aktiv: $0) }))\n          .toggleStyle(.switch)\n        Spacer()\n      }\n      .font(.system(size: 9.5, weight: .medium))\n\n      TextField("Optionales Voiceover-Skript", text: productionBinding(\\.skript), axis: .vertical)\n        .textFieldStyle(.roundedBorder)\n        .lineLimit(3...8)\n\n      HStack(spacing: 8) {\n        Button { Task { await store.voiceoverErzeugen(produktionID) } } label: {\n          Label(p.voiceoverDatei == nil ? "Voiceover erzeugen" : "Voiceover neu erzeugen", systemImage: "waveform.and.mic")\n        }\n        .buttonStyle(.bordered)\n        .disabled(store.istBeschaeftigt || p.skript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)\n\n        Button { Task { await store.musikAutomatischErzeugen(produktionID) } } label: {\n          Label(p.musikAssetID == nil ? "Musik erzeugen" : "Musik bereit", systemImage: "music.note")\n        }\n        .buttonStyle(.bordered)\n        .disabled(store.istBeschaeftigt || p.musikAssetID != nil)\n\n        Button { Task { await store.thumbnailMitAktiverEngineGenerieren(produktionID) } } label: {\n          Label("Thumbnail erzeugen", systemImage: "photo.badge.plus")\n        }\n        .buttonStyle(.bordered)\n        .disabled(store.istBeschaeftigt)\n\n        Spacer()\n\n        Button { Task { await store.vNextMasterNeuRendern(produktionID) } } label: {\n          Label(p.lokaleDatei == nil ? "Master rendern" : "Master neu rendern", systemImage: "sparkles.rectangle.stack")\n        }\n        .buttonStyle(.borderedProminent)\n        .tint(Color.bsRed)\n        .foregroundStyle(.white)\n        .disabled(store.istBeschaeftigt || sources.isEmpty)\n      }\n      .controlSize(.small)\n\n      HStack(spacing: 12) {\n        Label(p.voiceoverDatei == nil ? "Originalton" : "Voiceover-Layer", systemImage: "speaker.wave.2")\n        Label(p.musikAssetID == nil ? "Keine Zusatzmusik" : "Musik-Layer", systemImage: "music.quarternote.3")\n        Label(p.watermarkAktiv == true ? "Branding aktiv" : "Branding aus", systemImage: "signature")\n      }\n      .font(.system(size: 8.8))\n      .foregroundStyle(Color.bsMuted)\n    }\n    .blackstockCard(elevated: true)\n  }\n\n  private func reviewCard(_ p: Produktion) -> some View {\n''',
    "integrated creator studio",
)
replace_once(
    path,
    'AbschnittTitel(titel: "Finale Metadaten", untertitel: "Werden nach der tatsächlichen Timeline erzeugt und bleiben editierbar")',
    'AbschnittTitel(titel: "Packaging Lab", untertitel: "Drei Titel- und Thumbnail-Richtungen aus der tatsächlichen Timeline – editierbar vor dem Upload")',
    "packaging lab",
)

# 5) Present the product as one integrated creator system rather than a patch generation.
path = ROOT / "Sources/Blackstock/Views/CreatorOS1000View.swift"
replace_once(
    path,
    'Quellvideo finden, stärksten Moment analysieren und mit Originalmaterial lokal schneiden.',
    'Trend verstehen, stärksten Moment planen und Originalmaterial mit optionalen Studio-Layern produzieren.',
    "creator dashboard copy",
)
replace_once(
    path,
    'StatusPunkt(text: "Source-first · lokal", farbe: .bsGreen)',
    'StatusPunkt(text: "Creator Intelligence · integriert", farbe: .bsGreen)',
    "creator dashboard status",
)

# 6) Release audit must validate the integrated architecture, not enforce disabled tools.
path = ROOT / "Build/Release-Audit.sh"
replace_once(
    path,
    '''grep -q 'Originalton · Originalsprache · keine KI-Stimme' "$ROOT/Sources/Blackstock/Views/ChancenView.swift" || fail "Originalton-Sicherheitsregel fehlt"''',
    '''grep -q 'Originalton als Standard' "$ROOT/Sources/Blackstock/Views/ChancenView.swift" || fail "Originalton-Standard fehlt"''',
    "audit original audio",
)
replace_once(
    path,
    '''grep -q 'voiceover: nil' "$ROOT/Sources/Blackstock/AppStore+V11.swift" || fail "Voiceover muss im Source-Edit deaktiviert sein"\ngrep -q 'musik: nil' "$ROOT/Sources/Blackstock/AppStore+V11.swift" || fail "Zusatzmusik muss im Source-Edit deaktiviert sein"''',
    '''grep -q 'voiceover: voiceoverURL' "$ROOT/Sources/Blackstock/AppStore+V11.swift" || fail "Optionaler Voiceover-Layer fehlt"\ngrep -q 'musik: musicURL' "$ROOT/Sources/Blackstock/AppStore+V11.swift" || fail "Optionaler Musik-Layer fehlt"\ngrep -q 'Creator Studio' "$ROOT/Sources/Blackstock/Views/ProduktionsDetailView.swift" || fail "Integriertes Creator Studio fehlt"\ngrep -q 'vNextMasterNeuRendern' "$ROOT/Sources/Blackstock/AppStore+V11.swift" || fail "Studio-Rerender fehlt"''',
    "audit integrated studio",
)

manifest = ROOT / "RELEASE_MANIFEST.txt"
manifest_text = manifest.read_text()
if "Product generation: Blackstock Next" not in manifest_text:
    manifest.write_text(manifest_text.rstrip() + "\nProduct generation: Blackstock Next\nArchitecture: Creator Intelligence + Trends + Studio + Publishing + Analytics\n")

print("BLACKSTOCK_NEXT_GENERATION_OK")
