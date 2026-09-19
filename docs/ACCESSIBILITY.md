# Blackstock Accessibility Contract

Stand: 2026-09-19

Blackstock behandelt Accessibility als Release-Gate und nicht als nachträgliche UI-Politur.

## VoiceOver / Semantik

Kritische First-Run-, Studio- und Publishing-Kontrollen besitzen explizite Accessibility-Labels und bei dynamischen Reglern Accessibility-Werte. Icon-only Buttons und Controls mit ausgeblendeten sichtbaren Labels müssen eine explizite semantische Bezeichnung besitzen.

## Keyboard und Focus

Die Command Palette ist global per ⌘K erreichbar. Ihr Suchfeld erhält beim Öffnen deterministisch den Tastaturfokus und kann mit Escape geschlossen werden. Die übrigen kritischen Kontrollen verwenden native SwiftUI-Buttons, Listen, Textfelder, Picker und Slider, damit die macOS-Tastaturnavigation und Focus-Engine erhalten bleiben.

## Reduced Motion

Die kritischen Produktflächen verwenden keine eigenen Custom-Animationsabläufe. Dadurch wird keine zusätzliche App-Bewegung erzwungen, die der Systemeinstellung „Bewegung reduzieren“ entgegenwirken könnte. Der CI-Audit blockiert neue Custom-Animationen auf diesen Flächen, bis sie explizit an die Reduced-Motion-Systemeinstellung gebunden werden.

## Contrast

Kritische Flächen verwenden semantische Systemfarben und foregroundStyle statt fest codierter RGB-Farben. Dadurch bleiben Systemkontrast und Darstellungseinstellungen wirksam. Der CI-Audit blockiert feste RGB-Farben in diesen Flächen.

## Text Scaling

Kritische Flächen verwenden semantische SwiftUI-Fontstile wie largeTitle, title, headline, body, caption und caption2. Feste Punktgrößen sind dort verboten und werden durch den CI-Audit blockiert.

## CI-Evidenz

Build/audit_accessibility.py prüft explizite Semantik, icon-only/labelsHidden-Verträge, deterministischen Command-Palette-Focus und Tastaturpfad, keine festen Punktgrößen, keine ungebundenen Custom-Animationen und keine festen RGB-Farben auf kritischen Flächen. Zusätzlich läuft swift test in derselben Canonical-CI.