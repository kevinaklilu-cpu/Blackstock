# Blackstock 12.0.0 · Build 1200

Blackstock 12 richtet das Produkt um einen lernenden Creator Loop aus.

## Neuer Kernworkflow

`Channel verbinden → Channel DNA → Trend Intelligence → Source Analysis → Format Decision → Remix Director → Quality Gate → Render → Upload → Performance Learning`

## V12 Creator Intelligence

- Persistierte Channel-Strategie pro YouTube-Kanal mit Thema, Zielgruppe, Positionierung, Content-Pillars, Formatmix und Qualitätsgrenze.
- Opportunity Score kombiniert Trendgeschwindigkeit, Nachfrage, Content Gap, Confidence, Qualitäts-Potenzial und Channel-Fit.
- Automatische Formatentscheidung zwischen Short und ca. 5-Minuten-Longform; manuelle Wahl bleibt möglich.
- Remix-Zieldauer wird bis in den tatsächlichen Timeline-Planer durchgereicht.
- Eigener V12 Quality Score für Hook, Pace, Edit, Channel Fit, Transformation, Packaging, Rechte, Technik und erwartete Retention.
- Autopilot darf nur weiter zum Upload, wenn V12 Quality Gate und bestehender Ready Check erfolgreich sind.
- Performance Learning synchronisiert Video-Historie und erzeugt umsetzbare Insights zu Format, Retention, Packaging und Abo-Impact.

## Google / YouTube

- Creator-Loop zeigt OAuth, Google-Account, YouTube-Channel, Analytics- und Upload-Autorisierung getrennt.
- Desktop-OAuth kann aus dem V12-Dashboard eingerichtet werden, wenn ein Entwicklungs-Build keine eingebettete Konfiguration besitzt.
- Verbindung kann gezielt repariert und neu synchronisiert werden.

## Render & Qualität

- Short-Default: 42 Sekunden.
- Longform-Default: 300 Sekunden.
- Universal arm64/x86_64 Build bleibt erhalten.
- macOS 13 bleibt Mindestversion.

## Quellenmodell

Ein YouTube-Trend ist ein Trend-/Redaktionssignal. Automatisches Rendern verwendet nur Medien, die Blackstock technisch abrufen darf und deren Bearbeitungs-/Veröffentlichungsstatus im Projekt geklärt ist. Die YouTube Data API selbst liefert keine beliebigen Videodateien zum Herunterladen.
