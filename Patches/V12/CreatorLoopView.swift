import SwiftUI

struct CreatorLoopView: View {
  @EnvironmentObject private var store: AppStore
  @State private var strategyDraft: ChannelStrategyV12?

  private var selectedChannelID: UUID? {
    store.v12ActiveChannelID ?? store.liveKanaele.first?.id
  }

  private var selectedChannel: Kanal? {
    selectedChannelID.flatMap { store.kanal(fuer: $0) }
  }

  private var health: GoogleConnectionHealthV12 {
    store.v12GoogleHealth(channelID: selectedChannelID)
  }

  private var decisions: [TrendDecisionV12] {
    guard let selectedChannelID else { return [] }
    return Array(store.v12RankedDecisions(channelID: selectedChannelID).prefix(12))
  }

  private var productions: [Produktion] {
    guard let selectedChannelID else { return [] }
    return store.produktionen.filter { $0.kanalID == selectedChannelID }.sorted {
      ($0.aktualisiertAm ?? $0.erstelltAm) > ($1.aktualisiertAm ?? $1.erstelltAm)
    }
  }

  private var insights: [LearningInsightV12] {
    guard let selectedChannelID else { return [] }
    return Array(store.v12Insights(channelID: selectedChannelID).prefix(5))
  }

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 18) {
        PageHeader(
          titel: "Creator Loop · V12",
          untertitel: "Channel DNA → Trend Intelligence → Remix → Quality Gate → Upload → Performance Learning",
          trailing: AnyView(channelPicker))

        loopRail

        if selectedChannel == nil {
          EmptyState(
            symbol: "person.crop.rectangle.badge.plus",
            titel: "YouTube-Channel verbinden",
            text: "Blackstock 12 baut jede Entscheidung kanalbezogen. Verbinde zuerst Google/YouTube; danach wird aus Analytics und Kanalthema die Channel DNA erstellt.",
            button: "Google / YouTube verbinden",
            action: { Task { _ = await store.googleZugangHinzufuegen() } })
        } else {
          connectionAndStrategy
          trendRadar
          productionIntelligence
          learningPanel
        }
      }
      .padding(26)
    }
    .onAppear { loadStrategy() }
    .onChange(of: selectedChannelID) { _ in loadStrategy() }
  }

  private var channelPicker: some View {
    Picker("Channel", selection: Binding(
      get: { selectedChannelID },
      set: { store.v12ActiveChannelID = $0 })) {
      Text("Channel auswählen").tag(UUID?.none)
      ForEach(store.liveKanaele) { channel in
        Text(channel.name).tag(Optional(channel.id))
      }
    }
    .frame(width: 230)
  }

  private var loopRail: some View {
    ScrollView(.horizontal, showsIndicators: false) {
      HStack(spacing: 8) {
        ForEach(CreatorLoopStage.allCases.indices, id: \.self) { index in
          let stage = CreatorLoopStage.allCases[index]
          let current = store.v12LoopStage(for: store.ausgewaehlteProduktionID)
          let activeIndex = CreatorLoopStage.allCases.firstIndex(of: current) ?? 0
          HStack(spacing: 8) {
            Image(systemName: stage.symbol)
              .font(.system(size: 11, weight: .semibold))
            Text(stage.rawValue)
              .font(.system(size: 10, weight: index == activeIndex ? .semibold : .medium))
          }
          .foregroundStyle(index <= activeIndex ? Color.bsText : Color.bsMuted)
          .padding(.horizontal, 11)
          .frame(height: 34)
          .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
              .fill(index == activeIndex ? Color.bsRed.opacity(0.10) : Color.bsSurface2))
          .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
              .stroke(index == activeIndex ? Color.bsRed.opacity(0.40) : Color.bsBorder, lineWidth: 1))
          if index < CreatorLoopStage.allCases.count - 1 {
            Image(systemName: "chevron.right")
              .font(.system(size: 8, weight: .bold))
              .foregroundStyle(Color.bsMuted2)
          }
        }
      }
    }
  }

  private var connectionAndStrategy: some View {
    HStack(alignment: .top, spacing: 14) {
      connectionCard.frame(maxWidth: .infinity)
      strategyCard.frame(maxWidth: .infinity)
    }
  }

  private var connectionCard: some View {
    VStack(alignment: .leading, spacing: 14) {
      AbschnittTitel(
        titel: "1 · Channel Intelligence",
        untertitel: "Google-/YouTube-Verbindung und Berechtigungen werden separat geprüft")
      HStack(spacing: 14) {
        ScoreRing(wert: health.score, label: "Connection", farbe: health.readyForCreatorLoop ? .bsGreen : .bsAmber)
        VStack(alignment: .leading, spacing: 7) {
          healthRow("OAuth", health.oauthConfigured)
          healthRow("Google Account", health.accountConnected)
          healthRow("YouTube Channel", health.channelConnected)
          healthRow("Analytics", health.analyticsAuthorized)
          healthRow("Upload", health.uploadAuthorized)
        }
      }
      Text(health.detail)
        .font(.system(size: 10.5))
        .foregroundStyle(Color.bsMuted)
        .lineSpacing(2)
      HStack {
        if !health.oauthConfigured {
          Button("OAuth einrichten…") { store.v12OAuthDateiAuswaehlen() }
            .buttonStyle(.borderedProminent).tint(Color.bsRed).foregroundStyle(.white)
        } else if !health.accountConnected || !health.channelConnected {
          Button("Neu verbinden") { Task { await store.v12GoogleVerbindungReparieren(channelID: selectedChannelID) } }
            .buttonStyle(.borderedProminent).tint(Color.bsRed).foregroundStyle(.white)
        }
        if let id = selectedChannelID, !health.uploadAuthorized {
          Button("Upload freigeben") { Task { await store.uploadBerechtigungVerbinden(channelID: id) } }
            .buttonStyle(.bordered)
        }
        Button("Synchronisieren") { Task { await store.liveDatenAktualisieren() } }
          .buttonStyle(.bordered)
          .disabled(store.istBeschaeftigt)
      }
    }
    .blackstockCard(16, elevated: true)
  }

  private func healthRow(_ title: String, _ ready: Bool) -> some View {
    HStack(spacing: 7) {
      Image(systemName: ready ? "checkmark.circle.fill" : "circle.dashed")
        .foregroundStyle(ready ? Color.bsGreen : Color.bsAmber)
      Text(title).font(.system(size: 10.5, weight: .medium)).foregroundStyle(Color.bsText)
    }
  }

  private var strategyCard: some View {
    VStack(alignment: .leading, spacing: 12) {
      AbschnittTitel(
        titel: "2 · Channel DNA",
        untertitel: "Thema, Zielgruppe, Formatmix und Qualitätsgrenze steuern alle weiteren Entscheidungen")
      if let strategyDraft {
        TextField("Kanalthema", text: binding(\.primaryTopic, fallback: strategyDraft.primaryTopic))
          .textFieldStyle(.roundedBorder)
        TextField("Zielgruppe", text: binding(\.audience, fallback: strategyDraft.audience))
          .textFieldStyle(.roundedBorder)
        TextField("Positionierung", text: binding(\.positioning, fallback: strategyDraft.positioning))
          .textFieldStyle(.roundedBorder)
        HStack(spacing: 10) {
          VStack(alignment: .leading, spacing: 4) {
            Text("Shorts-Anteil").font(.system(size: 9.5)).foregroundStyle(Color.bsMuted)
            Slider(value: doubleBinding(\.shortWeight, fallback: strategyDraft.shortWeight), in: 0.1...0.9)
          }
          VStack(alignment: .leading, spacing: 4) {
            Text("Quality Gate").font(.system(size: 9.5)).foregroundStyle(Color.bsMuted)
            Slider(value: doubleBinding(\.minimumQualityScore, fallback: strategyDraft.minimumQualityScore), in: 80...96, step: 1)
          }
        }
        HStack {
          Picker("Modus", selection: modeBinding(strategyDraft.operatingMode)) {
            ForEach(CreatorOperatingMode.allCases) { Text($0.rawValue).tag($0) }
          }.frame(width: 170)
          Spacer()
          Text("Short \(strategyDraft.targetShortSeconds)s · Long \(strategyDraft.targetLongformSeconds / 60) min")
            .font(.system(size: 9.5, weight: .medium)).foregroundStyle(Color.bsMuted)
          Button("DNA speichern") { saveStrategy() }
            .buttonStyle(.borderedProminent).tint(Color.bsRed).foregroundStyle(.white)
        }
      }
    }
    .blackstockCard(16, elevated: true)
  }

  private var trendRadar: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack {
        AbschnittTitel(
          titel: "3 · Trend Intelligence",
          untertitel: "Nicht nur Views: Geschwindigkeit, Nachfrage, Content Gap, Confidence und Format-Fit werden gemeinsam bewertet")
        Spacer()
        Button("Trends aktualisieren") { Task { _ = await store.chancenAktualisieren() } }
          .buttonStyle(.bordered)
          .disabled(store.istBeschaeftigt)
      }
      if decisions.isEmpty {
        EmptyState(
          symbol: "chart.line.uptrend.xyaxis",
          titel: "Noch keine starken Trend-Signale",
          text: "Aktualisiere Trends. Blackstock bewertet anschließend automatisch, welche Chance für diesen Channel als Short oder 5-Minuten-Video am besten passt.",
          button: nil,
          action: nil)
      } else {
        ForEach(decisions) { decision in
          if let chance = store.chancen.first(where: { $0.id == decision.chanceID }) {
            trendDecisionRow(chance: chance, decision: decision)
          }
        }
      }
    }
    .blackstockCard(16)
  }

  private func trendDecisionRow(chance: Chance, decision: TrendDecisionV12) -> some View {
    HStack(alignment: .center, spacing: 14) {
      ScoreRing(wert: decision.opportunityScore, label: "Opportunity", farbe: decision.opportunityScore >= 80 ? .bsGreen : .bsRed)
      VStack(alignment: .leading, spacing: 5) {
        Text(chance.titel).font(.system(size: 13, weight: .semibold)).foregroundStyle(Color.bsText).lineLimit(2)
        Text(decision.reason).font(.system(size: 9.5)).foregroundStyle(Color.bsMuted).lineLimit(2)
        HStack(spacing: 8) {
          Text(decision.recommendedFormat.rawValue.uppercased())
            .font(.system(size: 8, weight: .bold)).foregroundStyle(Color.bsRed)
          Text("Ziel \(decision.targetDurationSeconds)s")
            .font(.system(size: 8.5)).foregroundStyle(Color.bsMuted)
          Text("Source \(Int(decision.sourceConfidence * 100))%")
            .font(.system(size: 8.5)).foregroundStyle(Color.bsMuted)
        }
      }
      Spacer()
      Button("Short") { start(chance: chance, format: .short) }
        .buttonStyle(.bordered)
      Button("5 Min") { start(chance: chance, format: .longform) }
        .buttonStyle(.borderedProminent).tint(Color.bsRed).foregroundStyle(.white)
    }
    .padding(.vertical, 8)
    .overlay(alignment: .bottom) { Rectangle().fill(Color.bsBorder).frame(height: 1) }
  }

  private var productionIntelligence: some View {
    VStack(alignment: .leading, spacing: 12) {
      AbschnittTitel(
        titel: "4–9 · Remix → Quality → Render → Upload",
        untertitel: "Blackstock hält Uploads zurück, wenn Quality-, Rechte- oder Technik-Gates nicht erfüllt sind")
      if productions.isEmpty {
        Text("Noch keine V12-Produktion für diesen Channel.")
          .font(.system(size: 10.5)).foregroundStyle(Color.bsMuted)
      } else {
        ForEach(productions.prefix(6)) { production in
          productionRow(production)
        }
      }
    }
    .blackstockCard(16)
  }

  private func productionRow(_ production: Produktion) -> some View {
    let score = store.v12State.qualityScores[production.id]
    let stage = store.v12LoopStage(for: production.id)
    return HStack(spacing: 13) {
      ScoreRing(wert: score?.overall ?? production.qualitaet.gesamt, label: "Quality", farbe: score?.isReady(minimum: store.v12Strategy(for: production.kanalID).minimumQualityScore) == true ? .bsGreen : .bsAmber)
      VStack(alignment: .leading, spacing: 4) {
        Text(production.arbeitstitel).font(.system(size: 12.5, weight: .semibold)).foregroundStyle(Color.bsText).lineLimit(1)
        Text("\(stage.rawValue) · \(production.format.rawValue) · Ziel \(production.zielDauerSekunden)s")
          .font(.system(size: 9.5)).foregroundStyle(Color.bsMuted)
        if let score {
          Text("Hook \(Int(score.hook)) · Pace \(Int(score.pacing)) · Transformation \(Int(score.transformation)) · Retention-Prognose \(Int(score.predictedRetention))")
            .font(.system(size: 8.5)).foregroundStyle(Color.bsMuted2)
        }
      }
      Spacer()
      if let score, !score.blockingReasons.isEmpty {
        Text("\(score.blockingReasons.count) Gate\(score.blockingReasons.count == 1 ? "" : "s")")
          .font(.system(size: 9, weight: .semibold)).foregroundStyle(Color.bsAmber)
      }
      Button("Öffnen") {
        store.ausgewaehlteProduktionID = production.id
        store.ausgewaehltesZiel = .produktionen
      }.buttonStyle(.bordered)
    }
    .padding(.vertical, 6)
  }

  private var learningPanel: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack {
        AbschnittTitel(
          titel: "10 · Performance Learning",
          untertitel: "Jeder Upload verbessert Formatwahl, Hooks, Packaging und die nächsten Trendentscheidungen")
        Spacer()
        if let id = selectedChannelID {
          Button("Jetzt lernen") { store.v12LearningAktualisieren(channelID: id) }
            .buttonStyle(.bordered)
        }
      }
      ForEach(insights) { insight in
        HStack(alignment: .top, spacing: 12) {
          Image(systemName: "brain.head.profile")
            .foregroundStyle(Color.bsPurple)
            .frame(width: 20)
          VStack(alignment: .leading, spacing: 3) {
            Text("\(insight.kind.rawValue) · \(insight.summary)")
              .font(.system(size: 11, weight: .semibold)).foregroundStyle(Color.bsText)
            Text(insight.action).font(.system(size: 9.5)).foregroundStyle(Color.bsMuted).lineSpacing(2)
          }
          Spacer()
          VertrauenBadge(konfidenz: insight.confidence)
        }
        .padding(.vertical, 5)
      }
    }
    .blackstockCard(16, elevated: true)
  }

  private func start(chance: Chance, format: VideoFormat) {
    guard let channelID = selectedChannelID else { return }
    Task { _ = await store.v12ProduktionStarten(chance: chance, channelID: channelID, forcedFormat: format) }
  }

  private func loadStrategy() {
    guard let id = selectedChannelID else {
      strategyDraft = nil
      return
    }
    strategyDraft = store.v12EnsureStrategy(for: id)
    store.v12LearningAktualisieren(channelID: id)
  }

  private func saveStrategy() {
    guard let strategyDraft else { return }
    store.v12StrategySpeichern(strategyDraft)
    self.strategyDraft = store.v12Strategy(for: strategyDraft.channelID)
  }

  private func binding(_ keyPath: WritableKeyPath<ChannelStrategyV12, String>, fallback: String) -> Binding<String> {
    Binding(
      get: { strategyDraft?[keyPath: keyPath] ?? fallback },
      set: { value in strategyDraft?[keyPath: keyPath] = value })
  }

  private func doubleBinding(_ keyPath: WritableKeyPath<ChannelStrategyV12, Double>, fallback: Double) -> Binding<Double> {
    Binding(
      get: { strategyDraft?[keyPath: keyPath] ?? fallback },
      set: { value in strategyDraft?[keyPath: keyPath] = value })
  }

  private func modeBinding(_ fallback: CreatorOperatingMode) -> Binding<CreatorOperatingMode> {
    Binding(
      get: { strategyDraft?.operatingMode ?? fallback },
      set: { value in strategyDraft?.operatingMode = value })
  }
}
