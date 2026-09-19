# Release Gates

Statuswerte: **PASS / FAIL / BLOCKED_EXTERNAL**.

| Gate | Status |
| --- | --- |
| Product Journey | FAIL |
| Guided Experience | FAIL |
| Strategy | FAIL |
| Language | FAIL |
| Research | FAIL |
| Temporal Semantics | FAIL |
| Grounding / Provenance | FAIL |
| Discovery | FAIL |
| Rights | FAIL |
| Capture | FAIL |
| Editing | FAIL |
| Audio | FAIL |
| Captions | FAIL |
| Packaging | FAIL |
| Video QC / 4K | FAIL |
| Publishing | FAIL |
| Wrong Channel E2E | PASS |
| Upload Resume | PASS |
| Analytics | PASS |
| Comments | PASS |
| Security | PASS |
| Privacy | PASS |
| Accessibility | FAIL |
| Recovery | PASS |
| Migration | PASS |
| Installer | PASS |
| Signing | BLOCKED_EXTERNAL |
| Notarization | BLOCKED_EXTERNAL |
| Gatekeeper | BLOCKED_EXTERNAL |
| Updater | FAIL |
| Clean-Machine E2E | FAIL |

Hinweis: **Installer = PASS** basiert auf der Canonical-CI: Das erzeugte `.pkg` wird auf einem frischen macOS-Runner installiert, Bundle-Metadaten und Codesign werden geprüft und die installierte App wird gestartet. **Clean-Machine E2E** bleibt FAIL, weil dieser Smoke-Test noch keinen vollständigen Nutzerpfad bis Veröffentlichung und Lernen abdeckt.

Hinweis: **Comments = PASS** bezieht sich auf den implementierten read-only Pfad für veröffentlichte Videos: GET-only YouTube-CommentThreads, Plaintext, Pagination, spezifische Providerfehler, erneute Zielkanal-Identitätsprüfung und Video-/Kanal-Kontext-Hard-Stop. Schreib-, Antwort- oder Moderationsaktionen sind daraus ausdrücklich nicht abgeleitet.

Hinweis: **Wrong Channel E2E = PASS** basiert auf den deterministischen Hard-Stop-Tests: Ein falscher Workspace-Kanal oder falscher autorisierter Upload-Kanal stoppt vor Datei-/Journal-Mutation. Zusätzlich muss die aktuell von YouTube gelieferte autorisierte Kanalidentität eindeutig und exakt dem Projekt-Zielkanal entsprechen.

Hinweis: **Upload Resume = PASS** basiert auf dem deterministischen Resumable-Upload-End-to-End-Test: Eine vorhandene Remote-Session wird abgefragt, der von YouTube gemeldete Remote-Offset gewinnt gegenüber lokalem Zwischenstand, nur der verbleibende Byte-Range wird übertragen, jeder PUT ist authentifiziert und der Fortschritt wird persistent bis `remoteCommitted` mit Video-ID und finalem Offset fortgeschrieben.

Hinweis: **Analytics = PASS** basiert auf den deterministischen YouTube-Analytics-Contract- und Kontexttests: Abrufe sind an ein veröffentlichtes Projekt, denselben Projekt-Datensatz, denselben Zielkanal und eine konkrete Video-ID gebunden; vor dem Abruf wird die aktuell autorisierte YouTube-Kanalidentität erneut validiert. Fehlende Provider-Zeilen bleiben fehlend statt als Nullwerte erfunden zu werden, und inkonsistente Responses führen zum Hard-Stop.

Hinweis: **Security = PASS** bezieht sich auf die deterministisch abgesicherten App-Pfade: Google Desktop OAuth verwendet PKCE S256 und zufälligen State, der Callback lauscht ausschließlich auf 127.0.0.1 und akzeptiert nur den erwarteten Callback-Pfad, OAuth-Berechtigungen werden capability-basiert minimiert und bei Erweiterung neu autorisiert, Tokens/Scopes/OAuth-Client-Bindung liegen im gerätegebundenen macOS-Keychain mit Zugriff nur im entsperrten Zustand, und ein Wechsel der OAuth-Client-ID invalidiert die bestehende Autorisierung. Zusätzlich sind Update-Manifest, Paket-Hash und Developer-ID-Installer-Team kryptografisch bzw. systemseitig gebunden. Die separaten Apple-Gates Signing, Notarization und Gatekeeper bleiben davon unberührt und weiterhin BLOCKED_EXTERNAL.

Hinweis: **Privacy = PASS** basiert auf lokaler Datenhaltung, gerätegebundenem Keychain für Google-/YouTube-Zugangsdaten, sicherem OAuth-JSON-Import ohne Persistenz des client_secret, nichtpersistentem WebKit-Speicher für eingebettete YouTube-Recherche mit youtube-nocookie.com sowie einer bestätigungspflichtigen Löschfunktion, die Blackstock-Keychain-Einträge, blackstock.*-Einstellungen und den lokalen Application-Support-Datenbaum entfernt und Teilfehler sichtbar meldet.

Hinweis: **Recovery = PASS** basiert auf validierter lokaler Workspace-Wiederherstellung: Vor einem neuen atomaren Save wird nur ein lesbarer, zum Projekt gehörender Primärstand als Backup gesichert. Ist der Primärstand beschädigt, lädt Blackstock den letzten validierten Backup-Stand, protokolliert die Wiederherstellung im Activity Ledger und persistiert den wiederhergestellten Zustand erneut. Ein beschädigter Primärstand darf ein vorhandenes valides Backup nicht überschreiben.

Hinweis: **Migration = PASS** basiert auf versionierter Persistenz für Studio-Workspace, Publish-Preparation sowie Published-/Growth-Learning-Daten. Unversionierte Legacy-Dateien werden deterministisch auf das aktuelle Schema migriert und erneut atomar gespeichert; unbekannte Future-Schema-Versionen führen zum Hard-Stop statt zu stiller Fehlinterpretation.

Hinweis: **Updater = FAIL** bleibt absichtlich bestehen. Manifest-Signatur, HTTPS-Pflicht, SHA-256-Paketprüfung und Developer-ID-Installer-Teamprüfung sind implementiert; für PASS fehlen weiterhin eine reale Produktions-Endpoint-Konfiguration und ein vollständiger Update-E2E gegen ein tatsächlich signiertes Release.

**STATUS: NOCH NICHT MARKTREIF**