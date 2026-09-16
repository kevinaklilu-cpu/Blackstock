# Blackstock

Blackstock ist eine native macOS App für YouTube-Recherche, Produktion, Publishing und Analytics. Der Produktname ist ausschließlich **Blackstock**; die aktuelle technische Version ist `1.0.0`.

## Installation

**Blackstock.dmg öffnen → Blackstock.app nach Programme ziehen → starten.**

Für Endnutzer ist kein lokaler Build und kein Terminal-Schritt erforderlich.

## Kernworkflow

`Kanal → Entdecken → Recherche → Ideen → Studio → Veröffentlichen → Analytics → Lernen`

Blackstock verbindet kanalbezogene Trend-Erkennung, eingebettete Video-Preview, Source-/Rights-Prüfung, Clip- und Remix-Planung, Captions, optionale Voice-/Musik-/Branding-Layer, Thumbnail-/Packaging-Arbeit, hochwertige lokale Renderings, YouTube-Publishing und Analytics in einem durchgängigen Workflow.

## Produktprinzipien

- **Ein Produkt statt Tool-Hopping:** Recherche, Produktion, Packaging, Publishing und Analytics arbeiten auf demselben Projektzustand.
- **Kanalbezogene Intelligence:** Chancen und Empfehlungen orientieren sich am verbundenen Kanal und dessen Content-DNA.
- **Rights-aware by default:** Referenzvideos und tatsächlich nutzbare Source Assets werden getrennt behandelt; unsichere Rechte blockieren automatisches Publishing.
- **Quality first:** Source-aware Rendering, Originalton als Standard, editierbare Captions und optionale kreative Layer.
- **Harter Release-Pfad:** Regressionstests, vollständiger Swift-Typecheck, Market-Readiness-Audit, Smoke-Test, Universal-Binary-Prüfung, Developer-ID-Signierung, Apple-Notarisierung und Gatekeeper-Validierung.
- **Sichere Credentials:** OAuth-Konfiguration wird im Release-Prozess aus geschützten Repository-Secrets eingebunden; Tokens gehören in den macOS-Keychain.

## macOS

- Minimum: macOS 13
- Architekturen: Apple Silicon (`arm64`) und Intel (`x86_64`)
- Bundle ID: `de.blackstock.native`
- Version: `1.0.0`
- Build: `100`

## Release-Artefakte

Der kanonische CI-Build erzeugt `Blackstock.dmg` und `Blackstock.zip` samt SHA-256-Prüfsummen. Der öffentliche Distributions-Workflow gibt dieselben Namen erst frei, nachdem Produktions-OAuth, Developer-ID-Signatur, Apple-Notarisierung und Gatekeeper erfolgreich geprüft wurden.

Interne historische Datei- oder Symbolnamen wie `Release1000`, `V1000` oder `CreatorOS1000View` sind ausschließlich Migrations-/Build-Interna und keine Produktnamen.
