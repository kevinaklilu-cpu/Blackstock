#!/usr/bin/env python3
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]

requirements = {
    "Sources/BlackstockCore/LocalLoudnessAnalyzer.swift": [
        "AudioLoudnessSnapshot",
        "integratedLUFS",
        "maximumMomentaryLUFS",
        "maximumShortTermLUFS",
        "truePeakDBTP",
        "BS1770LoudnessMeter",
        "1.53512485958697",
        "-1.99004745483398",
        "momentaryFrames = 19_200",
        "shortTermFrames = 144_000",
        "stepFrames = 4_800",
        "return level > -70",
        "$0 - 10",
        "truePeakPhases",
        "0.9721679687500",
    ],
    "Tests/BlackstockCoreTests/LocalLoudnessAnalyzerTests.swift": [
        "testFullScale997HzMonoReferenceIsMinusThreePointZeroOneLUFS",
        "testDualChannelReferenceAddsAboutThreeLU",
        "testSilenceProducesNoInventedIntegratedLoudness",
        "testTruePeakFindsInterSamplePeakAboveSamplePeak",
        "testUnsupportedMultichannelLayoutHardStops",
    ],
    "Sources/BlackstockApp/StudioState.swift": [
        "audioLoudnessAssessment",
        "LocalLoudnessAnalyzer()",
        "audioQCURL = artifact.fileURL",
        "audioQCURL = asset.sourceURL",
    ],
    "Sources/BlackstockCore/DeterministicQualityEvidenceBuilder.swift": [
        "audioLoudnessAssessment",
        "Blackstock ITU-R BS.1770 Loudness Meter",
        "Professionelle Loudness-Messung fehlt",
        "Audio des finalen Renders professionell gemessen",
        "True Peak über 0 dBTP",
    ],
    "Sources/BlackstockApp/PackagingReviewView.swift": [
        "Professionelle Loudness-Messung",
        "Integrated:",
        "True Peak:",
        "ITU-R BS.1770",
    ],
    "Tests/BlackstockCoreTests/DeterministicQualityEvidenceBuilderTests.swift": [
        "testFinalRenderAudioMeasurementsProvideGroundedAudioCoverage",
        "testPeakAndRMSWithoutProfessionalLoudnessRemainBlocked",
    ],
}

errors = []
for relative, markers in requirements.items():
    path = ROOT / relative
    if not path.is_file():
        errors.append(f"missing audio contract file: {relative}")
        continue
    text = path.read_text(encoding="utf-8")
    for marker in markers:
        if marker not in text:
            errors.append(
                f"{relative}: missing professional audio marker: {marker}"
            )

legacy = ROOT / "Sources/BlackstockCore/LocalAudioSignalAnalyzer.swift"
if legacy.is_file():
    text = legacy.read_text(encoding="utf-8")
    if "LUFS" in text or "dBTP" in text:
        errors.append(
            "LocalAudioSignalAnalyzer must not relabel sample Peak/RMS as LUFS or dBTP"
        )

if errors:
    print("Professional audio audit failed:", file=sys.stderr)
    for error in errors:
        print(f"- {error}", file=sys.stderr)
    sys.exit(1)

print(
    "Professional audio audit passed: final-render PCM, BS.1770 integrated "
    "loudness, momentary/short-term loudness and true peak remain distinct "
    "and release-gated."
)
