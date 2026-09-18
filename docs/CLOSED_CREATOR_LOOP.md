# Closed Creator Loop — Feasibility and Gap Register

Diese Datei konkretisiert den FINAL CANONICAL MASTER PROMPT. Sie ersetzt keine Master-Anforderung.

**STATUS: NOCH NICHT MARKTREIF**

## Ziel

Blackstock bildet einen geschlossenen, nachvollziehbaren Creator-Loop ab:

Opportunity → Research → Strategy → Production → Preview → Storyboard → Editing → Packaging → Review → Publishing → Analytics → Learning → nächste Strategy-Version.

Das Produkt darf niemals Views, Abonnenten oder Viralität garantieren. Es optimiert beeinflussbare Faktoren und misst reale Ergebnisse.

## Technisch realisierbar

### Discovery / Research
Status: IN PROGRESS

- YouTube-Suche und Rohmetriken über offizielle APIs.
- Keine erfundenen Opportunity-/Virality-Scores.
- Provider-native Sortierungen.
- Provenance, Zeitsemantik und Evidence bleiben Pflicht.

### Strategy
Status: IN PROGRESS

- HistoricalChannelProfile getrennt von ChannelStrategy.
- Strategie versioniert.
- Content-Sprache getrennt von Produktsprache.
- Nächste Strategie darf nur aus dokumentierten Beobachtungen und Nutzerentscheidungen entstehen.

### Production / Editing
Status: IN PROGRESS

Technisch lokal auf macOS realisierbar:
- AVFoundation Composition und Export.
- VideoToolbox für Hardware-Encoding.
- Vision/Core ML für Reframe- und Motivtracking.
- Speech/Whisper-kompatible lokale Modelle für Transkription.
- Captions und Text-Overlays.
- Audio-Leveling, Ducking und Loudness-QA.
- EditGraph, Undo/Redo und Activity Ledger.
- 1080p/1440p/4K Render-Pipeline.

Fehlend bis PASS:
- vollständiger Storyboard-Editor,
- Multitrack-Timeline,
- Caption-Editor,
- Auto-Reframe + manueller Override,
- Audio-QA,
- visuelle Overlays/B-Roll,
- produktionsreifer Export und Render-QA.

### Link-first Remote Ingest
Status: PARTIAL / provider-dependent

UX-Ziel:
Opportunity auswählen → Als Clip verwenden → Rechte bestätigen → Quelle automatisch vorbereiten → Studio.

Technische Wahrheit:
- Eine beliebige fremde YouTube-Seiten-URL kann nicht über einen offiziellen kostenlosen YouTube-Download-Endpunkt als Mediendatei bezogen werden.
- Deshalb ist Remote-Ingest ein austauschbarer Provider-Adapter.
- Lokale/originale/Cloud-/direkte autorisierte Medien bleiben vollständig lokal verarbeitbar.
- Kostenpflichtige Provider sind standardmäßig deaktiviert.
- Kostenlose Provider dürfen verwendet werden, wenn capability-gated und aktuell verifiziert.
- Kein stiller Pay-as-you-go-Fallback.

### Packaging
Status: FAIL

Technisch realisierbar:
- mehrere Titel-/Thumbnail-Varianten,
- Thumbnail-Generator und Editor,
- Metadaten, Chapters, Tags, Localizations,
- Captions-Dateien,
- Review-Vergleich.

YouTube unterstützt offizielles Setzen eigener Thumbnails sowie Metadata-Updates. Native YouTube-A/B-Tests sind aktuell eine YouTube-Studio-Funktion; Blackstock darf deren Ergebnis nicht faken.

### Publishing
Status: IN PROGRESS

- Wrong-Channel-Hard-Stop vorhanden.
- External Action Journal vorhanden.
- offizieller resumable YouTube Upload implementiert.
- idempotenter Upload-Key verhindert beabsichtigte Doppel-Uploads.
- Upload-Session kann nach Unterbrechung abgefragt und fortgesetzt werden.

Fehlend bis PASS:
- vollständige OAuth Scope-Eskalation für Upload,
- Thumbnail-Upload,
- Caption-Upload,
- Metadata-/Localization-Update,
- Conflict-Reconciliation-E2E,
- echtes Testkonto-E2E.

### Analytics / Growth Learning
Status: IN PROGRESS

Technisch realisierbar und im Core begonnen:
- Views,
- Engaged Views,
- Likes,
- Kommentare,
- Shares,
- Watchtime,
- Average View Duration,
- Average View Percentage,
- Subscribers Gained/Lost.

Beobachtungsfenster:
- 24h,
- 72h,
- 7d,
- 28d.

Blackstock speichert Fakten, nicht Garantien. Die nächste Empfehlung muss auf konkreten Observation-IDs und Evidence beruhen.

## Qualität, die Wachstum unterstützen kann

Blackstock optimiert fünf getrennte Qualitätsachsen:

1. **Demand Fit**
   - Thema passt zu realer Nachfrage und Kanalstrategie.

2. **Packaging Fit**
   - Titel/Thumbnail kommunizieren das Versprechen klar und wahrheitsgemäß.

3. **Retention Fit**
   - Hook, Struktur, Tempo, visuelle Abwechslung, Captions und Audio reduzieren vermeidbare Drop-offs.

4. **Audience Fit**
   - Sprache, Format und Content Promise passen zur Zielgruppe.

5. **Learning Fit**
   - Nach Veröffentlichung werden reale Resultate dem konkreten Projekt und Experiment zugeordnet.

Keine Achse darf durch einen synthetischen Gesamtscore verborgen werden. Details und Daten bleiben sichtbar.

## Zero-Cost-Prinzip

Standard:
- lokale Verarbeitung zuerst,
- offizielle kostenlose Kontingente danach,
- kostenlose externe Provider optional,
- kostenpflichtige Provider deaktiviert.

Eine Capability darf nicht automatisch Geld ausgeben.

## Nicht technisch garantierbar

- eine bestimmte Zahl von Views,
- eine bestimmte Zahl von neuen Abonnenten,
- virale Distribution,
- ein bestimmter Ranking-Platz im YouTube-Recommendation-System,
- ein Native-YouTube-A/B-Test über eine API, solange YouTube dafür keine öffentliche API anbietet,
- kostenloser offizieller Datei-Ingest beliebiger fremder YouTube-Videos ohne einen zulässigen Provider.

Diese Grenzen verhindern den geschlossenen Creator-Loop nicht. Sie bestimmen lediglich, welche Schritte Blackstock selbst kontrolliert und welche Ergebnisse nur beobachtet werden können.
