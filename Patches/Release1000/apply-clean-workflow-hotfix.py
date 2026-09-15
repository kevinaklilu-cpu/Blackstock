from pathlib import Path

repo = Path.cwd()


def once(path, old, new):
    text = path.read_text()
    if new in text:
        return
    if old not in text:
        raise SystemExit(f"missing in {path}: {old[:120]!r}")
    path.write_text(text.replace(old, new, 1))


def all_(path, old, new):
    text = path.read_text()
    if old in text:
        path.write_text(text.replace(old, new))
    elif new not in text:
        raise SystemExit(f"missing in {path}: {old!r}")


def section(path, start, end, new):
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


trends = repo / "Sources/Blackstock/Views/ChancenView.swift"
dashboard = repo / "Sources/Blackstock/Views/CreatorOS1000View.swift"
production = repo / "Sources/Blackstock/Views/ProduktionsDetailView.swift"

# Trends: search first. Duration/date/library live behind one familiar filter control.
once(
    trends,
    'untertitel: "Finde aktuelle YouTube-Videos, spiele sie direkt ab und erstelle daraus mit Blackstock den passenden Clip, Remix, Short oder ein neues Video.",',
    'untertitel: "YouTube-Trends entdecken, direkt ansehen und als Remix oder Clip weiterverwenden.",')
controls = '''  private var controls: some View {\n    VStack(spacing: 8) {\n      HStack(spacing: 10) {\n        Picker("Kanal", selection: $selectedChannelID) {\n          Text("Kanal auswählen").tag(UUID?.none)\n          ForEach(store.liveKanaele) { channel in Text(channel.name).tag(Optional(channel.id)) }\n        }\n        .frame(width: 200)\n\n        HStack(spacing: 8) {\n          Image(systemName: "magnifyingglass").foregroundStyle(Color.bsMuted)\n          TextField("Videos, Creator oder Thema", text: $suche)\n            .textFieldStyle(.plain)\n            .onSubmit {\n              rememberSearch()\n              Task { await refresh() }\n            }\n          if !recentSearches.isEmpty {\n            Menu {\n              ForEach(recentSearches, id: \\.self) { query in\n                Button(query) {\n                  suche = query\n                  Task { await refresh() }\n                }\n              }\n            } label: { Image(systemName: "clock.arrow.circlepath") }\n            .menuStyle(.borderlessButton).fixedSize()\n          }\n          if !suche.isEmpty {\n            Button { suche = "" } label: { Image(systemName: "xmark.circle.fill") }\n              .buttonStyle(.plain).foregroundStyle(Color.bsMuted)\n          }\n        }\n        .padding(.horizontal, 11).frame(maxWidth: .infinity, minHeight: 36)\n        .background(Color.bsSurface2).clipShape(RoundedRectangle(cornerRadius: 9))\n      }\n\n      HStack(spacing: 14) {\n        Menu {\n          Section("Länge") {\n            ForEach(TrendSourceDurationFilter.allCases) { item in Button(item.rawValue) { durationFilter = item } }\n          }\n          Section("Zeitraum") {\n            ForEach(TrendAgeFilter.allCases) { item in Button(item.rawValue) { ageFilter = item } }\n          }\n          Section("Bibliothek") {\n            ForEach(TrendLibraryFilter.allCases) { item in Button(item.rawValue) { libraryFilter = item } }\n          }\n        } label: { Label("Filter", systemImage: "line.3.horizontal.decrease") }\n        .menuStyle(.borderlessButton).fixedSize()\n\n        Menu {\n          ForEach(TrendSortierung.allCases) { item in Button(item.rawValue) { sortierung = item } }\n        } label: { Label(sortierung.rawValue, systemImage: "arrow.up.arrow.down") }\n        .menuStyle(.borderlessButton).fixedSize()\n\n        Text("\\(durationFilter.rawValue) · \\(ageFilter.rawValue)")\n          .font(.system(size: 9)).foregroundStyle(Color.bsMuted2)\n        Spacer()\n      }\n      .font(.system(size: 9.5))\n    }\n    .padding(10)\n    .background(Color.bsSurface)\n    .clipShape(RoundedRectangle(cornerRadius: 12))\n    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.bsBorder))\n  }\n\n'''
section(trends, '  private var controls: some View {', '  private var topicStrip: some View {', controls)
result_header = '''  private var resultHeader: some View {\n    HStack(spacing: 8) {\n      Text("\\(filtered.count) Videos")\n        .font(.system(size: 10.5, weight: .semibold)).foregroundStyle(Color.bsText)\n      Spacer()\n      if let selectedChannelID, let topic = store.blackstockTopic(for: selectedChannelID) {\n        Label(topic.rawValue, systemImage: "scope")\n          .font(.system(size: 9, weight: .medium)).foregroundStyle(Color.bsMuted)\n      }\n      Button { Task { await loadMore() } } label: { Label("Mehr", systemImage: "plus.circle") }\n        .buttonStyle(.borderless)\n        .disabled(store.istBeschaeftigt || store.googleZugaenge.isEmpty)\n    }\n  }\n\n'''
section(trends, '  private var resultHeader: some View {', '  private var feed: some View {', result_header)
all_(trends,
     'Text("Blackstock: \\(recommendation.actionLabel) → \\(recommendation.formatLabel) \\(recommendation.durationLabel)")',
     'Text("\\(recommendation.formatLabel) · \\(recommendation.durationLabel)")')
all_(trends,
     'Text("Originalmaterial ohne Download: Nutze YouTubes eigene Remix-/Ausschneiden-Funktion. Für einen vollständigen Blackstock-MP4-Export wählst du eine Videodatei, die du verwenden darfst.")',
     'Text("YouTube-Remix nutzt das Original. Für einen Blackstock-MP4-Export wählst du eine Videodatei, die du verwenden darfst.")')
once(trends,
     '''        HStack(spacing: 8) {\n          Label("Quelle: \\(chance.youtubeDurationSeconds.map(durationText) ?? "–")", systemImage: "film")\n          Label("Originalsprache", systemImage: "captions.bubble")\n          if chance.canEmbedYouTube { Label("Player bereit", systemImage: "play.rectangle") }\n          if let id = chance.youtubeVideoID, store.v100State.sourceHealth[id]?.available == false {\n            Label("Player blockiert", systemImage: "exclamationmark.triangle.fill")\n              .foregroundStyle(Color.bsAmber)\n          }\n          if let id = chance.youtubeVideoID, store.v100State.watchedVideoIDs.contains(id) {\n            Label("angesehen", systemImage: "checkmark.circle.fill")\n          }\n          Spacer()\n''',
     '''        HStack(spacing: 8) {\n          if let duration = chance.youtubeDurationSeconds { Label(durationText(duration), systemImage: "clock") }\n          Label("Originalsprache", systemImage: "captions.bubble")\n          Spacer()\n''')

# Dashboard: overview, not automation console. Remove internal execution jargon and the last top-3 autopilot control.
text = dashboard.read_text()
start = '        Button {\n          guard let channelID = selectedChannelID else { return }\n          runningAutopilot = true\n'
a = text.find(start)
if a >= 0:
    end = '        .disabled(selectedChannelID == nil || runningMissionID != nil || runningAutopilot)\n'
    b = text.find(end, a)
    if b < 0:
        raise SystemExit('dashboard top3 end missing')
    dashboard.write_text(text[:a] + text[b + len(end):])
all_(dashboard,
     'Text("\\(mission.executionPath.rawValue) · \\(mission.formatLabel) · \\(mission.durationLabel) · Score \\(Int(mission.score.rounded()))")',
     'Text("\\(mission.formatLabel) · \\(mission.durationLabel)")')
all_(dashboard,
     'Text("\\(mission.executionPath.rawValue) · \\(mission.formatLabel) · \\(mission.durationLabel)")',
     'Text("\\(mission.formatLabel) · \\(mission.durationLabel)")')

# Production: one four-step path. Detailed source/timeline controls stay available, but collapsed.
once(production,
     '''          if let source = production.chanceSnapshot { trendSourceCard(source) }\n          pipelineCard(production)\n          sourcesCard\n          if let editBlueprint { editBlueprintCard(editBlueprint) }\n          if let timeline = state.timeline { timelineCard(timeline) }\n          if production.lokaleDatei != nil { reviewCard(production) }\n          metadataCard(production)\n          readyCard(production)''',
     '''          if let source = production.chanceSnapshot { trendSourceCard(source) }\n          productionFlowCard(production)\n          if production.lokaleDatei != nil { reviewCard(production) }\n          metadataCard(production)\n          readyCard(production)\n\n          DisclosureGroup("Schnittdetails & Quellen") {\n            VStack(alignment: .leading, spacing: 14) {\n              sourcesCard\n              if let editBlueprint { editBlueprintCard(editBlueprint) }\n              if let timeline = state.timeline { timelineCard(timeline) }\n            }\n            .padding(.top, 10)\n          }\n          .font(.system(size: 10, weight: .semibold))\n          .foregroundStyle(Color.bsMuted)''')
flow_card = '''  private func productionFlowCard(_ p: Produktion) -> some View {\n    VStack(alignment: .leading, spacing: 12) {\n      AbschnittTitel(titel: "Erstellen", untertitel: "Originalmaterial → Schnitt → Vorschau → Veröffentlichen")\n      BlackstockFortschritt(wert: state.progress, farbe: .bsRed)\n\n      if sources.isEmpty {\n        HStack(alignment: .center, spacing: 12) {\n          VStack(alignment: .leading, spacing: 4) {\n            Text("Wie möchtest du weitermachen?")\n              .font(.system(size: 11, weight: .semibold)).foregroundStyle(Color.bsText)\n            Text("YouTube-Originalmaterial läuft über Remix/Ausschneiden. Für einen Blackstock-MP4-Export wählst du eine Videodatei, die du verwenden darfst.")\n              .font(.system(size: 9)).foregroundStyle(Color.bsMuted)\n          }\n          Spacer()\n          if p.chanceSnapshot?.youtubeVideoID != nil {\n            Button("Zum Trend") { store.ausgewaehltesZiel = .chancen }.buttonStyle(.bordered)\n          }\n          Button { localSourceImporter = true } label: {\n            if importingLocalSource { ProgressView().controlSize(.small) }\n            else { Label("Videodatei wählen", systemImage: "plus.rectangle.on.folder") }\n          }\n          .buttonStyle(.borderedProminent).tint(Color.bsRed).foregroundStyle(.white)\n          .disabled(importingLocalSource || store.istBeschaeftigt)\n        }\n      } else if p.lokaleDatei == nil {\n        HStack(spacing: 12) {\n          VStack(alignment: .leading, spacing: 3) {\n            StatusPunkt(text: state.phase.rawValue, farbe: state.phase == .failed ? .bsRed : .bsGreen)\n            Text(state.checkpoint?.detail ?? p.naechsterSchritt)\n              .font(.system(size: 9)).foregroundStyle(Color.bsMuted)\n          }\n          Spacer()\n          Button(state.phase == .failed ? "Erneut versuchen" : "Schnitt erstellen") {\n            Task { await store.v48ProduktionFortsetzen(produktionID) }\n          }\n          .buttonStyle(.borderedProminent).tint(Color.bsRed).foregroundStyle(.white)\n          .disabled(store.istBeschaeftigt)\n        }\n      } else {\n        HStack(spacing: 8) {\n          Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.bsGreen)\n          Text("Video fertig erstellt").font(.system(size: 11, weight: .semibold)).foregroundStyle(Color.bsText)\n          Text("· Originalton · Originalsprache").font(.system(size: 9)).foregroundStyle(Color.bsMuted)\n          Spacer()\n        }\n      }\n    }\n    .blackstockCard(14, elevated: true)\n  }\n\n'''
section(production, '  private func pipelineCard(_ p: Produktion) -> some View {', '  private var sourcesCard: some View {', flow_card)
all_(production,
     'Clip-Modus · stärkste Momente aus einer bereitgestellten Original-/Lizenzdatei',
     'Clip · stärkste Momente aus deiner Videodatei')
all_(production,
     'untertitel: "YouTube liefert Blackstock den Player und die Trenddaten, aber keine Videodatei zum Schneiden. Wähle hier die Original-/Lizenzdatei, die zu diesem Trendvideo gehört.")',
     'untertitel: "Erweiterte Quellenverwaltung für den Blackstock-MP4-Export.")')
all_(production,
     'Label("Für den Render fehlt noch die bearbeitbare Videodatei", systemImage: "film.badge.plus")',
     'Label("Für den MP4-Export fehlt eine Videodatei", systemImage: "film.badge.plus")')

# Visible product guardrails.
assert 'Top 3 automatisch erstellen' not in dashboard.read_text()
assert 'private var controls: some View {\n    VStack' in trends.read_text()
assert 'Label("Filter", systemImage: "line.3.horizontal.decrease")' in trends.read_text()
assert 'Text("Originalton · Originalsprache · keine KI-Stimme")' in trends.read_text()
assert 'DisclosureGroup("Schnittdetails & Quellen")' in production.read_text()
assert 'AbschnittTitel(titel: "Erstellen"' in production.read_text()

print("BLACKSTOCK_CLEAN_WORKFLOW_HOTFIX_OK")
