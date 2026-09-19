# Professionelle Audio-QC

Blackstock trennt technische PCM-Fakten von professioneller Loudness-Messung und von der weiterhin nötigen hörbaren Qualitätsprüfung.

## Messpfad

Der finale Render wird lokal dekodiert und für den professionellen Meter auf 48 kHz Float-PCM analysiert. Der Messpfad implementiert die für Mono/Stereo relevanten Regeln aus **ITU-R BS.1770-5 (11/2023)**:

- zweistufiges K-Weighting mit den offiziellen 48-kHz-Koeffizienten,
- 400-ms-Gating-Blöcke mit 75 % Überlappung,
- absolutes Gate bei -70 LKFS,
- relatives Gate 10 LU unter dem absolut gegateten Zwischenwert,
- Integrated Loudness,
- Maximum Momentary Loudness (400 ms),
- Maximum Short-term Loudness (3 s),
- True Peak über 4× Oversampling und den in Annex 2 angegebenen vierphasigen FIR-Interpolationsfilter.

Der 0-dBFS-997-Hz-Referenztest muss ungefähr -3,01 LUFS ergeben. Ein separater Inter-Sample-Test stellt sicher, dass True Peak höher als der reine Sample-Peak erkannt werden kann.

## Release-Vertrag

Peak/RMS und Full-Scale-Sample-Zählung bleiben zusätzliche technische Fakten und werden niemals als LUFS oder dBTP bezeichnet.

Wenn der finale Render eine Audiospur besitzt, aber die PCM-Analyse oder die professionelle Integrated-LUFS-/True-Peak-Messung fehlt, entsteht ein Release-Blocker. Eine manuelle Prüfnotiz kann diesen technischen Nachweis nicht ersetzen.

Die hörbare Prüfung bleibt zusätzlich erforderlich, insbesondere für Sprachverständlichkeit, Störgeräusche, ungewollte Pegelsprünge und wahrnehmbare Verzerrungen.

## Grenzen

Der aktuelle professionelle Meter unterstützt Mono und Stereo. Andere Kanalzahlen werden nicht still heruntergemischt oder geschätzt, sondern führen zu einem expliziten Hard-Stop.

EBU R128 wird als professioneller Referenzrahmen für Loudness-Normalisierung herangezogen. Blackstock leitet daraus **keinen erfundenen YouTube-Zielwert** ab; gemessene LUFS-/dBTP-Werte werden als Fakten angezeigt.
