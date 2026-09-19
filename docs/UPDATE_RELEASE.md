# Blackstock Update Release

Blackstock akzeptiert Updates nur über ein HTTPS-Manifest, dessen Signatur mit dem im App-Bundle eingebetteten öffentlichen Update-Schlüssel verifiziert werden kann. Das referenzierte `.pkg` muss zusätzlich exakt dem im Manifest signierten SHA-256 entsprechen. Das Manifest bindet außerdem den exakten 40-stelligen Git-Source-Commit kryptografisch in denselben Signatur-Payload ein.

## Produktionsschlüssel

Der private Update-Signaturschlüssel darf nicht im Repository, im App-Bundle oder in Release-Artefakten gespeichert werden.

Für die Manifest-Erzeugung wird er nur über folgende Umgebungsvariable bereitgestellt:

`BLACKSTOCK_UPDATE_PRIVATE_KEY_BASE64`

Der zugehörige öffentliche Schlüssel wird beim App-Build über:

`BLACKSTOCK_UPDATE_PUBLIC_KEY_BASE64`

in `BlackstockUpdatePublicKeyBase64` geschrieben.

Die Manifest-URL wird über:

`BLACKSTOCK_UPDATE_MANIFEST_URL`

in `BlackstockUpdateManifestURL` geschrieben.

## Manifest erzeugen

Nach dem finalen, signierten und gegebenenfalls notarisierten Paket:

```bash
export BLACKSTOCK_UPDATE_PRIVATE_KEY_BASE64="…"
export BLACKSTOCK_SOURCE_COMMIT_SHA="$(git rev-parse HEAD)"

swift Build/generate_update_manifest.swift \
  --package dist/Blackstock.pkg \
  --package-url "https://updates.example.com/Blackstock.pkg" \
  --version "1.0.0" \
  --build "100" \
  --source-commit-sha "$BLACKSTOCK_SOURCE_COMMIT_SHA" \
  --output dist/update-manifest.json
```

Das Tool:

1. liest das lokale Paket,
2. berechnet den SHA-256 selbst,
3. bindet Version, Build, Paket-URL, Paket-SHA-256 **und Source-Commit-SHA** in denselben Signatur-Payload wie `UpdateManifestVerifier`,
4. signiert ihn mit Curve25519/Ed25519,
5. schreibt das Manifest atomar.

## Sicherheitsregeln

- Manifest und Paket müssen per HTTPS ausgeliefert werden.
- Der private Signaturschlüssel bleibt außerhalb von Git und App-Bundle.
- Ein Paket wird in Blackstock erst nach gültiger Manifest-Signatur geladen.
- Vor der Übergabe an den macOS-Installer werden Paket-Hash **und** Developer-ID-Installer-Team unmittelbar erneut geprüft; erst nach diesem Installations-Preflight wird der System-Installer geöffnet.
- Nach der Installation wird zusätzlich `BlackstockSourceCommitSHA` aus dem App-Bundle gegen den im signierten Manifest gebundenen Source-Commit geprüft; Version/Build allein reichen nicht als Update-Evidenz.
- Blackstock installiert Updates nicht still; der System-Installer wird nur nach ausdrücklicher Nutzeraktion geöffnet.
- Signing, Notarisierung und Gatekeeper bleiben `BLOCKED_EXTERNAL`, bis der reale Produktionspfad mit Apple-Zertifikaten erfolgreich ausgeführt wurde.
- Der Updater bleibt `FAIL`, bis eine reale Update-Endpoint-/Manifest-Konfiguration und ein vollständiger Update-E2E gegen ein signiertes Release nachgewiesen sind.


## Produktionsnachweis

Für den finalen Release-Nachweis gelten zusätzlich `docs/PRODUCTION_RELEASE_EVIDENCE.md`, `BlackstockReleaseVerifier`, `Build/validate_production_release_evidence.py` und `Build/validate_in_app_update_evidence.py`.

Blackstock schreibt beim echten App-Update eine lokale Evidenzkette von der akzeptierten Manifest-Signatur über Paket-Hash und Installer-Team bis zur Übergabe an den macOS-Installer. Erst der anschließend gestartete exakte Ziel-Build kann diese Evidenz vervollständigen.

Der Updater bleibt bis zu diesem realen Produktionslauf ausdrücklich `FAIL`.
