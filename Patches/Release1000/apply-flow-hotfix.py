from pathlib import Path

repo = Path.cwd()
view = repo / 'Sources/Blackstock/Views/CreatorOS1000View.swift'
store = repo / 'Sources/Blackstock/AppStore+V1000.swift'


def replace_once(path: Path, old: str, new: str):
    text = path.read_text()
    if new in text:
        return
    if old not in text:
        raise SystemExit(f'Expected block not found in {path}: {old[:100]!r}')
    path.write_text(text.replace(old, new, 1))

replace_once(view, 'import SwiftUI\n', 'import SwiftUI\nimport UniformTypeIdentifiers\n')
replace_once(
    view,
    '  @State private var runningAutopilot = false\n',
    '  @State private var runningAutopilot = false\n  @State private var sourceMission: CreatorMission1000?\n  @State private var localSourceImporter = false\n  @State private var importingLocalSource = false\n')
replace_once(
    view,
    '    .onChange(of: selectedChannelID) { newValue in\n      store.v12ActiveChannelID = newValue\n    }\n',
    '''    .onChange(of: selectedChannelID) { newValue in\n      store.v12ActiveChannelID = newValue\n    }\n    .fileImporter(\n      isPresented: $localSourceImporter,\n      allowedContentTypes: [.movie],\n      allowsMultipleSelection: false\n    ) { result in\n      importLicensedSource(result)\n    }\n''')
replace_once(
    view,
    '''        if let mission = snapshot.bestMission {\n          Button {\n            run(mission)\n          } label: {\n            if runningMissionID == mission.id { ProgressView().controlSize(.small) }\n            else { Label("Bestes Video produzieren", systemImage: "bolt.fill") }\n          }\n          .buttonStyle(.borderedProminent).tint(Color.bsRed).foregroundStyle(.white)\n          .disabled(runningMissionID != nil || runningAutopilot)\n        }\n''',
    '''        if let mission = snapshot.bestMission {\n          Button {\n            run(mission)\n          } label: {\n            if runningMissionID == mission.id && !importingLocalSource { ProgressView().controlSize(.small) }\n            else { Label("Bestes Video produzieren", systemImage: "bolt.fill") }\n          }\n          .buttonStyle(.borderedProminent).tint(Color.bsRed).foregroundStyle(.white)\n          .disabled(runningMissionID != nil || runningAutopilot || importingLocalSource)\n\n          Button {\n            chooseLicensedSource(for: mission)\n          } label: {\n            if runningMissionID == mission.id && importingLocalSource { ProgressView().controlSize(.small) }\n            else { Label(sourceActionLabel(for: mission), systemImage: "scissors") }\n          }\n          .buttonStyle(.bordered)\n          .disabled(runningMissionID != nil || runningAutopilot || importingLocalSource)\n        }\n''')
replace_once(
    view,
    '''            Button("Produzieren") { run(mission) }\n              .buttonStyle(.borderedProminent).tint(Color.bsRed).foregroundStyle(.white).controlSize(.small)\n              .disabled(runningMissionID != nil || runningAutopilot)\n''',
    '''            Button("Produzieren") { run(mission) }\n              .buttonStyle(.borderedProminent).tint(Color.bsRed).foregroundStyle(.white).controlSize(.small)\n              .disabled(runningMissionID != nil || runningAutopilot || importingLocalSource)\n            Button { chooseLicensedSource(for: mission) } label: {\n              Label(sourceActionLabel(for: mission), systemImage: "scissors")\n            }\n            .buttonStyle(.bordered).controlSize(.small)\n            .disabled(runningMissionID != nil || runningAutopilot || importingLocalSource)\n''')
replace_once(
    view,
    '''  private func run(_ mission: CreatorMission1000) {\n    guard let channelID = selectedChannelID,\n          let chance = store.chancen.first(where: { $0.id == mission.chanceID }) else { return }\n    runningMissionID = mission.id\n    Task {\n      _ = await store.v1000ProduktionStarten(chance: chance, channelID: channelID)\n      runningMissionID = nil\n    }\n  }\n}\n''',
    '''  private func run(_ mission: CreatorMission1000) {\n    guard let channelID = selectedChannelID,\n          let chance = store.chancen.first(where: { $0.id == mission.chanceID }) else { return }\n    runningMissionID = mission.id\n    Task {\n      _ = await store.v1000ProduktionStarten(chance: chance, channelID: channelID)\n      runningMissionID = nil\n    }\n  }\n\n  private func sourceActionLabel(for mission: CreatorMission1000) -> String {\n    guard let channelID = selectedChannelID,\n          let chance = store.chancen.first(where: { $0.id == mission.chanceID }) else { return "Eigene Quelle" }\n    let recommendation = store.v26Recommendation(for: chance, channelID: channelID)\n    return recommendation.mode == .singleSource ? "Clip mit Datei" : "Remix mit Datei"\n  }\n\n  private func chooseLicensedSource(for mission: CreatorMission1000) {\n    sourceMission = mission\n    localSourceImporter = true\n  }\n\n  private func importLicensedSource(_ result: Result<[URL], Error>) {\n    switch result {\n    case .success(let urls):\n      guard let sourceURL = urls.first,\n            let mission = sourceMission,\n            let channelID = selectedChannelID,\n            let chance = store.chancen.first(where: { $0.id == mission.chanceID })\n      else {\n        sourceMission = nil\n        return\n      }\n      importingLocalSource = true\n      runningMissionID = mission.id\n      Task {\n        _ = await store.v1000ProduktionMitQuelleStarten(\n          chance: chance, channelID: channelID, sourceURL: sourceURL)\n        importingLocalSource = false\n        runningMissionID = nil\n        sourceMission = nil\n      }\n    case .failure(let error):\n      sourceMission = nil\n      store.meldung = error.localizedDescription\n    }\n  }\n}\n''')

insert_before = '''  func v1000AutopilotRun(channelID: UUID, maximum: Int = 3) async {\n'''
new_func = '''  @discardableResult\n  func v1000ProduktionMitQuelleStarten(\n    chance: Chance,\n    channelID: UUID,\n    sourceURL: URL\n  ) async -> UUID? {\n    if let existing = produktionen.first(where: { $0.chanceID == chance.id && $0.kanalID == channelID }) {\n      ausgewaehlteProduktionID = existing.id\n      ausgewaehltesZiel = .produktionen\n      meldung = "Diese Chance existiert bereits als Produktion. Blackstock öffnet das vorhandene Projekt."\n      return existing.id\n    }\n\n    let recommendation = v26Recommendation(for: chance, channelID: channelID)\n    let mission = CreatorOS1000Service.shared.mission(\n      chance: chance,\n      decision: recommendation.decision,\n      hasUsableSource: true,\n      preferredEditMode: recommendation.mode)\n\n    guard let id = await v26ProduktionStarten(\n      chance: chance,\n      channelID: channelID,\n      forcedMode: recommendation.mode,\n      forcedFormat: mission.format)\n    else { return nil }\n\n    do {\n      _ = try await v26LokaleSchnittquelleHinzufuegen(zu: id, datei: sourceURL)\n    } catch {\n      meldung = error.localizedDescription\n      ausgewaehlteProduktionID = id\n      ausgewaehltesZiel = .produktionen\n      return id\n    }\n\n    if let index = produktionen.firstIndex(where: { $0.id == id }) {\n      produktionen[index].zielDauerSekunden = mission.targetDurationSeconds\n      produktionen[index].hook = mission.hookAngle\n      produktionen[index].captionsAktiv = true\n      produktionen[index].watermarkAktiv = true\n      produktionen[index].naechsterSchritt = "\(mission.executionPath.rawValue) · Quelle analysieren und Master bauen"\n      produktionen[index].aktualisiertAm = Date()\n    }\n    speichern()\n\n    await v48ProduktionFortsetzen(id)\n    ausgewaehlteProduktionID = id\n    ausgewaehltesZiel = .produktionen\n    return id\n  }\n\n'''
text = store.read_text()
if 'func v1000ProduktionMitQuelleStarten(' not in text:
    if insert_before not in text:
        raise SystemExit('Autopilot insertion point missing')
    store.write_text(text.replace(insert_before, new_func + insert_before, 1))

print('BLACKSTOCK_1000_FLOW_HOTFIX_OK')
