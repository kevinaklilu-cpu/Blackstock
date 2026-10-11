# Blackstock 1.0

Blackstock ist eine native macOS-Produktionsumgebung für den vollständigen YouTube-Workflow: Signale entdecken, Quellen transparent zusammenstellen, Videos laden, lokal schneiden, Untertitel und Hochformat-Clips erzeugen, Qualität prüfen und auf den verbundenen Kanal veröffentlichen.

## Produktumfang

- **Entdecken:** strikte Zeitraum-, Land-, Sprach-, Format- und Sortierfilter, eingebettete Vorschau und nachvollziehbare Signale
- **Multi-Source-Story:** Leitvideo plus passende Ergänzungen auswählen, der Reihe nach laden und transparent in das Projekt übernehmen
- **Studio:** gemeinsame Bild-/Ton-Zeitleiste, automatische Highlight-Vorschläge, lokaler Sprachschnitt, Reframing, Text-Overlays und bearbeitbare Untertitel
- **Export:** 1080p- und 4K-Rendering, technische Qualitätsprüfung, Thumbnail- und Metadaten-Workflow
- **YouTube:** JSON-geführte Desktop-OAuth-Einrichtung, Kanalauswahl, Upload, Analytics, Kommentare und Monetarisierungsfortschritt
- **Sicherheit:** nicht-destruktiver EditGraph, Wiederherstellung, lokale Verarbeitung ohne stillen Cloud-Fallback und nichtinteraktive Schlüsselbund-Lesezugriffe

Die Bedienoberfläche führt durch die Arbeitsschritte und zeigt Downloads, Quellen, automatische Entscheidungen und den Bearbeitungsverlauf an. Automatische Schnitte bleiben prüfbar und rückgängig machbar.

## Version 1.0.0

Der Produktcode und das lokal installierbare Universal-Paket werden als **Blackstock 1.0.0** gebaut und durch die automatisierten Produkt-, Wiederherstellungs- und Paketprüfungen validiert. Die Änderungen stehen in [docs/1.0_RELEASE_NOTES.md](docs/1.0_RELEASE_NOTES.md).

**VERTRIEBSSTATUS: LOKALES 1.0.0-PAKET VALIDIERT — ÖFFENTLICHE MACOS-FREIGABE AUSSTEHEND**

Für eine öffentliche Weitergabe außerhalb dieses Macs fehlen weiterhin die externen Apple-Nachweise: Developer-ID-Signierung, Notarisierung, Gatekeeper-Prüfung, realer Hardware-Capture-Smoke und ein signiertes Update-Manifest. Blackstock weist diese Punkte absichtlich nicht als bestanden aus. Die verbindlichen Nachweise stehen in [docs/RELEASE_GATES.md](docs/RELEASE_GATES.md) und [docs/MARKET_READINESS.md](docs/MARKET_READINESS.md).
