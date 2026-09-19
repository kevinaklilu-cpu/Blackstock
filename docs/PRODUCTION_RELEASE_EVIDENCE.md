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

## 2. Produktionspaket erzeugen

Beispiel:

```bash
export BLACKSTOCK_VERSION="1.0.0"
export BLACKSTOCK_BUILD="100"
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
  --output release-evidence.json
```

Ein erfolgreicher Lauf schreibt `BLACKSTOCK_RELEASE_VERIFY_PASS`.

Er prüft:

- Manifest wird tatsächlich über HTTPS geladen.
- Manifest-Signatur ist mit dem eingebetteten öffentlichen Schlüssel gültig.
- Manifest beschreibt gegenüber der Ausgangsversion tatsächlich ein Update.
- Paket wird von der im Manifest angegebenen HTTPS-URL geladen.
- Paket-SHA-256 entspricht exakt dem signierten Manifest.
- Paket ist ein Developer-ID-Installer des erwarteten Apple-Teams.
- Stapled Notarization Ticket ist gültig.
- Gatekeeper akzeptiert das Installer-Paket.
- optional: installierte App besteht `codesign --deep --strict`.
- optional: installierte App weist Developer ID Application und erwartete Team-ID aus.
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

1. ältere Produktionsversion installieren;
2. prüfen, dass deren Bundle-Version exakt der dokumentierten Ausgangsversion entspricht;
3. diese Version muss mit der realen Produktions-Manifest-URL, dem öffentlichen Update-Schlüssel und der erwarteten Installer-Team-ID gebaut sein;
4. Blackstock starten und in der App nach Updates suchen;
5. die App muss das neue signierte Manifest erkennen;
6. Download muss aus der Manifest-Paket-URL erfolgen;
7. Blackstock muss Signatur, Hash und Installer-Team erfolgreich prüfen;
8. erst nach Nutzeraktion darf der macOS-Installer geöffnet werden;
9. Installation im System-Installer abschließen;
10. Blackstock neu starten;
11. Bundle-Version und Build müssen exakt der Manifest-Zielversion entsprechen.

Blackstock protokolliert diesen Pfad selbst lokal unter:

`~/Library/Application Support/Blackstock/Update/update-evidence.json`

Die Evidenz wird erst vollständig, wenn derselbe ältere Build ein gültiges Manifest akzeptiert hat, das Paket Hash- und Installer-Team-Prüfung bestanden hat, der macOS-Installer tatsächlich geöffnet wurde und anschließend exakt der Manifest-Ziel-Build gestartet ist.

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
