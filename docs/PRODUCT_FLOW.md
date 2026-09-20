# Blackstock Product Flow

Diese Regeln konkretisieren den FINAL CANONICAL MASTER PROMPT. Sie ersetzen keine Master-Anforderung.

## Kanonische Produktkette

Discovery → Research → Analysis → Production → Preview → Storyboard → Editing → Packaging → Review → Publishing → Published/Learning

Jede Stufe besitzt:
- einen klaren Zweck,
- reale Eingaben,
- sichtbare Outputs,
- deterministische Eintritts-/Austrittsbedingungen,
- Provenance und Activity-Ereignisse,
- keine stillen Remote-Aktionen.

## UX-Grundsatz: mächtig im Hintergrund, ruhig im Vordergrund

Blackstock zeigt pro Screen primär:
1. den aktuellen Kontext,
2. das wichtigste Medium oder Ergebnis,
3. den nächsten sinnvollen Schritt.

Weitere Details erscheinen progressiv:
- Warum?
- Quelle/Evidence
- Alternativen
- technische Parameter
- Verlauf
- Rechte/Policy
- erweiterte Controls

## Opportunity-Auswahl

Es gibt keinen synthetischen "Virality Score" und keine erfundene Erfolgswahrscheinlichkeit.

Blackstock zeigt ausschließlich reale YouTube-Rohwerte und Provider-eigene Sortierung:
- YouTube View Count,
- Likes,
- Kommentare,
- Veröffentlichungszeit,
- YouTube-Relevanzsortierung,
- YouTube-Datumssortierung,
- YouTube-View-Count-Sortierung.

Blackstock erzeugt aus YouTube-API-Daten keine eigenen Opportunity-, Virality- oder abgeleiteten Performance-Scores. Fehlende Daten bleiben fehlend und werden niemals geschätzt.

Die Nutzeroberfläche priorisiert:
- großes abspielbares Video,
- wenige verständliche Signal-Chips,
- auswählbare transparente Sortierung,
- "Warum hier?" als Disclosure,
- Provider-/Abrufzeit-Provenance.

## Kontinuierlicher Workspace nach dem First-Run

Discovery endet nicht mit der Ersteinrichtung. Nach dem Onboarding bleiben **Chancen** und **Projekte** normale Hauptflächen:

- **Chancen** lädt jederzeit neue reale YouTube-Suchergebnisse für den verbundenen Workspace-Kanal.
- Suchraum und Provider-Sortierung sind sichtbar; Blackstock erzeugt weiterhin keinen eigenen Virality-Score.
- **Als neues Projekt übernehmen** legt einen neuen Research-Loop an, ohne das vorherige Projekt zu löschen.
- **Projekte** zeigt laufende, geprüfte und veröffentlichte Projekte im Verlauf und erlaubt den Wechsel zurück in den jeweils passenden nächsten Schritt.
- Projektgebundene Opportunity-Quelle, Research-Evidence, Studio-Workspace, Publish-/Growth-Daten bleiben an der Projekt-ID gebunden.
- Laufzeitdaten wie Kommentare und Learning-Zustand werden beim Projektwechsel neu auf den gewählten Kontext ausgerichtet, damit kein Zustand eines anderen Projekts in die Oberfläche hineinragt.

Der First-Run richtet also den Workspace ein; er ist **nicht** der einzige Weg, später neue Content-Loops zu starten.

## Research-Video vs. Produktionsmedium

Research-/Opportunity-Videos:
- werden über den offiziellen eingebetteten YouTube-Player in Blackstock angesehen,
- bleiben Provider-Medien,
- werden nicht als versteckte Produktionsdownloads behandelt.

Produktionsmedien:
- werden als echte Videodatei in den Projekt-Workspace übernommen,
- werden automatisch an die ausgewählte Opportunity-/Provider-Quelle gebunden,
- tragen Provenance plus die einmalige Workspace-Nutzererklärung zur Nutzungsverantwortung,
- verlangen danach keine erneute Lizenzdatei oder manuelle Rechte-Referenz pro Video,
- werden nativ über AVFoundation verarbeitet.

Blackstock erteilt oder verifiziert dabei keine Lizenz. Der Nutzer bestätigt einmalig auf Workspace-Ebene, nur Inhalte zu bearbeiten und zu veröffentlichen, die er verwenden darf, und übernimmt die Verantwortung für diese Nutzung. Fehlt diese Erklärung, bleibt der Produktions-/Clip-Pfad gesperrt.

## Studio

Das Studio folgt Preview → Storyboard → Timeline/EditGraph.

Grundregeln:
- Player bleibt visuell dominant.
- Inspector zeigt nur kontextrelevante Aktionen.
- AI-Vorschläge sind zunächst Vorschläge, keine unsichtbaren Edits.
- Übernommene Edits erzeugen eine EditGraph-Revision.
- Undo/Redo ist non-destruktiv.
- Activity Ledger zeigt, was wann von wem geändert wurde.
- Nicht implementierte Werkzeuge bleiben verborgen.

## Lokale Clip-Kandidaten

Auf einem **autorisierten lokalen Produktionsmedium** kann Blackstock im Studio Clip-Kandidaten vollständig lokal erzeugen:

1. On-Device-Spracherkennung erzeugt zeitgebundene Sprachsegmente auf dem Originalmedium.
2. Ein deterministischer lokaler Generator nutzt Segmentgrenzen und gemessene Pausen, um zusammenhängende Ausschnitte vorzuschlagen.
3. Jeder Vorschlag zeigt ausschließlich nachvollziehbare Fakten: Quell-Zeitbereich, Dauer, Wortzahl, Transkript-Vorschau und – falls verfügbar – Spracherkennungs-Konfidenz.
4. Es gibt keinen Viralitäts-, Gewinner-, Qualitäts- oder Erfolgs-Score.
5. **„Vorschau abspielen“** spielt den Kandidaten im Hauptplayer, ohne den EditGraph zu ändern; **„Zurück zur aktuellen Schnittvorschau“** stellt den bestehenden Schnitt wieder her.
6. Erst **„Diesen Ausschnitt übernehmen“** schreibt einen Trim in den EditGraph.
7. Der Trim bleibt non-destruktiv und ist über Undo/Redo reversibel. Bestehende weitere EditGraph-Operationen bleiben nachvollziehbar erhalten.

Diese lokale Funktion ersetzt **keine** Ingest-Berechtigung für fremde YouTube-Videos. Ein Research-Video bleibt Playback/Research, solange keine zulässige Produktionsquelle oder ein verifiziert freigegebener Ingest-Pfad vorliegt.

## Sichtbare lokale Burn-in-Captions

Nach der lokalen On-Device-Transkription kann der Nutzer **„Sichtbare Captions ins Video rendern“** explizit aktivieren.

- Die VTT-Datei bleibt separat für YouTube/Packaging erhalten.
- Der Studio-Player zeigt bei aktivierter Option dieselben Transcript-Zeitfenster als sichtbare Caption-Vorschau.
- Der finale lokale MP4-Render erhält einen zweiten AVFoundation/Core-Animation-Pass und brennt diese Captions tatsächlich in die Bildpixel ein.
- Burn-in ist projektbezogen gespeichert und standardmäßig deaktiviert, bis der Nutzer es einschaltet.
- Ändert ein Schnitt die Transcript-Timeline, verwirft Blackstock veraltete Caption-/Burn-in-Zustände statt falsche Texte weiterzuverwenden.
- Aktivieren oder Deaktivieren invalidiert einen bestehenden Render, damit Packaging nie still ein Video mit einer anderen Caption-Konfiguration verwendet.
- Alles läuft lokal; für Burn-in-Captions ist kein Cloud-Provider erforderlich.

## Visuelle Zusatzaufnahmen

Kamera- und Bildschirmaufnahmen können nach dem Hauptmedium als zusätzliche projektgebundene Produktionsmedien gespeichert werden, ohne den Hauptschnitt zu ersetzen.

- Jede zusätzliche Videoaufnahme behält Rechte-Provenance und gemessene Dauer.
- Der Nutzer kann sie als zeitgesteuerte visuelle Einblendung aktivieren und Zielstart, Quellstart sowie Dauer festlegen.
- Die Einblendung ersetzt im gewählten Zeitfenster nur das Bild; der Hauptton des aktuellen Schnitts läuft weiter.
- Bereiche werden deterministisch an Quell- und Ausgabedauer begrenzt; leere oder nicht nutzbare Bereiche werden nicht gerendert.
- Der finale AVFoundation-Render führt die Einblendungen vor Caption-/Text-Burn-in aus, sodass sichtbare Captions und Text-Overlays darüber korrekt erhalten bleiben.
- Änderungen an visuellen Einblendungen invalidieren veraltete Render- und Packaging-Artefakte.

## Multi-Clip-Ausgabe und Packaging

Gespeicherte lokale Clip-Kandidaten können als eigene validierte MP4-Dateien gerendert werden. Danach stehen zwei getrennte Nutzeraktionen zur Verfügung:

- **Exportieren …** kopiert alle bereits validiert gerenderten Clips in einen vom Nutzer gewählten Ordner. Falls für einen Clip ein lokales Transkript vorliegt, wird zusätzlich eine WebVTT-Datei erzeugt. Ein JSON-Manifest bindet Clip-ID, Quell-Zeitbereich, Dateiname und Render-SHA-256.
- Gespeicherte Clips können einen eigenen Nutzer-Titel erhalten. Alte Projekte ohne Clip-Titel bleiben kompatibel.
- **Für Packaging verwenden** übernimmt genau einen validierten gespeicherten Clip als aktuellen Packaging-/Review-Kandidaten. Der Clip wird dabei in den aktiven Schnittkontext geladen, damit Vorschau, Transkript, Audio-QC und Veröffentlichungspaket auf demselben Inhalt basieren.
- Ein explizit vergebener Clip-Titel wird als Packaging-Titel vorgeschlagen. Bereits gespeicherte Packaging-Metadaten haben Vorrang und werden nicht still überschrieben.

Batch-Export und Publishing bleiben bewusst getrennt: Export schreibt nur lokale Dateien. Eine externe Veröffentlichung erfordert weiterhin die normalen Review-, Rechte-, Kanal- und Bestätigungsgates.

## Keine Überladung

Navigation zeigt keine nicht validierten Produktflächen.
Komplexe Funktionen werden erst sichtbar, wenn:
- Capability real implementiert,
- Policy erlaubt,
- Daten vorhanden,
- Berechtigung vorhanden,
- Qualität geprüft,
- Tests bestanden.

**STATUS: NOCH NICHT MARKTREIF**


## Zero-Cost-Processing

Blackstock wird so gebaut, dass Nutzer keine laufenden Pflichtkosten für externe AI-/Video-APIs tragen müssen.

Priorität:
1. lokale native Verarbeitung auf dem Mac,
2. offizielle kostenlose Kontingente,
3. optionale kostenlose externe Provider,
4. kostenpflichtige Provider nur nach expliziter zukünftiger Aktivierung – niemals automatisch.

Regeln:
- allowPaidProviders = false ist der Standard.
- Ein erschöpftes Gratis-Kontingent darf niemals still in Pay-as-you-go wechseln.
- Wenn lokale Verarbeitung verfügbar ist, gewinnt sie vor externen Providern.
- Provider-Schlüssel gehören nicht in die normale macOS-App.
- Kostenlose externe Provider werden capability-gated und mit lastVerifiedAt geführt.
- Ändert ein Anbieter sein Preismodell, fällt Blackstock lokal zurück oder markiert die Capability als nicht verfügbar.
- OpusClip API ist ein optionaler Adapter und keine Produktabhängigkeit.

## Link-first Opportunity → Clip

Für Nutzer bleibt der Ablauf ohne Copy/Paste:
1. Trend-/Opportunity-Video auswählen.
2. Als Clip verwenden wählen.
3. Die einmalige Workspace-Nutzererklärung muss vorhanden sein; pro Video gibt es keine erneute Lizenzmaske.
4. Blackstock übernimmt Provider-ID/Quell-URL intern und bindet die spätere Produktionsdatei automatisch an dieselbe Opportunity.
5. Der Media Source Resolver wählt einen zulässigen kostenlosen oder lokalen Verarbeitungspfad.
6. Der Job zeigt nur reale Zustände: Quelle auflösen → Verarbeitung → Clips verfügbar / Fehler.
7. Clips werden im Blackstock-Studio visuell geprüft und weiterbearbeitet.
8. Render, Review und Upload folgen den kanonischen Gates.

Wenn für eine fremde YouTube-Quelle kein zulässiger kostenloser Remote-Ingest-Pfad verfügbar ist, behauptet Blackstock keinen funktionierenden Ingest. Dieser konkrete Provider-Gap bleibt sichtbar, bis ein zulässiger kostenloser Provider verfügbar ist.
