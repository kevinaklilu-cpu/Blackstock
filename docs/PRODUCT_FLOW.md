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

## Research-Video vs. Produktionsmedium

Research-/Opportunity-Videos:
- werden über den offiziellen eingebetteten YouTube-Player in Blackstock angesehen,
- bleiben Provider-Medien,
- werden nicht als versteckte Produktionsdownloads behandelt.

Produktionsmedien:
- müssen lokal/autorisiert oder rechtlich belegbar erworben sein,
- tragen Rechte-/Herkunftsnachweis,
- werden nativ über AVFoundation verarbeitet.

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
3. Rechte-/Nutzungsbestätigung prüfen.
4. Blackstock übernimmt die bekannte Quell-URL intern.
5. Der Media Source Resolver wählt einen zulässigen kostenlosen oder lokalen Verarbeitungspfad.
6. Der Job zeigt nur reale Zustände: Quelle auflösen → Verarbeitung → Clips verfügbar / Fehler.
7. Clips werden im Blackstock-Studio visuell geprüft und weiterbearbeitet.
8. Render, Review und Upload folgen den kanonischen Gates.

Wenn für eine fremde YouTube-Quelle kein zulässiger kostenloser Remote-Ingest-Pfad verfügbar ist, behauptet Blackstock keinen funktionierenden Ingest. Dieser konkrete Provider-Gap bleibt sichtbar, bis ein zulässiger kostenloser Provider verfügbar ist.
