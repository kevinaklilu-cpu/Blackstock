# Produktions-Release-Evidenz

Dieses Dokument definiert die noch externen Blackstock-Release-Nachweise. Es ersetzt keine Apple-Zertifikate, keine Notarisierung und keinen physischen Update-Test; es macht die Nachweise reproduzierbar und maschinenlesbar.

## 1. Voraussetzungen

Für einen echten Produktionslauf werden benötigt:

- gültige **Developer ID Application**-Identität,
- gültige **Developer ID Installer**-Identität desselben Apple-Teams,
- funktionsfähiges Apple-Notary-Keychain-Profil,
- privater Blackstock-Update-Signaturschlüssel außerhalb des Repositories,
- öffentlicher Blackstock-Update-Schlüssel,
- reale HTTPS-Manifest-URL,
- reale HTTPS-Paket-URL,
- erwartete Apple-Team-ID,
- eine ältere installierbare Blackstock-Version für den Update-Test.

Der CI-only E2E-Helper darf in einem Produktionspaket nicht enthalten sein.


## GitHub Actions: empfohlener Produktionspfad

Blackstock enthält zwei bewusst getrennte manuelle Workflows:

1. **Blackstock Production Release** (`.github/workflows/production-release.yml`)
   - baut den Release,
   - importiert Developer-ID-Zertifikate nur in einen temporären Runner-Keychain,
   - signiert App und Installer,
   - notarisiert mit App-Store-Connect-API-Key,
   - prüft `Accepted`, Stapling und Gatekeeper,
   - erzeugt das signierte Update-Manifest mit gebundenem `github.sha`,
   - bindet denselben Source-Commit in App-Bundle und Produktionsmetadaten,
   - lädt das Release-Bundle als GitHub-Artefakt hoch.

2. **Blackstock Verify Published Release** (`.github/workflows/verify-published-release.yml`)
   - läuft erst **nach** Veröffentlichung von Manifest und Paket unter den realen HTTPS-URLs,
   - verifiziert Manifest-Signatur, Paket-Hash, Installer-Team und Notarisierungsstatus,
   - persistiert den dabei signaturgeprüften Manifest-Snapshot über `--verified-manifest-output` und die geprüften Paketbytes über `--verified-package-output`,
   - installiert exakt diese geprüfte Paketdatei auf einem frischen macOS-Runner,
   - führt die Post-Install-Prüfung ausschließlich mit `--verified-manifest-input` und `--verified-package-input` über denselben Snapshot aus, ohne Manifest oder Paket erneut aus dem Netz zu laden,
   - vergleicht Pre-Install- und Post-Install-Evidence auf identische Release-Identität,
   - verifiziert Developer ID Application, Gatekeeper, **Universal-2 (arm64 + x86_64)** sowie exakte Manifest-Version, -Build, **Source-Commit und Executable-SHA-256** der installierten App,
   - startet die installierte Produktions-App,
   - erzeugt `release-evidence.json`.

Beide Workflows sind ausschließlich `workflow_dispatch`. Ein Push oder Pull Request darf niemals automatisch einen Produktionsrelease auslösen.

### Erforderliche GitHub Secrets

Für **Blackstock Production Release**:

- `BLACKSTOCK_APP_CERT_P12_BASE64`
- `BLACKSTOCK_APP_CERT_PASSWORD`
- `BLACKSTOCK_INSTALLER_CERT_P12_BASE64`
- `BLACKSTOCK_INSTALLER_CERT_PASSWORD`
- `BLACKSTOCK_CODESIGN_IDENTITY`
- `BLACKSTOCK_INSTALLER_IDENTITY`
- `BLACKSTOCK_APPLE_TEAM_ID`
- `BLACKSTOCK_NOTARY_KEY_P8_BASE64`
- `BLACKSTOCK_NOTARY_KEY_ID`
- `BLACKSTOCK_NOTARY_ISSUER`
- `BLACKSTOCK_UPDATE_PRIVATE_KEY_BASE64`
- `BLACKSTOCK_UPDATE_PUBLIC_KEY_BASE64`
- optional für den eingebetteten Google-Client: `BLACKSTOCK_GOOGLE_OAUTH_CLIENT_ID`

Für **Blackstock Verify Published Release** werden nur die zur unabhängigen Verifikation nötigen Secrets verwendet:

- `BLACKSTOCK_UPDATE_PUBLIC_KEY_BASE64`
- `BLACKSTOCK_APPLE_TEAM_ID`
- `BLACKSTOCK_NOTARY_KEY_P8_BASE64`
- `BLACKSTOCK_NOTARY_KEY_ID`
- `BLACKSTOCK_NOTARY_ISSUER`

Der private Blackstock-Update-Signaturschlüssel wird bewusst **nicht** im Verifikationsworkflow benötigt.

Vor dem Import der Apple-Zertifikate führt **Blackstock Production Release** außerdem `Build/verify_update_key_pair.swift` aus. Der Workflow stoppt, wenn der konfigurierte öffentliche Update-Schlüssel nicht exakt zum privaten Manifest-Signaturschlüssel gehört. Dadurch kann kein notarisiertes Produktionspaket mit einem Manifest-Schlüssel gebaut werden, den die ausgelieferte App später nicht verifizieren kann.

### Workflow-Reihenfolge

1. Production Release mit Zielversion, Build, zukünftiger Manifest-URL und Paket-URL starten.
2. Das erzeugte `Blackstock.pkg` und `update-manifest.json` exakt unter diesen HTTPS-URLs veröffentlichen.
3. Die Notary Submission ID aus `notary-response.json` übernehmen.
4. Verify Published Release mit der realen Manifest-URL, einer älteren Ausgangsversion/-Build und genau dieser Submission ID starten.
5. `release-evidence.json` archivieren.
6. Auf einem realen Mac den vollständigen In-App-Updater-Versionswechsel durchführen und die von Blackstock erzeugte `update-evidence.json` sichern.
7. Den realen Capture-Hardware-Smoke durchführen.
8. Erst dann `Build/verify_market_readiness.py` über alle drei realen Evidenzdateien laufen lassen.

Die Canonical-CI prüft mit `Build/audit_production_release_workflows.py`, dass diese Trennung, die Secret-Bindung und der Ausschluss des CI-only E2E-Helpers aus Produktionspaketen erhalten bleiben.

### Produktionskonfiguration vor dem Build

Die Produktions-URL-Policy gilt konsistent für Workflow-Eingaben, den Manifest-Generator und den Release-Verifier. Manifest- und Paket-URLs müssen HTTPS verwenden, dürfen keine eingebetteten Zugangsdaten oder Fragmente enthalten und dürfen nicht auf lokale/Test-Spezialhosts wie `localhost`, Loopback, `.local`, `.invalid`, `.example` oder `.test` zeigen. Dasselbe gilt nach HTTP-Redirects im Release-Verifier.

Wenn `BLACKSTOCK_PRODUCTION_RELEASE=1` gesetzt ist, bricht `Build/package.sh` bereits **vor** der Kompilierung ab, wenn die Produktionskonfiguration nicht fail-closed gültig ist. `Build/validate_production_package_config.py` verlangt:

- eine absolute HTTPS-Manifest-URL auf einem realen Host, ohne eingebettete Zugangsdaten oder Fragment,
- einen Base64-kodierten 32-Byte-Update-Public-Key,
- eine ASCII-alphanumerische Apple-Installer-Team-ID.

Zusätzlich muss der Produktionsmodus Developer-ID-App-/Installer-Identitäten und vollständige Notarisierungsdaten besitzen; der CI-only E2E-Helper ist verboten. Der Paketierer erzeugt die auszuliefernde App immer als Universal-2 aus separat gebauten arm64- und x86_64-Slices und bricht ab, wenn einer der beiden Slices fehlt.

Die Developer-ID-Application-Signatur verwendet Hardened Runtime plus `Build/Blackstock.entitlements`. Die vollständige Produktions-Evidenz verlangt deshalb zusätzlich:

- `cameraEntitlementVerified = true`
- `audioInputEntitlementVerified = true`

Damit wird verifiziert, dass die installierte Produktions-App die Resource-Access-Entitlements `com.apple.security.device.camera` und `com.apple.security.device.audio-input` tatsächlich in ihrer Codesign-Signatur trägt.

## 2. Produktionspaket erzeugen

Beispiel:

```bash
export BLACKSTOCK_VERSION="1.0.0"
export BLACKSTOCK_BUILD="100"
export BLACKSTOCK_SOURCE_COMMIT_SHA="$(git rev-parse HEAD)"
export BLACKSTOCK_CODESIGN_IDENTITY="Developer ID Application: …"
export BLACKSTOCK_INSTALLER_IDENTITY="Developer ID Installer: …"
export BLACKSTOCK_NOTARY_KEYCHAIN_PROFILE="blackstock-notary"
export BLACKSTOCK_UPDATE_MANIFEST_URL="https://updates.example.com/update-manifest.json"
export BLACKSTOCK_UPDATE_PUBLIC_KEY_BASE64="…"
export BLACKSTOCK_UPDATE_INSTALLER_TEAM_ID="TEAMID"

Build/package.sh dist
```

`Build/package.sh` signiert die App, signiert das Installer-Paket und führt bei gesetztem Notary-Profil Notarisierung, Stapling und Gatekeeper-Assessment aus.

## 3. Manifest veröffentlichen

Erst das finale signierte/notarisierte Paket wird manifestiert:

```bash
export BLACKSTOCK_UPDATE_PRIVATE_KEY_BASE64="…"

swift Build/generate_update_manifest.swift \
  --package dist/Blackstock.pkg \
  --package-url "https://updates.example.com/Blackstock.pkg" \
  --version "1.0.0" \
  --build "100" \
  --source-commit-sha "$BLACKSTOCK_SOURCE_COMMIT_SHA" \
  --output dist/update-manifest.json
```

Danach werden **genau dieses** Manifest und **genau dieses** Paket unter den Produktions-HTTPS-URLs veröffentlicht.

## 4. Remote-Release verifizieren

Der Verifier verwendet dieselben Blackstock-Core-Regeln wie der Updater:

```bash
swift run -c release BlackstockReleaseVerifier \
  --manifest-url "https://updates.example.com/update-manifest.json" \
  --public-key-base64 "$BLACKSTOCK_UPDATE_PUBLIC_KEY_BASE64" \
  --installer-team-id "$BLACKSTOCK_UPDATE_INSTALLER_TEAM_ID" \
  --current-version "0.9.0" \
  --current-build "90" \
  --installed-app "/Applications/Blackstock.app" \
  --notary-submission-id "$BLACKSTOCK_NOTARY_SUBMISSION_ID" \
  --notary-keychain-profile "$BLACKSTOCK_NOTARY_KEYCHAIN_PROFILE" \
  --verified-manifest-output verified-update-manifest.json \
  --verified-package-output verified-Blackstock.pkg \
  --output preinstall-release-evidence.json
```

Ein erfolgreicher Lauf schreibt `BLACKSTOCK_RELEASE_VERIFY_PASS`.

Für den Installationspfad wird dieser erste Lauf als unveränderlicher Release-Snapshot behandelt. Nach der Installation wird derselbe Verifier erneut mit `--verified-manifest-input verified-update-manifest.json` und `--verified-package-input verified-Blackstock.pkg` ausgeführt. Dieser zweite Lauf greift für Manifest und Paket nicht mehr auf das Netzwerk zu. Der Workflow verlangt zusätzlich, dass die identitätsbildenden Felder der Pre-Install- und Post-Install-Evidence exakt übereinstimmen.

Er prüft:

- Manifest wird tatsächlich über HTTPS geladen.
- Manifest-Signatur ist mit dem eingebetteten öffentlichen Schlüssel gültig.
- Manifest beschreibt gegenüber der Ausgangsversion tatsächlich ein Update.
- Paket wird von der im Manifest angegebenen HTTPS-URL geladen.
- Paket-SHA-256 entspricht exakt dem signierten Manifest.
- Der signaturgeprüfte Manifest-Snapshot kann byteidentisch über `--verified-manifest-output` persistiert werden.
- Genau die bereits geprüfte Paketdatei kann über `--verified-package-output` für den anschließenden Installationsschritt persistiert werden; die persistierte Kopie wird erneut gegen denselben signierten Manifest-SHA-256 geprüft.
- `--verified-manifest-input` und `--verified-package-input` müssen gemeinsam angegeben werden. Damit kann die Post-Install-Prüfung denselben unveränderlichen Release-Snapshot erneut prüfen, statt Remote-Artefakte ein zweites Mal abzurufen.
- Der Source-Commit-SHA ist Teil des signierten Manifest-Payloads.
- Paket ist ein Developer-ID-Installer des erwarteten Apple-Teams.
- Stapled Notarization Ticket ist gültig.
- Gatekeeper akzeptiert das Installer-Paket.
- optional: installierte App besteht `codesign --deep --strict`.
- optional: installierte App weist Developer ID Application und erwartete Team-ID aus.
- optional: `BlackstockSourceCommitSHA` der installierten App entspricht exakt dem signierten Manifest-Commit.
- optional: die installierte App muss als Universal-2-Binary sowohl arm64 als auch x86_64 enthalten; ein fehlender Slice führt zum Hard-Stop.
- optional: der SHA-256 des vollständigen installierten Universal-Executables wird als `installedAppExecutableSHA256` in der Release-Evidenz gebunden.
- optional: Gatekeeper akzeptiert die installierte App.
- optional: `notarytool info` meldet für die konkrete Submission `Accepted`.

Die JSON-Datei wird mit `Build/validate_production_release_evidence.py` geprüft.

## 5. Signing / Notarization / Gatekeeper

Diese drei Gates dürfen erst von `BLOCKED_EXTERNAL` auf `PASS` wechseln, wenn die Produktions-Evidenz alle folgenden Felder positiv belegt:

- `developerIDInstallerVerified = true`
- `developerIDApplicationVerified = true`
- `notaryStatus = "Accepted"`
- `staplerValidated = true`
- `gatekeeperInstallerAccepted = true`
- `gatekeeperApplicationAccepted = true`

Die Evidenz muss zu derselben Version, demselben Build und derselben Apple-Team-ID gehören.

## 6. Echter Updater-E2E

Der Release-Verifier allein reicht **nicht** für `Updater = PASS`.

Zusätzlich muss auf einem sauberen Mac der tatsächliche Blackstock-App-Pfad geprüft werden:

1. ältere Produktionsversion unter `/Applications/Blackstock.app` installieren;
2. prüfen, dass deren Bundle-Version und Build exakt der dokumentierten Ausgangsversion entsprechen;
3. Blackstock muss vor dem Update den Source-Commit und SHA-256 des laufenden Quell-Executables erfassen, `codesign --verify --deep --strict` bestehen, dieselbe erwartete Apple-Team-ID tragen und einen passenden Installer-Receipt `de.blackstock.app` für die Ausgangsversion besitzen;
4. diese Version muss mit der realen Produktions-Manifest-URL, dem öffentlichen Update-Schlüssel und der erwarteten Installer-Team-ID gebaut sein;
5. Blackstock starten und in der App nach Updates suchen;
6. die App muss das neue signierte Manifest erkennen;
7. Download muss aus der Manifest-Paket-URL erfolgen;
8. Blackstock muss Signatur, Hash und Installer-Team erfolgreich prüfen;
9. erst nach Nutzeraktion darf der macOS-Installer geöffnet werden;
10. Installation im System-Installer abschließen;
11. Blackstock neu starten;
12. der gestartete Bundle-Pfad muss nach Symlink-Auflösung exakt `/Applications/Blackstock.app` sein;
13. Bundle-Version und Build müssen exakt der Manifest-Zielversion entsprechen;
14. `BlackstockSourceCommitSHA` des gestarteten Bundles muss exakt dem signierten Manifest-Source-Commit entsprechen;
15. der SHA-256 des nach dem Update tatsächlich gestarteten Blackstock-Executables wird als `observedInstalledExecutableSHA256` gespeichert und muss im finalen Market-Readiness-Verifier exakt dem veröffentlichten Release und dem Capture-Smoke entsprechen;
16. die gestartete App muss `codesign --verify --deep --strict` bestehen, als `Developer ID Application` signiert sein und dieselbe Apple-Team-ID tragen wie der verifizierte Installer;
17. der macOS-Installer-Receipt `de.blackstock.app` muss vorhanden sein, auf `/` installiert sein und exakt die Zielversion ausweisen.

Blackstock protokolliert diesen Pfad selbst lokal unter:

`~/Library/Application Support/Blackstock/Update/update-evidence.json`

Die Evidenz wird erst vollständig, wenn derselbe ältere Build ein gültiges Manifest akzeptiert hat, das Paket Hash- und Installer-Team-Prüfung bestanden hat, der macOS-Installer tatsächlich geöffnet wurde und anschließend exakt der Manifest-Ziel-Build **aus dem im Manifest signierten Source-Commit** unter `/Applications/Blackstock.app` gestartet ist. Der Post-Update-Start muss zusätzlich dieselbe Developer-ID-Team-ID und einen passenden Installer-Receipt `de.blackstock.app` belegen. Die lokale Updater-Evidence verwendet dafür Schema v5. Schema v5 bindet zusätzlich bereits die Ausgangs-App selbst an Source-Commit, Executable-SHA-256, `/Applications/Blackstock.app`, gültige Developer-ID-Team-ID und passenden Installer-Receipt.

Nach dem erfolgreichen Test:

```bash
python3 Build/validate_in_app_update_evidence.py \
  "$HOME/Library/Application Support/Blackstock/Update/update-evidence.json"
```

Die App darf bei falscher Manifest-Signatur, falschem Hash, falschem Team oder Nicht-HTTPS-URL niemals den Installer öffnen.

## 7. Gate-Regel

Bis die reale Produktions-Evidenz und der vollständige In-App-Update-Test vorliegen, bleiben:

- **Signing = BLOCKED_EXTERNAL**
- **Notarization = BLOCKED_EXTERNAL**
- **Gatekeeper = BLOCKED_EXTERNAL**
- **Updater = FAIL**

Das Vorhandensein des Verifiers allein ist ausdrücklich kein PASS-Nachweis.
