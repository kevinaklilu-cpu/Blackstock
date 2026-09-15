from pathlib import Path

repo = Path.cwd()


def replace(path: Path, old: str, new: str, *, count=None):
    text = path.read_text()
    if old not in text:
        if new in text:
            return
        raise SystemExit(f"Expected text missing in {path}: {old!r}")
    text = text.replace(old, new) if count is None else text.replace(old, new, count)
    path.write_text(text)

models = repo / "Sources/Blackstock/Models/Models.swift"
sidebar = repo / "Sources/Blackstock/Views/SidebarView.swift"
dashboard = repo / "Sources/Blackstock/Views/CreatorOS1000View.swift"
trends = repo / "Sources/Blackstock/Views/ChancenView.swift"
store = repo / "Sources/Blackstock/AppStore+V1000.swift"
factory = repo / "Sources/Blackstock/Views/ContentFactoryView.swift"

# Navigation uses familiar YouTube Studio / editor language. Version numbers stay internal only.
replace(models, 'case .command: "Creator OS"', 'case .command: "Dashboard"')
replace(models, 'case .produktionen: "Produktionen"', 'case .produktionen: "Erstellen"')
replace(models, 'case .konten: "Kanäle"', 'case .konten: "Kanal"')
replace(sidebar, 'Text("BLACKSTOCK 1000")', 'Text("BLACKSTOCK")')

# Dashboard: remove architecture jargon while keeping the proven engine underneath.
replacements = {
    'titel: "Creator OS",': 'titel: "Dashboard",',
    'untertitel: "Blackstock 1000 entscheidet, produziert, prüft und lernt – mit Review vor Publishing als sicherem Standard.",': 'untertitel: "Dein nächstes YouTube-Video – von der Trendidee bis zum Upload.",',
    'text: "Creator OS braucht einen verbundenen YouTube-Kanal, damit Trends, Formatwahl, Produktion und Learning auf denselben Kontext zeigen.",': 'text: "Verbinde deinen YouTube-Kanal, damit Blackstock Trends, Formate, Uploads und Analytics auf deinen Kanal abstimmen kann.",',
    'Text("BLACKSTOCK 1000")': 'Text("NÄCHSTES VIDEO")',
    'Text(selectedChannel == nil ? "Ein System statt 20 Einzelfunktionen" : "Neue Chancen laden")': 'Text(selectedChannel == nil ? "Kanal verbinden und loslegen" : "Neue Videoideen finden")',
    'Text("Trend → Entscheidung → Original Build oder lizenzierter Edit → Quality Gate → Review → Publish → Learning")': 'Text("Trends finden, Clip oder Video erstellen, prüfen und auf YouTube veröffentlichen.")',
    'Text("SYSTEM \\(Int(snapshot.systemScore.rounded()))")': 'Text("CHANCE \\(Int(snapshot.bestMission?.score.rounded() ?? snapshot.systemScore.rounded()))")',
    'Label("Bestes Video produzieren", systemImage: "bolt.fill")': 'Label("Video erstellen", systemImage: "wand.and.stars")',
    'Label("Autopilot · Top 3", systemImage: "arrow.triangle.2.circlepath")': 'Label("Top 3 automatisch erstellen", systemImage: "arrow.triangle.2.circlepath")',
    'metric("Chancen", snapshot.trendCount, "sparkles.tv")': 'metric("Trends", snapshot.trendCount, "sparkles.tv")',
    'metric("In Arbeit", snapshot.activeProductionCount, "film.stack")': 'metric("In Produktion", snapshot.activeProductionCount, "film.stack")',
    'metric("Blockiert", snapshot.blockedProductionCount, "exclamationmark.triangle.fill")': 'metric("Prüfen", snapshot.blockedProductionCount, "exclamationmark.triangle.fill")',
    'metric("Learning", snapshot.learningSignalCount, "brain.head.profile")': 'metric("Signale", snapshot.learningSignalCount, "chart.xyaxis.line")',
    'AbschnittTitel(titel: "Nächste Missionen", untertitel: "Keine Karten-Sammlung: jede Zeile ist eine priorisierte, ausführbare Entscheidung")': 'AbschnittTitel(titel: "Videoideen", untertitel: "Nach Potenzial für deinen Kanal sortiert")',
    'Text("Noch keine neue Mission. Aktualisiere Trends oder prüfe ausgeblendete Quellen.")': 'Text("Noch keine passenden Videoideen. Aktualisiere die Trends oder starte eine neue Suche.")',
    'Button("Produzieren") { run(mission) }': 'Button("Erstellen") { run(mission) }',
    'AbschnittTitel(titel: "Production Lane", untertitel: "Ein Blick auf aktive Master, Reviews und Blocker")': 'AbschnittTitel(titel: "In Produktion", untertitel: "Aktive Videos, Freigaben und offene Schritte")',
    'Button("Studio öffnen") { store.ausgewaehltesZiel = .produktionen }': 'Button("Erstellen öffnen") { store.ausgewaehltesZiel = .produktionen }',
    'Text("Noch keine Produktion. Creator OS kann die beste Chance oben direkt bis zum Master führen.")': 'Text("Noch kein Video in Produktion. Starte oben mit einer Videoidee oder öffne die Trends.")',
    'AbschnittTitel(titel: "Learning Loop", untertitel: "Blackstock nutzt echte Performance-Signale statt erfundene Erfolgswerte")': 'AbschnittTitel(titel: "Performance", untertitel: "Was bei deinen veröffentlichten Videos wirklich funktioniert")',
    'Text("Nach veröffentlichten Videos erscheinen hier belastbare Signale zu Format, Dauer, Packaging und Retention.")': 'Text("Nach deinen Uploads zeigt Blackstock hier Signale zu Format, Videolänge, Titel/Thumbnail und Zuschauerbindung.")',
    'return recommendation.mode == .singleSource ? "Clip mit Datei" : "Remix mit Datei"': 'return recommendation.mode == .singleSource ? "Clip aus Datei" : "Remix aus Datei"',
}
for old, new in replacements.items():
    replace(dashboard, old, new)

# Trends speaks like a video browser + clipper, not like an internal system console.
trend_replacements = {
    'untertitel: "Englische YouTube-Quellvideos ab 4 Minuten. Erst ansehen, dann entscheidet Blackstock anhand von Trend + Channel-Performance über Clip/Remix und die optimale Ausgabelänge.",': 'untertitel: "Finde aktuelle YouTube-Videos, spiele sie direkt ab und erstelle daraus mit Blackstock den passenden Clip, Remix, Short oder ein neues Video.",',
    'Text("BLACKSTOCK EMPFIEHLT")': 'Text("EMPFOHLEN")',
    'Text("Creator OS nutzt das YouTube-Video als Trend-Referenz. Ohne eigene/lizenzierte Datei baut Blackstock ein originales Video; Clip/Remix wird nur mit einer nutzbaren Schnittquelle ausgeführt.")': 'Text("Das YouTube-Video dient als Referenz. Für Clip oder Remix wählst du eine eigene oder lizenzierte Videodatei. Ohne Schnittquelle erstellt Blackstock ein neues Video zum Thema.")',
    'Label("Creator OS produzieren", systemImage: "bolt.fill")': 'Label("Video erstellen", systemImage: "wand.and.stars")',
    'store.meldung = "Creator OS konnte die Produktion nicht anlegen."': 'store.meldung = "Das Video konnte nicht erstellt werden."',
}
for old, new in trend_replacements.items():
    replace(trends, old, new)

# User-visible production status describes actions/results instead of architecture/versioning.
store_replacements = {
    '"Creator OS baut ein originales \\(mission.formatLabel) · \\(mission.durationLabel)"': '"Neues \\(mission.formatLabel) wird erstellt · \\(mission.durationLabel)"',
    '"Creator OS hat die Produktion am nächsten reparierbaren Schritt angehalten."': '"Die Produktion wurde beim nächsten lösbaren Schritt angehalten."',
    '"Blackstock 1000 hat den Master erstellt. Review bleibt vor dem Publishing aktiv."': '"Video fertig erstellt. Vor dem Veröffentlichen bleibt die Freigabe aktiv."',
    '"Creator OS Autopilot: \\(completed) von \\(missions.count) geplanten Produktionen bis zum Master geführt."': '"Automatisch erstellt: \\(completed) von \\(missions.count) Videos sind bis zur Freigabe vorbereitet."',
}
for old, new in store_replacements.items():
    replace(store, old, new)

# Older creation screen: keep persisted automation values stable, simplify only the displayed text.
replace(factory, 'titel: "Autopilot",', 'titel: "Automatisch erstellen",')
replace(factory, 'Text("Smart Autopilot").tag("Smart Autopilot")', 'Text("Automatisch · empfohlen").tag("Smart Autopilot")')
replace(factory, 'store.meldung = "Autopilot-Regel gespeichert."', 'store.meldung = "Automatik-Regel gespeichert."')

# Main surfaces must never expose release-number or architecture branding.
for path in (sidebar, dashboard, trends):
    text = path.read_text()
    for forbidden in ("BLACKSTOCK 1000", "Blackstock 1000", '"Creator OS"'):
        if forbidden in text:
            raise SystemExit(f"Forbidden user-facing label remains in {path}: {forbidden}")

print("BLACKSTOCK_UI_LANGUAGE_HOTFIX_OK")
