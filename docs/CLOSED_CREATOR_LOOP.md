# Closed Creator Loop — Feasibility and Gap Register

Diese Datei konkretisiert den FINAL CANONICAL MASTER PROMPT. Sie ersetzt keine Master-Anforderung.

**INTERNER PRODUKTSTATUS: IMPLEMENTIERT / CANONICAL CI PASS**

**MARKTSTATUS: NOCH NICHT MARKTREIF**

## Ziel

Blackstock bildet einen geschlossenen, nachvollziehbaren Creator-Loop ab:

Opportunity → Research → Strategy → Production → Preview → Storyboard → Editing → Packaging → Review → Publishing → Analytics → Learning → nächste Strategy-Version.

Das Produkt garantiert weder Views noch Abonnenten oder Viralität. Es optimiert kontrollierbare Faktoren und speichert reale Ergebnisse mit Provenance.

## Implementierter Creator-Loop

### Discovery / Research
Status: PASS

- Reale YouTube-Kandidaten über offizielle APIs.
- Provider-native Sortierung und Rohmetriken.
- Keine erfundenen Opportunity-/Virality-Scores.
- Projektgebundene Research-Evidence, Zeitsemantik und Provenance.
- Opportunity wird mit Provider-ID, Quelle und Zielkanal in ein Projekt überführt.

### Strategy
Status: PASS

- HistoricalChannelProfile getrennt von ChannelStrategy.
- Versionierte Strategie.
- Content-Sprache getrennt von Produktsprache.
- Nächste Strategie wird nur aus dokumentierten Beobachtungen und Nutzerentscheidungen abgeleitet.

### Production / Preview / Storyboard
Status: PASS

- Autorisierte lokale Produktionsmedien und projektgebundene Quelle.
- Einmalige Workspace-Erklärung zur Nutzungsverantwortung statt Lizenzdatei pro Video.
- Lokale Vorschau.
- Vollständiger Storyboard-Editor mit Beats, Titel, Zweck, visueller Richtung, Reihenfolge, Hinzufügen und Entfernen.
- Kamera-, Mikrofon-, Bildschirm- und Systemaudio-Pipelines sind implementiert; reale Hardware-Evidenz bleibt ein externer Freigabenachweis.

### Editing
Status: PASS

- Persistenter nicht-destruktiver EditGraph.
- Undo/Redo und Activity Ledger.
- Trim und Remove-Range.
- Manuelles und lokales Vision-basiertes Reframe.
- Lokale Clip-Kandidaten aus zeitcodiertem Transkript ohne Virality-/Winner-Score.
- Text-Overlays.
- Zusatz-Audio mit Lautstärke-Mix.
- Persistente visuelle B-Roll-/Supplemental-Video-Inserts mit Zielstart, Quellstart und Dauer.
- B-Roll wird lokal über einen softwarebasierten Frame-Compositor verarbeitet: AVAssetReader/Writer + Core Image Software Rendering; der bereits gemischte Hauptton wird anschließend wieder zugemultiplext.
- Dadurch ist B-Roll nicht vom instabilen Built-in-AVFoundation-Video-Compositor auf headless/virtuellen Macs abhängig.
- Reale 1080p-/4K-Ausgabe und technische Render-QA.

### Captions
Status: PASS

- On-Device-Transkription ohne stillen Cloud-Fallback.
- WebVTT-Ausgabe und Burn-in-Captions.
- Persistenter manueller Segment-Editor für Text, Startzeit und Dauer.
- Überlappende, leere oder außerhalb der editierten Timeline liegende Segmente werden abgelehnt.
- Manuelle Korrekturen werden markiert, WebVTT wird neu geschrieben und stale Render-/Clip-Evidenz invalidiert.
- Technische Caption-QA vor Review und Publishing.

### Link-first Remote Ingest
Status: IMPLEMENTED WITH PROVIDER BOUNDARY

UX-Pfad:

Opportunity auswählen → Als Clip verwenden → einmalige Nutzungsverantwortung bestätigen → Quelle automatisch binden → Studio.

Technische Grenze:

- Eine beliebige fremde YouTube-Seiten-URL liefert über die offizielle YouTube API keine frei editierbare Videodatei.
- Blackstock verwendet deshalb keinen versteckten Downloader.
- Lokale/originale/Cloud-/direkte autorisierte Medien sind vollständig lokal verarbeitbar.
- Zusätzliche Ingest-Provider bleiben capability-gated.
- Kostenpflichtige Provider sind standardmäßig deaktiviert.
- Kein stiller Pay-as-you-go-Fallback.

### Packaging
Status: PASS

- Persistentes Veröffentlichungspaket.
- Mehrere Titel-/Thumbnail-Varianten ohne erfundenen Gewinner.
- Thumbnail-Generator und technische Thumbnail-QA.
- Metadaten, Captions und Review-Evidence.
- YouTube-Grenzen werden vor Publish erneut validiert.

### Publishing
Status: PASS

- Wrong-Channel-Hard-Stop.
- External Action Journal.
- Offizieller resumable YouTube Upload.
- Idempotenter Upload-Key und Resume.
- Journaled Thumbnail- und Caption-Aktionen.
- Capability-basierte OAuth-Scopes.
- Erneute Zielkanalprüfung direkt vor Remote-Aktionen.
- Finaler ausdrücklicher Nutzer-Confirm vor High-Impact-Publishing.

Public/Unlisted bleibt zusätzlich hinter dem separat auditierten Build-Flag; ohne Freigabe ist nur der vorgesehene private Publish-Pfad aktiv.

### Analytics / Growth Learning
Status: PASS

Implementiert sind reale Provider-Fakten einschließlich:

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

Blackstock speichert Fakten, nicht Garantien. Lernempfehlungen bleiben auf konkrete Observation-/Evidence-IDs zurückführbar.

## Installations- und Clean-Machine-Status

Status: PASS

Die Canonical CI:

- baut Universal-2-Binaries für arm64 und x86_64,
- erzeugt ein echtes installierbares macOS-.pkg,
- installiert und startet exakt dieses Paket auf Apple Silicon,
- führt den installierten Creator-Loop-E2E aus,
- übergibt exakt dasselbe Paket per SHA-256 an einen nativen Intel-Runner,
- installiert, startet und prüft dort denselben Creator-Loop erneut.

Der installierte E2E umfasst Opportunity-Bindung, Nutzungsverantwortung, lokale Clip-Kandidaten, realen Video-Render inklusive B-Roll, Audio-QA, Review, gemockte externe Publishing-Grenzen, Upload-Journaling, Analytics, Growth-Learning und Persistenz-Roundtrip.

## Verbleibende Freigabenachweise

Es fehlen keine bekannten internen Produkt-Gates mehr. Für eine öffentliche Marktfreigabe fehlen reale externe Evidenzen:

- Capture-Hardware-/Permission-Smoke auf einem unterstützten physischen Mac,
- Developer ID Application / Installer Signing,
- Apple Notarization,
- Gatekeeper-Nachweis,
- echte Produktions-Update-Endpunkte plus vollständiger älter→neuer In-App-Versionswechsel.

Diese Punkte werden bewusst nicht durch CI-Fixtures oder Behauptungen ersetzt.

## Zero-Cost-Prinzip

Standard:

- lokale Verarbeitung zuerst,
- offizielle kostenlose Kontingente danach,
- kostenlose externe Provider optional,
- kostenpflichtige Provider deaktiviert.

Eine Capability darf nicht automatisch Geld ausgeben.

## Nicht technisch garantierbar

- eine bestimmte Zahl von Views,
- eine bestimmte Zahl neuer Abonnenten,
- virale Distribution,
- ein bestimmter Ranking-Platz im YouTube-Recommendation-System,
- ein Native-YouTube-A/B-Test über eine öffentliche API, solange YouTube dafür keine öffentliche API anbietet,
- kostenloser offizieller Datei-Ingest beliebiger fremder YouTube-Videos ohne zulässigen Provider.

**STATUS: NOCH NICHT MARKTREIF — ausschließlich wegen der dokumentierten realen externen Freigabenachweise.**
