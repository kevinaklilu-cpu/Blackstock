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
| Wrong Channel E2E | FAIL |
| Upload Resume | FAIL |
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

**STATUS: NOCH NICHT MARKTREIF**