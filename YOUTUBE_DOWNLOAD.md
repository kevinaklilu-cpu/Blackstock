# YouTube → Schnitt → Veröffentlichung

„Video schneiden“ in Entdecken erstellt ein Clip-Projekt. Wenn noch keine lokale
Quelle vorhanden ist, startet Blackstock den Download des ausgewählten Videos.
Der Download-Dialog zeigt Fortschritt, Ziel und Fehler und bietet Pause,
Fortsetzen und Abbruch. Blackstock lädt H.264 bis 1080p und AAC separat,
verbindet sie mit AVFoundation und übergibt erst die fertige MP4 an den Import.
Der bisherige Schnitt-Player und die automatische Highlight-Analyse übernehmen.
Untertitel, Thumbnail, Render-Review und der bestehende YouTube-Upload folgen
im Projekt. Ein Upload erfordert den verbundenen Kanal und die Freigabe im
Veröffentlichungsdialog.

Die einmalige Nutzungserklärung des Arbeitsbereichs bleibt erhalten.
Browser-Cookies werden nicht gelesen; private, gesperrte oder nicht verfügbare
Videos werden als Fehler angezeigt. Downloadfehler sind wiederholbar. Eine
laufende Übertragung wird beim Projektwechsel abgebrochen, damit ihre Datei
nicht im falschen Projekt landet. Teil-Dateien liegen außerhalb des beobachteten
Imports. Bei Unterbrechung bleiben sie erhalten. Beim erneuten Öffnen desselben
Projekts verwendet Blackstock die Teildateien für dieselbe Quell-URL weiter;
ein anderes Video erhält einen getrennten Zwischenstand. Jede Wiederaufnahme
arbeitet mit einer neuen Kopie, damit ein nach einem Absturz noch laufender
Downloadprozess keine aktuellen Dateien verändert. Nach erfolgreicher
Verarbeitung werden die Zwischenstände dieser Quelle gelöscht.

## Build und Test

`Build/package.sh` integriert prüfsummengesicherte yt-dlp- und Deno-Helfer für
Apple Silicon und Intel. Versionen und Hashes stehen in
`Build/prepare_download_tools.py`. Der erste Build benötigt Internetzugriff.
Für einen Entwicklungsstart kann `BLACKSTOCK_DOWNLOAD_TOOLS_DIR` auf
`.build/download-tools` gesetzt werden. Installierte Homebrew-Helfer werden
alternativ erkannt.

`Build/test_youtube_download.sh` testet mit dem öffentlichen Big-Buck-Bunny-Video
den tatsächlichen Download, Abbruch/Neustart, Pause/Fortsetzen, MP4-Ausgabe,
Bild-/Tonspuren und deren Dauer sowie Wiederaufnahme mit einer neuen Download-Instanz.
`Build/test_download_recovery.sh` prüft ohne Netzwerk den Erhalt der Teildateien
und die Trennung unterschiedlicher Quellen. Der Test braucht Netzwerkzugriff und etwa
260 MB für die fertige Testdatei. `swift test` führt zusätzlich die Unit-Tests
aus und benötigt eine Xcode-Installation mit XCTest.

Das lokal gebaute Paket ist ein Entwicklungsbuild. Ein veröffentlichbarer
Release benötigt weiterhin die vorhandene Developer-ID-/Notarisierungspipeline.
Ein echter Kanal-Upload wird durch den Download-Test nicht ausgeführt.

## Regressionen aus dem lokalen Nutzungstest

Der Ingest-Wächter liefert Ereignisse und Abbruch-Rückrufe auf dem MainActor.
Ein Generationstoken verwirft alte Ereignisse nach einem Neustart des Wächters.
Damit kann das Anlegen des Download-Arbeitsordners keinen Actor-Absturz auslösen.
`Build/test_local_interaction.sh` prüft Ereignisse, Abbruch und Neustart mit
aktivierten Actor-Prüfungen. Der Live-Downloadtest verwendet ebenfalls den Wächter.

Schlüsselbundzugriffe unterdrücken optionale Authentifizierungsdialoge sowohl
für Data-Protection- als auch für ältere Login-Keychain-Einträge. Das gilt für
Lesen, Aktualisieren, Anlegen und Löschen. Die prozesslokale Einstellung wird
nach jedem Zugriff wiederhergestellt; Keychain-Berechtigungen bleiben bestehen.
Gesperrte oder nicht freigegebene Einträge liefern einen Fehler statt einer
Kette von Passwortfenstern. Ein gesperrter Schlüsselbund muss in macOS entsperrt
werden; das Programm kann fehlende Zugriffsrechte nicht selbst erteilen.

Verweigerte Lesezugriffe werden pro Eintrag bis zur ausdrücklichen erneuten
Prüfung angehalten. Ein einzelner Hinweis in der App ersetzt wiederholte
Zugriffsversuche; der Schalter lädt anschließend auch die Kanalidentität neu.
