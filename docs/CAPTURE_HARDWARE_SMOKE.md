# Capture Hardware Smoke

Dieser Test ist der letzte externe Nachweis für den Release-Gate **Capture**. Er muss auf einem physischen, unterstützten Mac mit realer Kamera, realem Mikrofon und erteilter Bildschirmaufnahme-Berechtigung ausgeführt werden. Headless-CI oder synthetische Geräte zählen nicht als Hardware-Evidenz.

## Voraussetzungen

- Blackstock aus dem zu prüfenden Installer installieren.
- macOS-Version und Mac-Modell dokumentieren.
- Kamera und Mikrofon physisch verfügbar.
- Bildschirmaufnahme-Berechtigung kann in macOS erteilt werden.
- Keine vorhandenen Blackstock-Capture-Dateien als Testresultat wiederverwenden.
- Ein lokales Testprojekt mit bestätigter Rechtefreigabe verwenden.

## Pflichtpfade

### 1. Kamera

1. In Blackstock **Kamera** auswählen.
2. Berechtigung erteilen, falls noch nicht erfolgt.
3. Aufnahme starten und mindestens 5 Sekunden reale Bewegung aufnehmen.
4. Aufnahme stoppen.
5. Rechtebestätigung abschließen.
6. Prüfen:
   - Datei wurde neu erzeugt.
   - Videospur ist vorhanden und Dauer > 0.
   - Falls Mikrofon freigegeben war, ist eine Audiospur vorhanden.
   - Aufnahme wurde in den Projekt-Workspace übernommen.
   - temporäre Capture-Datei wurde nach erfolgreicher Übernahme bereinigt.

### 2. Mikrofon

1. **Mikrofon** auswählen.
2. Mindestens 5 Sekunden hörbare Sprache aufnehmen.
3. Aufnahme stoppen und Rechtebestätigung abschließen.
4. Prüfen:
   - neue M4A/AAC-Datei wurde erzeugt.
   - Dauer > 0.
   - Audiospur enthält dekodierbare Samples.
   - Datei ist als Supplemental Capture dem aktuellen Projekt zugeordnet.
   - Persistenz über App-Neustart bleibt erhalten.

### 3. Bildschirm

1. **Bildschirm** auswählen.
2. Bildschirmaufnahme-Berechtigung erteilen.
3. Mindestens 5 Sekunden sichtbare UI-Bewegung aufnehmen.
4. Aufnahme stoppen und Rechtebestätigung abschließen.
5. Prüfen:
   - neue Videodatei wurde erzeugt.
   - Videospur ist vorhanden und Dauer > 0.
   - Aufnahme gehört zum aktuellen Projekt.
   - Blackstock selbst wird entsprechend der implementierten Filterregel nicht unbeabsichtigt als fremde Quelle behandelt.

### 4. Systemaudio

1. Während der Bildschirmaufnahme eine klar erkennbare lokale Audioquelle abspielen.
2. Aufnahme mindestens 5 Sekunden weiterlaufen lassen.
3. Aufnahme stoppen.
4. Prüfen:
   - resultierende Bildschirmaufnahme besitzt eine Audiospur.
   - dekodierbare Samples > 0.
   - Audio ist hörbar und stammt aus der Systemaudio-Aufnahme, nicht aus einer nachträglich eingefügten Testdatei.

## Fehlerfälle

Mindestens einmal pro Berechtigungsart muss ein verweigerter bzw. nicht erteilter Zugriff geprüft werden. Blackstock darf dann keine erfolgreiche Aufnahme behaupten und keine leere Datei als valides Capture in den Workspace übernehmen.

Ein Abbruch während einer laufenden Aufnahme muss temporäre Dateien bereinigen oder einen klar wiederaufnehmbaren Fehlerzustand hinterlassen. Stille Datenverluste zählen als FAIL.

## Evidenzdatei

Blackstock erzeugt und aktualisiert die Hardware-Evidenz automatisch während der echten App-Nutzung unter:

`~/Library/Application Support/Blackstock/Diagnostics/capture-hardware-smoke.json`

Die Einstellungen zeigen für jeden der vier kanonischen Pfade den aktuellen technischen Nachweis und können die Datei im Finder öffnen. Ein lokaler Entwicklungsstart zählt nicht als Installer-Nachweis; `installedFromPackage` wird nur für `/Applications/Blackstock.app` gesetzt.

Nach dem vollständigen Test wird dieselbe Datei auf demselben Mac validiert:

```bash
python3 Build/validate_capture_hardware_smoke.py \
  "$HOME/Library/Application Support/Blackstock/Diagnostics/capture-hardware-smoke.json"
```

Der Validator prüft zusätzlich, dass die projektgebundenen Capture-Dateien noch existieren, Screen und Systemaudio aus derselben ScreenCaptureKit-Datei stammen und der Restart-Nachweis aus einer anderen App-Launch-ID als die Aufnahmen stammt.

Pflichtfelder:

- `schemaVersion`: aktuell `1`
- `testedAt`: ISO-8601
- `blackstockVersion`
- `blackstockBuild`
- `macOSVersion`
- `hardwareModel`
- `installedFromPackage`: `true`
- `camera`, `microphone`, `screen`, `systemAudio`
  - `permissionGranted`
  - `recordingCreated`
  - `durationSeconds`
  - `persistedToProject`
  - `decodedSamples` für Mikrofon/Systemaudio
  - `videoTrackPresent` für Kamera/Bildschirm
- `deniedPermissionHardStopPassed`
- `temporaryCleanupPassed`
- `appRestartPersistencePassed`
- `restartVerifiedLaunchID`
- `deniedPermissionKinds`: alle vier kanonischen Capture-Arten
- `temporaryCleanupKinds`: alle vier kanonischen Capture-Arten

Jeder Pfad enthält zusätzlich die projektgebundene `projectID`, die `recordedLaunchID` und den `persistedFilePath`. Diese Felder werden von Blackstock selbst geschrieben; die persistierte Datei muss beim finalen Validatorlauf noch vorhanden sein.

Jeder Pflichtpfad muss PASS sein. Ein fehlendes Feld, Dauer <= 0, fehlende reale Spur oder fehlende Projektbindung führt zum FAIL.

## Gate-Regel

**Capture darf erst auf PASS gesetzt werden, wenn eine validierte Evidenzdatei aus einem physischen Mac-Test vorliegt.** Code-Audits und CI bleiben zusätzliche Regression-Sicherungen, ersetzen diesen Hardware-Nachweis aber nicht.
