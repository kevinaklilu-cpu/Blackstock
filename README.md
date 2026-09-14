# Blackstock Native Mac 11.1.0

## Installation für Endnutzer

Blackstock wird als **fertige macOS-App** verteilt. Auf dem Mac des Nutzers wird nichts kompiliert.

**Blackstock DMG öffnen → Blackstock.app nach Programme ziehen → starten.**

Es gibt keine Endnutzer-`.command`-Installation mehr. Details: `INSTALLATION_EINFACH.md`.

## Release-Build

Der reproduzierbare macOS-26-Build liegt in `.github/workflows/macos-build.yml`. Er erzeugt `Blackstock.app`, eine Universal-App-ZIP und `Blackstock-11.1.0-universal.dmg`. Developer-ID-Signierung/Notarisierung sind über Repository-Secrets optional aktivierbar und für einen reibungslosen öffentlichen Gatekeeper-Release vorgesehen.

---

# Blackstock Native Mac v11.1.0

Blackstock ist ein natives macOS **YouTube Creator & Media Operations Center**. Version 11 verschiebt den Kern von einer AI-first-Generator-UX zu **Existing Media First**: kanalrelevante Trends erkennen, rechtlich nutzbare Remote-Quellen auflösen, daraus eine nachvollziehbare Remix-Timeline bauen, nativ rendern, Metadaten aus dem tatsächlich geschnittenen Inhalt erzeugen und anschließend review-basiert oder automatisiert auf den richtigen YouTube-Kanal veröffentlichen.

## Kernworkflow

`Kanal → Trends → Source Discovery → Rights Check → Clip Analysis → Remix Timeline → Render → Metadata → Bereit-Check → Review/Upload → Analytics`

YouTube-Trendvideos sind ausschließlich `TrendReference`. Sie werden nicht gerippt oder als Schnittquelle behandelt. Für einen Render benötigt Blackstock ein `SourceAsset` mit maschinenlesbarem Rechtezustand.

## Hauptbereiche

- **Übersicht** – echte Tages-KPIs und ein zentraler Apple-Charts-Zeitverlauf.
- **Trends** – kanalbezogene Chancen mit stabiler Topic-Taxonomie; Sport bleibt immer verfügbar.
- **Produktionen** – eine operative State Machine für Source Discovery, Analyse, Planung, Cache, Render, Review und Upload.
- **Inhalte** – veröffentlichte/geplante Inhalte mit realen Performance-Kennzahlen.
- **Analytics** – Overview, Content und Revenue ohne erfundene Nullwerte.
- **Kanäle** – Google Accounts, mehrere YouTube-Kanäle, Content DNA und Berechtigungsstatus.
- **Einstellungen** – Produktion, Veröffentlichung, Quellen/Cache und optionale AI-Fallbacks.

## Architekturprinzipien

Blackstock v11 trennt `GoogleAccount` von `YouTubeChannelConnection`, `TrendReference` von `SourceAsset` und periodische Analytics von Lifetime-Werten. OAuth-Tokens und Stream-Keys liegen im Keychain. Remote-Medien werden nur in Blackstocks verwaltetem Working Directory gecacht; große Dateien werden nicht vollständig in den RAM geladen.

Automatisches Publishing wird blockiert, wenn Nutzungsrechte unbekannt/eingeschränkt/abgelaufen sind, erforderliche Attribution fehlt oder eine lizenzierte Quelle keine ausdrücklich erlaubte Bearbeitung, Veröffentlichung und kommerzielle Nutzung ausweist.

## Build

Voraussetzungen für einen vollständigen nativen Release-Build:

- macOS 13 oder neuer
- Xcode Command Line Tools / aktuelles Swift Toolchain
- Developer ID Application Zertifikat für signierte Distribution
- optional Apple-Notarisierungsprofil für DMG
- FFmpeg **nur**, wenn echtes RTMP-Live-Playout verwendet werden soll; FFmpeg wird nicht gebündelt

Prüfung:

```bash
./Build/verify-release.zsh
```

App-Bundle:

```bash
./Build/build-app.zsh
```

Signiertes/notarisiertes DMG siehe `INSTALLATION_EINFACH.md`.

## Tests

`Build/Core-Tests.sh` ist die gemeinsame portable Regressionstest-Matrix für lokale Prüfung und CI. Sie umfasst Altregressionen plus v11-Tests für Migration, Multi-Channel, Analytics, Rights, Remix, Publishing-Idempotenz und Recovery. `Build/Release-Audit.sh` prüft Versionskonsistenz, Ressourcen, gefährliche Swift-Konstrukte und Syntax.

## Migration

Beim ersten Laden eines älteren Zustands normalisiert Blackstock v10-Daten in den v11-State. Vor der Migration wird ein Pre-v11-Snapshot angelegt. Neue Felder verwenden stabile Defaults; alte Channel-/Production-IDs bleiben soweit möglich erhalten.

## Release

**Version:** 11.1.0  
**Build:** 1110  
**Bundle ID:** `de.blackstock.native`

Siehe `RELEASE_NOTES_v11.md`, `ARCHITEKTUR.md` und `PRODUCTION_CHECKLIST.md`.
