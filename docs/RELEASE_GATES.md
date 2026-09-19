# Release Gates

Statuswerte: **PASS / FAIL / BLOCKED_EXTERNAL**.

| Gate | Status |
| --- | --- |
| Product Journey | FAIL |
| Guided Experience | FAIL |
| Strategy | FAIL |
| Language | PASS |
| Research | FAIL |
| Temporal Semantics | PASS |
| Grounding / Provenance | FAIL |
| Discovery | FAIL |
| Rights | PASS |
| Capture | FAIL |
| Editing | PASS |
| Audio | FAIL |
| Captions | PASS |
| Packaging | PASS |
| Video QC / 4K | PASS |
| Publishing | PASS |
| Wrong Channel E2E | PASS |
| Upload Resume | PASS |
| Analytics | PASS |
| Comments | PASS |
| Security | PASS |
| Privacy | PASS |
| Accessibility | PASS |
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

Hinweis: **Language = PASS** basiert auf konsequenter deutscher Produktsprache in den kritischen First-Run-, Studio-, Review-, Einstellungen- und Journey-Flächen sowie einer davon getrennten, persistenten Content-Sprache. Die Content-Sprache wird bis zu YouTube `defaultLanguage` und `defaultAudioLanguage` weitergegeben. `Build/audit_language.py` läuft in der Canonical-CI und blockiert Regressionen auf bekannte englische Produktbegriffe.

Hinweis: **Temporal Semantics = PASS** trennt elapsed Beobachtungsfenster von YouTube-Analytics-Kalenderperioden, verwendet die getestete Pacific-Date-Semantik des Providers und kennzeichnet Analytics-Snapshots ausdrücklich als `providerMayLag`. Abrufzeitpunkt, angefragter Start-/Endzeitraum und Veröffentlichungszeit werden nicht miteinander vermischt. `Build/audit_temporal.py` läuft in der Canonical-CI.

Hinweis: **Rights = PASS** basiert auf einer expliziten, versionierten Nutzer-Rechtebestätigung plus konkretem Rechte-/Eigentumsnachweis am Produktionsmedium. Unknown/Prohibited, fehlende Evidenz oder fehlende Attestation verhindern den Eintritt in die Produktion; dieselbe Rechtefreigabe wird als Quality-Evidence geführt und am Publish-Preflight erneut zwingend geprüft.

Hinweis: **Editing = PASS** umfasst den persistenten nicht-destruktiven EditGraph mit Undo/Redo, Timeline/Storyboard, Trim, überlappungsbereinigte Remove-Range-Operationen und manuelles Reframe. Vorschau und finaler AVFoundation-Render verwenden dieselben editierenden Operationen; Änderungen invalidieren stale Render-/Audio-Evidenz und werden im Activity Ledger nachvollziehbar gespeichert.

Hinweis: **Capture = FAIL** bleibt bewusst bestehen: Der Canonical-Gate verlangt Camera/Mic/Screen/System-Audio-Capture. Der vorhandene autorisierte Datei-Ingest in den lokalen Projekt-Workspace ist dafür wertvolle Media-Infrastruktur, ersetzt diese vier Capture-Pfade aber nicht.

Hinweis: **Audio bleibt FAIL**. Bereits vorhanden und belegt sind Messungen des finalen gerenderten Edits, nicht des Rohmaterials: Blackstock prüft Audiospur, Sample-Rate und Kanalzahl und analysiert lokal PCM-Samples für Peak, RMS und Full-Scale-Samples. Fehlende Audiospur oder eine Analyse ohne Samples sind Blocker; mögliche Qualitätsprobleme bleiben als Warnungen und eine hörbare Prüfung auf Verständlichkeit, Störgeräusche und Pegelsprünge bleibt explizite Review-Evidenz. Peak/RMS werden nicht fälschlich als LUFS ausgegeben.

Hinweis: **Captions = PASS** basiert auf der transkribierten editierten Timeline, nicht auf dem ungeänderten Quellmedium. WebVTT/SRT werden vor dem Review technisch validiert; ungültige UTF-8-Daten, fehlende/ungültige Timings, leere Cues, nicht-monotone Reihenfolge und Überlappungen blockieren die Veröffentlichung. Caption-Uploads laufen zusätzlich journaled/idempotent über den gebundenen YouTube-Publishing-Pfad.

Hinweis: **Packaging = PASS** umfasst persistente Publish-Pakete und Review-Evidenz, bis zu drei Titel-/Thumbnail-Varianten ohne erfundenen Gewinner, YouTube-Metadatenlimits, dauerhaft in den Projekt-Workspace übernommene Assets, technische Thumbnail-Prüfung sowie erneute Caption-/Thumbnail-Validierung am Publish-Gate. Qualitative Bereiche werden nicht automatisch erfunden, sondern benötigen deterministische Evidenz oder eine konkrete Nutzer-Prüfnotiz.

Hinweis: **Video QC / 4K = PASS** basiert auf dem realen lokalen AVFoundation-Render und technischer Nachprüfung der erzeugten Datei: Datei, Dauer, Videotrack und Geometrie müssen zum aktuellen Edit passen. Zusätzlich wird der tatsächlich gewählte Render-Preset gegen die echte Ausgabeauflösung geprüft; ein 1080p-Artefakt kann deshalb nicht mehr als erfolgreicher 4K-Render gelten. Die definierten 4K-Ausgaben sind 3840×2160, 2160×3840 bzw. 2160×2160 für Landscape, Portrait und Square.

Hinweis: **Publishing = PASS** bezieht sich auf den sicheren kanonischen YouTube-Pfad: vollständiger Review-/Rights-/Render-/Packaging-Preflight, echte Netzwerkprüfung, unmittelbar erneute Verifikation genau eines autorisierten Projekt-Zielkanals, finaler ausdrücklicher Nutzer-Confirm, resumable/idempotenter Upload und journaled Thumbnail-/Caption-Aktionen. Public/Unlisted bleibt zusätzlich hinter dem separat auditierten Build-Flag gesperrt; ohne dieses Flag ist nur der freigegebene private Publish-Pfad zulässig.

Hinweis: **Accessibility = PASS** umfasst zusätzlich deterministischen Keyboard-/Focus-Zugriff über die fokussierte ⌘K-Command-Palette sowie CI-Verträge für Reduced Motion, Contrast und Text Scaling: kritische Flächen dürfen keine ungebundenen Custom-Animationen, festen RGB-Farben oder festen Punktgrößen enthalten. `docs/ACCESSIBILITY.md` dokumentiert den Vertrag. Bereits vorhanden und CI-abgesichert sind expliziter VoiceOver-Semantik für die kritischen First-Run-, Studio- und Veröffentlichungsprüfungs-Kontrollen, inklusive dynamischer Accessibility-Werte für Trim-/Reframe-Regler sowie Beschriftungen für icon-only Aktionen und Controls mit ausgeblendeten sichtbaren Labels. Die Canonical-CI führt zusätzlich `Build/audit_accessibility.py` aus und blockiert Regressionen bei diesen Semantik-Verträgen.

Hinweis: **Security = PASS** basiert zusätzlich auf dem versionierten `docs/THREAT_MODEL.md` und der in der Canonical-CI ausgeführten `Build/audit_security.py`-Suite. Der Audit erzwingt die kritischen Quellcode-Verträge und zentrale Negativtests. Bereits umgesetzt sind die deterministisch abgesicherten App-Pfade: Google Desktop OAuth verwendet PKCE S256 und zufälligen State, der Callback lauscht ausschließlich auf 127.0.0.1 und akzeptiert nur den erwarteten Callback-Pfad, OAuth-Berechtigungen werden capability-basiert minimiert und bei Erweiterung neu autorisiert, Tokens/Scopes/OAuth-Client-Bindung liegen im gerätegebundenen macOS-Keychain mit Zugriff nur im entsperrten Zustand, und ein Wechsel der OAuth-Client-ID invalidiert die bestehende Autorisierung. Zusätzlich sind Update-Manifest, Paket-Hash und Developer-ID-Installer-Team kryptografisch bzw. systemseitig gebunden. Die separaten Apple-Gates Signing, Notarization und Gatekeeper bleiben davon unberührt und weiterhin BLOCKED_EXTERNAL.

Hinweis: **Privacy = PASS** umfasst zusätzlich Remote-Revoke der Google-OAuth-Berechtigung, einen lokalen Nutzer-Datenexport ohne Keychain-/OAuth-Geheimnisse und eine explizite Retention-Policy mit automatischer Bereinigung abgelaufener temporärer Update-Pakete. `Build/audit_privacy.py` und die Swift-Tests sichern diese Verträge in der Canonical-CI ab. Bereits umgesetzt sind lokaler Datenhaltung, gerätegebundenem Keychain für Google-/YouTube-Zugangsdaten, sicherem OAuth-JSON-Import ohne Persistenz des client_secret, nichtpersistentem WebKit-Speicher für eingebettete YouTube-Recherche mit youtube-nocookie.com sowie einer bestätigungspflichtigen Löschfunktion, die Blackstock-Keychain-Einträge, blackstock.*-Einstellungen und den lokalen Application-Support-Datenbaum entfernt und Teilfehler sichtbar meldet.

Hinweis: **Recovery = PASS** basiert auf validierter lokaler Workspace-Wiederherstellung: Vor einem neuen atomaren Save wird nur ein lesbarer, zum Projekt gehörender Primärstand als Backup gesichert. Ist der Primärstand beschädigt, lädt Blackstock den letzten validierten Backup-Stand, protokolliert die Wiederherstellung im Activity Ledger und persistiert den wiederhergestellten Zustand erneut. Ein beschädigter Primärstand darf ein vorhandenes valides Backup nicht überschreiben.

Hinweis: **Migration = PASS** basiert auf versionierter Persistenz für Studio-Workspace, Publish-Preparation sowie Published-/Growth-Learning-Daten. Unversionierte Legacy-Dateien werden deterministisch auf das aktuelle Schema migriert und erneut atomar gespeichert; unbekannte Future-Schema-Versionen führen zum Hard-Stop statt zu stiller Fehlinterpretation.

Hinweis: **Updater = FAIL** bleibt absichtlich bestehen. Manifest-Signatur, HTTPS-Pflicht, SHA-256-Paketprüfung und Developer-ID-Installer-Teamprüfung sind implementiert; für PASS fehlen weiterhin eine reale Produktions-Endpoint-Konfiguration und ein vollständiger Update-E2E gegen ein tatsächlich signiertes Release.

Hinweis zur strikten Gate-Auslegung: **Audio** benötigt zusätzlich den im Canonical-Gate geforderten professionellen Audio-Toolset-Nachweis; Die vorhandenen Teilimplementierungen bleiben erhalten, reichen aber bewusst nicht für PASS.

**STATUS: NOCH NICHT MARKTREIF**