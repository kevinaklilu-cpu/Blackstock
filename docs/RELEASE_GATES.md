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
| Analytics | FAIL |
| Comments | PASS |
| Security | FAIL |
| Privacy | FAIL |
| Accessibility | FAIL |
| Recovery | FAIL |
| Migration | FAIL |
| Installer | PASS |
| Signing | BLOCKED_EXTERNAL |
| Notarization | BLOCKED_EXTERNAL |
| Gatekeeper | BLOCKED_EXTERNAL |
| Updater | FAIL |
| Clean-Machine E2E | FAIL |

Hinweis: **Installer = PASS** basiert auf der Canonical-CI: Das erzeugte `.pkg` wird auf einem frischen macOS-Runner installiert, Bundle-Metadaten und Codesign werden geprüft und die installierte App wird gestartet. **Clean-Machine E2E** bleibt FAIL, weil dieser Smoke-Test noch keinen vollständigen Nutzerpfad bis Veröffentlichung und Lernen abdeckt.

Hinweis: **Comments = PASS** bezieht sich auf den implementierten read-only Pfad für veröffentlichte Videos: GET-only YouTube-CommentThreads, Plaintext, Pagination, spezifische Providerfehler, erneute Zielkanal-Identitätsprüfung und Video-/Kanal-Kontext-Hard-Stop. Schreib-, Antwort- oder Moderationsaktionen sind daraus ausdrücklich nicht abgeleitet.

Hinweis: **Wrong Channel E2E = PASS** basiert auf den deterministischen Hard-Stop-Tests: Ein falscher Workspace-Kanal oder falscher autorisierter Upload-Kanal stoppt vor Datei-/Journal-Mutation. Zusätzlich muss die aktuell von YouTube gelieferte autorisierte Kanalidentität eindeutig und exakt dem Projekt-Zielkanal entsprechen.

Hinweis: **Upload Resume = PASS** basiert auf dem deterministischen Resume-E2E-Test: Eine persistierte YouTube-Resumable-Session wird nach Neustart/Reload weiterverwendet, der Remote-Offset per `308 Range` abgefragt, exakt ab dem nächsten Byte fortgesetzt, jeder Status-/Chunk-`PUT` authentifiziert und der finale Video-Commit inklusive Offset persistent im External Action Journal gespeichert.

**STATUS: NOCH NICHT MARKTREIF**