# Blackstock Threat Model

Stand: 2026-09-19

## Ziel und Schutzgüter

Blackstock ist eine lokale macOS-Anwendung für Recherche, Produktion, Publishing und Analytics. Das Threat Model schützt insbesondere:

- Google-/YouTube-OAuth-Tokens und gewährte Scopes,
- die Bindung eines Projekts an den ausdrücklich gewählten YouTube-Zielkanal,
- lokale Projekt-, Medien-, Review- und Analytics-Daten,
- Publish-Aktionen mit externen Seiteneffekten,
- Update-Manifeste und Installer-Pakete,
- die Integrität lokaler persistenter Zustände.

## Vertrauensgrenzen

1. **macOS App / lokaler Benutzerkontext** – Blackstock-Code und lokaler Application-Support-Bereich.
2. **macOS Keychain** – separates Betriebssystem-Sicherheitsboundary für OAuth-Geheimnisse.
3. **Browser ↔ Loopback OAuth** – untrusted Browser-Eingang; nur 127.0.0.1 und der fest definierte Callback-Pfad sind zulässig.
4. **Google/YouTube APIs** – externe Providergrenze; Responses gelten nicht implizit als zum Projekt passend und werden gegen Projekt-/Kanal-/Video-Kontext geprüft.
5. **Update-Infrastruktur** – Netzwerk und CDN sind untrusted; Vertrauen entsteht erst durch Ed25519-Manifest-Signatur, SHA-256-Paketbindung und Developer-ID-Installer-Teamprüfung.
6. **Lokale Persistenz** – Dateien können beschädigt, veraltet oder aus einer inkompatiblen Zukunftsversion stammen; Schema- und Projektbindung werden vor Verwendung validiert.

## Angreiferannahmen

Berücksichtigt werden:

- manipulierte oder fremde OAuth-Callbacks,
- CSRF-/State-Replay-Versuche,
- Netzwerkmanipulation und kompromittierte Update-Auslieferung,
- falsche oder mehrdeutige YouTube-Kanalidentität,
- manipulierte lokale JSON-Zustände,
- versehentliche oder absichtliche Scope-Ausweitung,
- Token-Exfiltration aus normaler Dateipersistenz,
- Wiederholung externer Publish-Aktionen nach Crash/Retry,
- manipulierte Installer-Pakete oder Pakete eines fremden Apple-Teams.

Nicht als durch die App lösbar angenommen werden vollständige Kompromittierung des entsperrten Benutzerkontos, Kernel-/Root-Kompromittierung oder kompromittierte Apple-/Google-Root-of-Trust-Infrastruktur.

## Sicherheitskontrollen

### OAuth und Credentials

- Authorization Code Flow mit PKCE S256.
- Kryptografisch zufälliger OAuth-State.
- Callback-Listener bindet ausschließlich an `127.0.0.1`.
- Nur `/oauth2/callback` wird akzeptiert.
- Capability-basierte minimale Scopes; Scope-Erweiterungen verlangen neue Autorisierung.
- OAuth-Token, Scopes und Client-Bindung werden im macOS-Keychain gespeichert.
- Keychain-Einträge verwenden `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`.
- Änderung der OAuth-Client-ID invalidiert die bestehende lokale Autorisierung.
- Importierte Desktop-OAuth-Konfiguration persistiert kein `client_secret`.

### Kanal- und Publishing-Sicherheit

- Projekt, Workspace und autorisierter Provider-Kanal müssen exakt zusammenpassen.
- Kanalidentität wird unmittelbar vor externen Publishing-Aktionen erneut abgefragt.
- Falscher oder mehrdeutiger Kanal führt vor Seiteneffekten zum Hard-Stop.
- Resumable Uploads sind journaled und idempotent; Remote-Status gewinnt beim Resume.
- Public/Unlisted-Publishing ist zusätzlich durch ein auditiertes Build-Flag begrenzt.
- Reale Veröffentlichung verlangt eine finale ausdrückliche Nutzerbestätigung.

### Update-Sicherheit

- Manifest und Paket-URL müssen HTTPS verwenden.
- Update-Manifest wird mit Ed25519 verifiziert.
- Das Paket muss dem signierten SHA-256 entsprechen.
- Vor Installer-Handoff wird die Integrität erneut geprüft.
- Das Paket muss eine gültige Developer-ID-Installer-Signatur des erwarteten Team-ID-Besitzers tragen.
- Fehlgeschlagene Prüfungen verwerfen das Paket; keine stille Installation.

### Persistenz und Wiederherstellung

- Persistenzdateien sind schemaversioniert.
- Unknown Future Schema führt zum Hard-Stop.
- Projektgebundene Daten werden gegen die erwartete Projekt-ID validiert.
- Nur validierte Primärzustände dürfen ein Recovery-Backup ersetzen.
- Beschädigte Primärdaten können aus dem letzten validierten lokalen Backup wiederhergestellt werden.

## Security-Test-Suite

Die Canonical-CI führt `Build/audit_security.py` und `swift test` aus.

Der statische Security-Audit erzwingt kritische Sicherheitsverträge in den produktiven Quellen und das Vorhandensein zentraler Negativtests. Die Swift-Tests decken unter anderem manipulierte Update-Manifeste, unsichere HTTP-Update-URLs, falsche Installer-Team-IDs, falsche Publishing-Kanäle, Resume-/Idempotenzpfade sowie Schema-Hard-Stops ab.

## Residual Risks / externe Gates

- Produktions-Signing, Apple-Notarisierung und Gatekeeper-Evidenz bleiben separate `BLOCKED_EXTERNAL` Gates.
- Ein vollständig kompromittiertes entsperrtes macOS-Benutzerkonto liegt außerhalb des App-Sicherheitsmodells.
- Provider-Ausfälle, Quota-Änderungen und kompromittierte Provider-Accounts werden nicht als durch lokale Kryptografie verhinderbar betrachtet.
