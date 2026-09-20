# Blackstock Market Readiness

Blackstock darf erst als marktreif gelten, wenn **interne Release-Gates** und **reale externe Evidenz** zusammenpassen. Kein CI-Fixture, kein lokaler Entwicklungsbuild und kein manuell gesetztes Boolean ersetzt diesen Nachweis.

## Finale Prüfung

Nach Abschluss des realen Hardware-Smokes, des echten Apple-Produktionsreleases und des echten In-App-Updates:

```bash
python3 Build/verify_market_readiness.py \
  --capture-evidence \
  "$HOME/Library/Application Support/Blackstock/Diagnostics/capture-hardware-smoke.json" \
  --production-release-evidence \
  "./release-evidence.json" \
  --in-app-update-evidence \
  "$HOME/Library/Application Support/Blackstock/Update/update-evidence.json" \
  --output "./market-readiness.json"
```

Nur ein erfolgreicher Lauf schreibt:

`BLACKSTOCK_MARKET_READINESS_PASS`

## Was geprüft wird

Der Verifier liest zuerst `docs/RELEASE_GATES.md`. Alle Gates außer den fünf realweltabhängigen Gates müssen bereits `PASS` sein:

- Capture
- Signing
- Notarization
- Gatekeeper
- Updater

Danach werden die drei realen Evidenzdateien jeweils mit ihren eigenen fail-closed Validatoren geprüft:

- `Build/validate_capture_hardware_smoke.py`
- `Build/validate_production_release_evidence.py`
- `Build/validate_in_app_update_evidence.py`

Alle Evidence-Dateien werden als striktes JSON behandelt. Nicht standardkonforme numerische Werte wie `NaN`, `Infinity` oder `-Infinity` werden abgelehnt; numerische Capture-Dauern und Updater-Zeitstempel müssen zusätzlich endlich sein. Produktions-Manifest- und Paket-URLs unterliegen auch in den Offline-Validatoren derselben Produktions-HTTPS-Regel wie der eigentliche Release-Pfad.

Anschließend bindet der Readiness-Verifier die Nachweise **untereinander**.

## Cross-Binding

Alle Nachweise müssen zu demselben Release gehören.

Der Verifier verlangt deshalb:

- identische Ausgangsversion des Update-Pfads zwischen Published-Release-Verifikation und realem In-App-Update,
- identischen Ausgangs-Build dieses Update-Pfads,
- identische Blackstock-Zielversion,
- identischen Ziel-Build,
- identische Produktions-Manifest-URL,
- identische Paket-URL,
- identischen SHA-256 des Release-Pakets,
- identischen Git-Source-Commit-SHA zwischen Capture-Hardware-Evidenz, signiertem Produktionsrelease, installierter App und In-App-Updater-Evidenz,
- identischen SHA-256 des tatsächlich installierten Blackstock-Executables zwischen Capture-Smoke, veröffentlichtem Release und nach dem In-App-Update gestarteter App,
- identische Apple-Team-ID zwischen der tatsächlich signierten Capture-App, dem Produktionsrelease, der vom Updater erwarteten Team-ID und der nach dem Update tatsächlich gestarteten Developer-ID-App,
- identischen Installer-Receipt `de.blackstock.app` samt Zielversion zwischen Capture-Smoke und Post-Update-Start,
- identischen installierten App-Pfad `/Applications/Blackstock.app` zwischen Published-Release-Verifikation und echtem Updater-E2E.

Damit kann zum Beispiel kein erfolgreicher Hardware-Smoke von Build 100 mit einem signierten Build 101 oder einem Update-Paket eines anderen Hashes kombiniert werden.

## Capture-Evidenz

Die reale Capture-Evidenz wird von Blackstock selbst erzeugt. Sie enthält für Kamera, Mikrofon, Bildschirm und Systemaudio unter anderem:

- Berechtigungsstatus,
- reale Aufnahmedauer,
- technisch erkannte Video-/Audiospuren,
- projektgebundene persistierte Datei,
- kanonischer Projektpfad unter `~/Library/Application Support/Blackstock/Projects/<projectID>/Media` bzw. `Captures`, nach Symlink-Auflösung,
- UUID-basierter importierter Asset-Dateiname und Übereinstimmung des Pfad-Projekts mit `projectID`,
- SHA-256 dieser Datei,
- gemeinsame Aufnahme-Launch-ID für alle vier kanonischen Capture-Pfade,
- Source-Commit-SHA des installierten Blackstock-Bundles,
- gültiger macOS-Installer-Receipt `de.blackstock.app` für exakt dieselbe App-Version,
- erfolgreiche `codesign --verify --deep --strict`-Prüfung der laufenden App plus tatsächliche `Developer ID Application`-Team-ID,
- SHA-256 des tatsächlich laufenden Blackstock-Executables,
- Restart-Launch-ID,
- Hard-Stop-Nachweis bei verweigerter Berechtigung,
- Temp-Cleanup-Nachweis.

Der Validator liest die persistierten Dateien erneut und prüft ihre SHA-256-Werte.

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
- Gatekeeper für Installer und installierte App.

## In-App-Updater-Evidenz

Blackstock selbst protokolliert den tatsächlichen App-Pfad:

1. ältere installierte Produktionsversion,
2. akzeptiertes signiertes Manifest,
3. verifiziertes Paket,
4. verifiziertes Installer-Team,
5. Übergabe an den macOS-Installer,
6. anschließend gestartete exakte Zielversion, Ziel-Build und der im Manifest signierte Source-Commit,
7. SHA-256 des tatsächlich gestarteten Executables,
8. exakter Bundle-Pfad `/Applications/Blackstock.app`,
9. erfolgreiche `codesign --verify --deep --strict`-Prüfung plus tatsächliche `Developer ID Application`-Team-ID,
10. passender macOS-Installer-Receipt `de.blackstock.app` für exakt die Zielversion.

## CI-Regel

Die Canonical-CI testet ausschließlich den **Vertrag des Verifiers** mit synthetischen Fixtures. Diese Fixtures sind niemals Produktionsnachweis und dürfen die fünf externen Gates nicht auf PASS setzen.

Die CI-Negativtests verwenden absichtlich widersprüchliche Paket-Hashes **und separat einen abweichenden beobachteten Source-Commit** zwischen Release- und Updater-Evidenz. Der Market-Readiness-Verifier muss beide Fälle ablehnen.

## Statusregel

Solange keine drei realen, gegenseitig konsistenten Evidenzdateien vorliegen, bleibt:

**STATUS: NOCH NICHT MARKTREIF**

Ein zukünftiger Wechsel auf marktreif darf erst nach einem realen erfolgreichen `BLACKSTOCK_MARKET_READINESS_PASS` erfolgen.
