# Blackstock Market Readiness

Blackstock darf erst als marktreif gelten, wenn **interne Release-Gates** und **reale externe Evidenz** zusammenpassen. Kein CI-Fixture, kein lokaler Entwicklungsbuild und kein manuell gesetztes Boolean ersetzt diesen Nachweis.

## Finale Prüfung

Nach Abschluss des echten Apple-Produktionsreleases und eines echten In-App-Updates:

```bash
python3 Build/verify_market_readiness.py \
  --production-release-evidence "./release-evidence.json" \
  --in-app-update-evidence \
  "$HOME/Library/Application Support/Blackstock/Update/update-evidence.json" \
  --output "./market-readiness.json"
```

Nur ein erfolgreicher Lauf schreibt:

`BLACKSTOCK_MARKET_READINESS_PASS`

## Was geprüft wird

Der Verifier liest zuerst `docs/RELEASE_GATES.md`. Alle Gates außer den vier realweltabhängigen Gates müssen bereits `PASS` sein:

- Signing
- Notarization
- Gatekeeper
- Updater

Danach werden die beiden realen Evidenzdateien mit ihren fail-closed Validatoren geprüft:

- `Build/validate_production_release_evidence.py`
- `Build/validate_in_app_update_evidence.py`

Produktions-Manifest- und Paket-URLs unterliegen in Core-Verifier, In-App-Updater, Release-Verifier und Offline-Validatoren derselben Produktions-HTTPS-Regel. Der In-App-Updater prüft zusätzlich die nach Redirects tatsächlich erreichte finale URL.

Für die finale Prüfung werden beide Evidence-Dateien jeweils genau einmal als Bytes eingelesen. Die Einzelvalidatoren arbeiten auf temporären byteidentischen Snapshots. Nach Abschluss wird zusätzlich geprüft, dass sich keine Quelldatei während der Verifikation verändert hat. Der finale Report enthält den SHA-256 jeder tatsächlich geprüften Evidence-Datei.

## Cross-Binding

Beide Nachweise müssen zu demselben Release gehören. Der Verifier verlangt deshalb:

- identische Ausgangsversion und identischen Ausgangs-Build des Update-Pfads,
- gemessenen Source-Commit und SHA-256 der tatsächlich gestarteten Quell-App,
- identische Blackstock-Zielversion und identischen Ziel-Build,
- identische Produktions-Manifest-URL und Paket-URL,
- identischen SHA-256 des Release-Pakets,
- identischen Ziel-Source-Commit zwischen signiertem Produktionsrelease, installierter App und In-App-Updater-Evidenz,
- identischen SHA-256 des tatsächlich installierten Blackstock-Executables zwischen Published-Release-Verifikation und nach dem In-App-Update gestarteter App,
- identische Apple-Team-ID zwischen Produktionsrelease, erwarteter Updater-Team-ID und tatsächlich gestarteter Developer-ID-App,
- installierte Ziel-App unter `/Applications/Blackstock.app`,
- passenden Installer-Receipt `de.blackstock.app` für die Zielversion.

## Apple-Release-Evidenz

`BlackstockReleaseVerifier` erzeugt den Produktionsnachweis für:

- signiertes HTTPS-Manifest,
- echten Paketdownload,
- Paket-SHA-256,
- Developer ID Installer,
- Developer ID Application,
- Apple-Team-ID,
- Notarisierungsstatus `Accepted`,
- Stapling,
- Gatekeeper für Installer und installierte App,
- Universal-2-App mit arm64 und x86_64.

Blackstock benötigt für seinen YouTube-Clip-Workflow **keine Kamera- oder Mikrofon-Entitlements**. Diese sind daher weder Teil des Produktionspakets noch Teil des Release-Nachweises.

## In-App-Updater-Evidenz

Blackstock selbst protokolliert den tatsächlichen App-Pfad:

1. ältere installierte Produktionsversion einschließlich Source-Commit, Executable-SHA-256, kanonischem App-Pfad, Developer-ID-Team-ID und Installer-Receipt,
2. akzeptiertes signiertes Manifest,
3. verifiziertes Paket,
4. verifiziertes Installer-Team,
5. Übergabe an den macOS-Installer,
6. anschließend gestartete exakte Zielversion, Ziel-Build und der im Manifest signierte Source-Commit,
7. SHA-256 des tatsächlich gestarteten Executables,
8. exakter Bundle-Pfad `/Applications/Blackstock.app`,
9. erfolgreiche `codesign --verify --deep --strict`-Prüfung plus tatsächliche `Developer ID Application`-Team-ID,
10. passender macOS-Installer-Receipt `de.blackstock.app` für die Zielversion.

## CI-Regel

Die Canonical-CI testet ausschließlich den **Vertrag des Verifiers** mit synthetischen Fixtures. Diese Fixtures sind niemals Produktionsnachweis und dürfen die vier externen Gates nicht auf PASS setzen.

Der aktive Blackstock-Produktpfad ist YouTube-first: Entdecken → Quelle → Analyse → Clip → Render → Review → Upload → Analytics. Kamera-, Mikrofon-, Bildschirm- und Systemaudio-Aufnahme sind kein Release-Gate und werden vom ausgelieferten App-Bundle nicht angefordert.

## Statusregel

Solange kein echtes signiertes/notarisiertes Produktionsrelease und kein dazu passender realer In-App-Update-Nachweis vorliegen, bleibt:

**STATUS: NOCH NICHT MARKTREIF**

Ein zukünftiger Wechsel auf marktreif darf erst nach einem realen erfolgreichen `BLACKSTOCK_MARKET_READINESS_PASS` erfolgen.
