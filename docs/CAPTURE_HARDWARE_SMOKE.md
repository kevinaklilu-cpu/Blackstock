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

Die Einstellungen zeigen für jeden der vier kanonischen Pfade den aktuellen technischen Nachweis und können die Datei im Finder öffnen. Ändern sich Build, Source-Commit, macOS-Version, Hardwaremodell, Installationspfad oder Developer-ID-Signatur, wird vorhandene Capture-Evidenz nicht weiterverwendet. Ein lokaler Entwicklungsstart oder bloßes Kopieren der App nach `/Applications` zählt nicht als Installer-Nachweis; `installedFromPackage` wird nur gesetzt, wenn `/Applications/Blackstock.app` läuft **und** der macOS-Package-Receipt `de.blackstock.app` existiert, zur laufenden Version passt sowie Installation auf `/` ausweist. Zusätzlich liest Blackstock die tatsächliche Codesign-Identität der laufenden App aus: `developerIDApplicationVerified` wird nur gesetzt, wenn `codesign` eine `Developer ID Application`-Signatur mit exakt der im Produktionsbuild eingebetteten Apple-Team-ID meldet. Diese Team-ID wird als `applicationTeamID` gespeichert. Die Evidenz bindet außerdem `BlackstockSourceCommitSHA` aus dem installierten App-Bundle ein; ältere Evidence-Schemata ohne vollständige Produktions-App-Provenienz werden bewusst nicht hochgestuft, sondern müssen neu aufgenommen werden.

Nach dem vollständigen Test wird dieselbe Datei auf demselben Mac validiert:

```bash
python3 Build/validate_capture_hardware_smoke.py \
  "$HOME/Library/Application Support/Blackstock/Diagnostics/capture-hardware-smoke.json"
```

Der Validator prüft zusätzlich, dass die projektgebundenen Capture-Dateien noch existieren, Screen und Systemaudio aus derselben ScreenCaptureKit-Datei stammen, der Restart-Nachweis aus einer anderen App-Launch-ID als die Aufnahmen stammt und die Evidence eine bestätigte Developer-ID-Application-Team-ID enthält. Der finale Market-Readiness-Verifier verlangt anschließend dieselbe Apple-Team-ID in Capture-, Produktionsrelease- und Updater-Evidenz.

Pflichtfelder:

- `schemaVersion`: aktuell `5`
- `testedAt`: ISO-8601
- `blackstockVersion`
- `blackstockBuild`
- `blackstockSourceCommitSHA`: exakt 40 hexadezimale Git-SHA-Zeichen
- `macOSVersion`
- `hardwareModel`
- `installedFromPackage`: `true`
- `installerReceiptPackageID`: exakt `de.blackstock.app`
- `installerReceiptVersion`: exakt dieselbe Version wie `blackstockVersion`
- `installerReceiptVerified`: `true`; Blackstock liest dafür den echten macOS-Package-Receipt über `pkgutil --pkg-info-plist`
- `applicationTeamID`: tatsächliche Apple-Team-ID der laufenden Developer-ID-App
- `developerIDApplicationVerified`: `true`
- `applicationExecutableSHA256`: SHA-256 des tatsächlich laufenden Blackstock-Executables
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

Jeder Pfad enthält zusätzlich die projektgebundene `projectID`, die `recordedLaunchID`, den `persistedFilePath` und `persistedFileSHA256`. Diese Felder werden von Blackstock selbst geschrieben. Die persistierte Datei muss beim finalen Validatorlauf noch vorhanden sein und ihr SHA-256 muss weiterhin exakt dem bei der technischen Capture-Prüfung erfassten Fingerabdruck entsprechen.

Jeder Pflichtpfad muss PASS sein. Ein fehlendes Feld, Dauer <= 0, fehlende reale Spur oder fehlende Projektbindung führt zum FAIL.

## Gate-Regel

**Capture darf erst auf PASS gesetzt werden, wenn eine validierte Evidenzdatei aus einem physischen Mac-Test vorliegt.** Code-Audits und CI bleiben zusätzliche Regression-Sicherungen, ersetzen diesen Hardware-Nachweis aber nicht.
