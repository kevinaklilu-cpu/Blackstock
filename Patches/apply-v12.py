from pathlib import Path
import shutil

ROOT = Path.cwd()
PATCH = ROOT / "Patches" / "V12"

def replace(path, old, new, *, count=-1, required=True):
    p = ROOT / path
    s = p.read_text()
    if required and old not in s:
        raise SystemExit(f"V12 patch pattern missing in {path}: {old[:100]!r}")
    s = s.replace(old, new, count)
    p.write_text(s)

def copy(src, dst):
    target = ROOT / dst
    target.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(PATCH / src, target)

# New V12 modules.
copy("V12Models.swift", "Sources/Blackstock/Models/V12Models.swift")
copy("CreatorIntelligenceV12Service.swift", "Sources/Blackstock/Services/CreatorIntelligenceV12Service.swift")
copy("AppStore+V12.swift", "Sources/Blackstock/AppStore+V12.swift")
copy("CreatorLoopView.swift", "Sources/Blackstock/Views/CreatorLoopView.swift")
copy("V12CoreTests.swift", "Tests/V12CoreTests.swift")
copy("RELEASE_NOTES_v12.md", "RELEASE_NOTES_v12.md")

# Persist V12 alongside V11 without breaking legacy state files.
replace("Sources/Blackstock/Models/Models.swift", "  var v11: V11State?\n", "  var v11: V11State?\n  var v12: V12State?\n")
replace("Sources/Blackstock/Models/Models.swift", "      batchAuftraege, automationsregeln, v11\n", "      batchAuftraege, automationsregeln, v11, v12\n")
replace("Sources/Blackstock/Models/Models.swift", "    v11: V11State? = nil\n", "    v11: V11State? = nil, v12: V12State? = nil\n")
replace("Sources/Blackstock/Models/Models.swift", "    self.v11 = v11\n", "    self.v11 = v11\n    self.v12 = v12\n")
replace("Sources/Blackstock/Models/Models.swift", "    v11 = try c.decodeIfPresent(V11State.self, forKey: .v11)\n", "    v11 = try c.decodeIfPresent(V11State.self, forKey: .v11)\n    v12 = try c.decodeIfPresent(V12State.self, forKey: .v12)\n")

# AppStore V12 state + migration defaults.
replace("Sources/Blackstock/AppStore.swift", "  @Published var v11State: V11State\n", "  @Published var v11State: V11State\n  @Published var v12State: V12State\n")
replace("Sources/Blackstock/AppStore.swift", "    v11State = migriert\n", "    v11State = migriert\n    var creatorState = zustand.v12 ?? V12State()\n    if creatorState.activeChannelID == nil {\n      creatorState.activeChannelID = zustand.kanaele.first(where: { !$0.istDemo && $0.youtubeChannelID != nil })?.id\n    }\n    v12State = creatorState\n")
replace("Sources/Blackstock/AppStore.swift", "      v11: v11State\n", "      v11: v11State,\n      v12: v12State\n")
replace("Sources/Blackstock/AppStore.swift", "      \"blackstock.remoteCacheLimitGB\": 20.0,\n", "      \"blackstock.remoteCacheLimitGB\": 20.0,\n      \"blackstock.creatorMode\": CreatorOperatingMode.copilot.rawValue,\n      \"blackstock.v12MinimumQuality\": 88.0,\n")

# Carry V12 duration decisions into the real remix/render pipeline and enforce V12 quality before auto-upload.
replace("Sources/Blackstock/AppStore+V11.swift", "  func v11ProduktionStartenAusChance(\n    _ chance: Chance, mode: ProductionModeV11 = .automatic\n  ) async -> UUID? {\n    guard let id = v11ProduktionAusChance(chance, mode: mode) else { return nil }\n", "  func v11ProduktionStartenAusChance(\n    _ chance: Chance, mode: ProductionModeV11 = .automatic, targetDurationSeconds: Int? = nil\n  ) async -> UUID? {\n    guard let id = v11ProduktionAusChance(chance, mode: mode) else { return nil }\n    if let targetDurationSeconds, let index = produktionen.firstIndex(where: { $0.id == id }) {\n      produktionen[index].zielDauerSekunden = max(15, targetDurationSeconds)\n    }\n")
replace("Sources/Blackstock/AppStore+V11.swift", "      var timeline = try RemixPlannerService().plan(\n        sources: currentSources,\n        mode: state.mode,\n        requestedFormat: produktionen[pIndex].format)\n", "      var timeline = try RemixPlannerService().plan(\n        sources: currentSources,\n        mode: state.mode,\n        requestedFormat: produktionen[pIndex].format,\n        targetDuration: Double(produktionen[pIndex].zielDauerSekunden))\n")
needle = """      let check = bereitCheck(for: productionID)
      if !check.issues.isEmpty {
        v11PhaseSetzen(productionID, phase: .review, detail: "Bereit-Check: \\(check.issues.count) Problem(e)")
      } else {
        v11PhaseSetzen(productionID, phase: review ? .review : .ready, detail: review ? "Review erforderlich" : "Bereit zum Veröffentlichen")
      }
"""
replace("Sources/Blackstock/AppStore+V11.swift", needle, needle + """      let creatorScore = v12QualityAktualisieren(productionID)
      let creatorStrategy = v12Strategy(for: produktionen[latestIndex].kanalID)
      let creatorReady = creatorScore?.isReady(minimum: creatorStrategy.minimumQualityScore) == true
      if !creatorReady {
        produktionen[latestIndex].status = .qualitaet
        produktionen[latestIndex].naechsterSchritt = "V12 Quality Gate verbessern"
        v11PhaseSetzen(
          productionID, phase: .review,
          detail: "V12 Quality Gate: \\(Int(creatorScore?.overall ?? 0))/100 – Verbesserung vor Upload")
      }
""")
replace("Sources/Blackstock/AppStore+V11.swift", "      if review {\n        meldung = \"Render fertig. Die Produktion wartet auf dein Review.\"\n      } else {\n", "      if review || !creatorReady {\n        meldung = creatorReady\n          ? \"Render fertig. Die Produktion wartet auf dein Review.\"\n          : \"Render fertig. Blackstock V12 hält den Upload zurück, bis das Quality Gate erfüllt ist.\"\n      } else {\n")

# V12 format duration: Short / ~5 minute longform.
replace("Sources/Blackstock/Services/RemixPlannerService.swift", "    mode: ProductionModeV11,\n    requestedFormat: VideoFormat\n  ) throws -> RemixTimeline {", "    mode: ProductionModeV11,\n    requestedFormat: VideoFormat,\n    targetDuration: Double? = nil\n  ) throws -> RemixTimeline {")
replace("Sources/Blackstock/Services/RemixPlannerService.swift", """    let targetDuration: Double
    switch format {
    case .short: targetDuration = 55
    case .longform: targetDuration = 8 * 60
    case .serie: targetDuration = 4 * 60
    case .livestream: targetDuration = usable.compactMap(\\.duration).reduce(0, +)
    }
""", """    let resolvedTargetDuration: Double
    switch format {
    case .short: resolvedTargetDuration = targetDuration ?? 42
    case .longform: resolvedTargetDuration = targetDuration ?? 5 * 60
    case .serie: resolvedTargetDuration = targetDuration ?? 5 * 60
    case .livestream: resolvedTargetDuration = usable.compactMap(\\.duration).reduce(0, +)
    }
""")
replace("Sources/Blackstock/Services/RemixPlannerService.swift", "guard duration < targetDuration else { break }", "guard duration < resolvedTargetDuration else { break }")
replace("Sources/Blackstock/Services/RemixPlannerService.swift", "let remaining = targetDuration - duration", "let remaining = resolvedTargetDuration - duration")

# V12 is the default home surface.
replace("Sources/Blackstock/Views/RootView.swift", "    case .command: CommandView()", "    case .command: CreatorLoopView()")
replace("Sources/Blackstock/Views/SidebarView.swift", 'Text("BLACKSTOCK")', 'Text("BLACKSTOCK 12")')

# Release identity.
(ROOT / "Build/version.env").write_text("APP_VERSION=12.0.0\nBUILD_NUMBER=1200\nMIN_MACOS=13.0\nBUNDLE_ID=de.blackstock.native\n")
replace("Sources/Blackstock/ReleaseInfo.swift", '"11.1.0"', '"12.0.0"')
replace("Sources/Blackstock/ReleaseInfo.swift", '"1110"', '"1200"')

# Xcode 26 lipo syntax.
replace("Build/build-app.zsh", 'lipo -verify_arch arm64 x86_64 "$MACOS/Blackstock"', 'lipo "$MACOS/Blackstock" -verify_arch arm64 x86_64', required=False)

# Release gates know about V12.
replace("Build/Release-Audit.sh", '[[ "$APP_VERSION" == "11.1.0" ]]', '[[ "$APP_VERSION" == "12.0.0" ]]')
replace("Build/Release-Audit.sh", '[[ "$BUILD_NUMBER" == "1110" ]]', '[[ "$BUILD_NUMBER" == "1200" ]]')
replace("Build/Release-Audit.sh", 'RELEASE_NOTES_v11.md', 'RELEASE_NOTES_v12.md')
replace("Build/Release-Audit.sh", 'MODELS=("$ROOT/Sources/Blackstock/Models/Models.swift" "$ROOT/Sources/Blackstock/Models/V11Models.swift")', 'MODELS=("$ROOT/Sources/Blackstock/Models/Models.swift" "$ROOT/Sources/Blackstock/Models/V11Models.swift" "$ROOT/Sources/Blackstock/Models/V12Models.swift")')
replace("Build/Release-Audit.sh", '  "$ROOT/Sources/Blackstock/Services/FinalMetadataService.swift" \\\n  "$ROOT/Sources/Blackstock/Services/RemoteMediaCacheService.swift"', '  "$ROOT/Sources/Blackstock/Services/FinalMetadataService.swift" \\\n  "$ROOT/Sources/Blackstock/Services/CreatorIntelligenceV12Service.swift" \\\n  "$ROOT/Sources/Blackstock/Services/RemoteMediaCacheService.swift"')

replace("Build/Core-Tests.sh", 'MODELS=("$ROOT/Sources/Blackstock/Models/Models.swift" "$ROOT/Sources/Blackstock/Models/V11Models.swift")', 'MODELS=("$ROOT/Sources/Blackstock/Models/Models.swift" "$ROOT/Sources/Blackstock/Models/V11Models.swift" "$ROOT/Sources/Blackstock/Models/V12Models.swift")')
needle_test = 'run_test v11-release "$ROOT/Sources/Blackstock/Services/SourceConnectorService.swift" "$ROOT/Sources/Blackstock/Services/ClipAnalysisService.swift" "$ROOT/Sources/Blackstock/Services/RemixPlannerService.swift" "$ROOT/Sources/Blackstock/Services/FinalMetadataService.swift" "$ROOT/Tests/V11ReleaseTests.swift"\n'
replace("Build/Core-Tests.sh", needle_test, needle_test + 'run_test v12-core "$ROOT/Sources/Blackstock/Services/SourceConnectorService.swift" "$ROOT/Sources/Blackstock/Services/ClipAnalysisService.swift" "$ROOT/Sources/Blackstock/Services/RemixPlannerService.swift" "$ROOT/Sources/Blackstock/Services/CreatorIntelligenceV12Service.swift" "$ROOT/Tests/V12CoreTests.swift"\n')
replace("Build/Core-Tests.sh", '"$ROOT/Sources/Blackstock/Services/FinalMetadataService.swift" "$ROOT/Sources/Blackstock/Services/RemoteMediaCacheService.swift"', '"$ROOT/Sources/Blackstock/Services/FinalMetadataService.swift" "$ROOT/Sources/Blackstock/Services/CreatorIntelligenceV12Service.swift" "$ROOT/Sources/Blackstock/Services/RemoteMediaCacheService.swift"')

(ROOT / "RELEASE_MANIFEST.txt").write_text(
    "Blackstock 12.0.0 (Build 1200)\nBundle: de.blackstock.native\nMinimum macOS: 13.0\n"
    "Creator Loop: Channel DNA -> Trend Intelligence -> Source Analysis -> Format Decision -> Remix -> Quality -> Render -> Upload -> Learning\n"
)
print("BLACKSTOCK_V12_PATCH_APPLIED")
