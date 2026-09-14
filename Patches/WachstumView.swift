import Charts
import SwiftUI

struct WachstumView: View {
  @EnvironmentObject private var store: AppStore
  @State private var tab = "Übersicht"
  @State private var channelID: UUID?
  @State private var range: AnalyticsRangePreset = .twentyEightDays
  @State private var metric: AnalyticsMetric = .views

  private var points: [AnalyticsDailyPoint] { store.analyticsPoints(channelID: channelID, preset: range) }
  private var summary: AnalyticsSummary { store.analyticsSummary(channelID: channelID, preset: range) }
  private var selectedVideos: [VideoLeistung] {
    store.videos.filter { channelID == nil || $0.kanalID == channelID }
      .sorted { $0.views > $1.views }
  }
  private var revenueConnected: Bool {
    let ids = channelID.map { [$0] } ?? store.liveKanaele.map(\.id)
    return !ids.isEmpty && ids.allSatisfy {
      let status = store.channelProfile(for: $0).revenueAccess
      return status == .available || status == .authorizedNoData
    }
  }

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 18) {
        PageHeader(
          titel: "Analytics",
          untertitel: "Periodengenaue YouTube-Analytics. Lifetime-Werte und Zeitraum-KPIs werden nicht vermischt.",
          trailing: AnyView(filters))
        Picker("Bereich", selection: $tab) {
          ForEach(["Übersicht", "Inhalte", "Revenue"], id: \.self) { Text($0).tag($0) }
        }.pickerStyle(.segmented).frame(maxWidth: 520)

        switch tab {
        case "Inhalte": contentTab
        case "Revenue": revenueTab
        default: overviewTab
        }
      }.padding(26)
    }
  }

  private var filters: some View {
    HStack(spacing: 9) {
      Picker("Kanal", selection: $channelID) {
        Text("Alle Kanäle").tag(UUID?.none)
        ForEach(store.liveKanaele) { Text($0.name).tag(Optional($0.id)) }
      }.frame(width: 190)
      Picker("Zeitraum", selection: $range) {
        ForEach(AnalyticsRangePreset.allCases.filter { $0 != .custom }) { Text($0.rawValue).tag($0) }
      }.frame(width: 140)
      Button { Task { await store.liveDatenAktualisieren() } } label: { Image(systemName: "arrow.clockwise") }
        .buttonStyle(.bordered).disabled(store.istBeschaeftigt)
    }
  }

  private var overviewTab: some View {
    VStack(alignment: .leading, spacing: 16) {
      HStack(spacing: 12) {
        KPIKarte(titel: "Aufrufe", wert: summary.views.kompakt, delta: range.rawValue, symbol: "play.fill")
        KPIKarte(titel: "Watchtime", wert: watchtime(summary.watchTimeMinutes), delta: range.rawValue, symbol: "clock.fill", akzent: .bsBlue)
        KPIKarte(titel: "Abonnenten netto", wert: signed(summary.subscribersNet), delta: range.rawValue, symbol: "person.2.fill", akzent: .bsGreen)
        KPIKarte(titel: "Geschätzter Umsatz", wert: summary.estimatedRevenue.map { $0.euro } ?? "Nicht verfügbar", delta: revenueConnected ? range.rawValue : "Revenue-Zugriff fehlt", symbol: "eurosign.circle.fill", akzent: .bsGreen)
      }

      VStack(alignment: .leading, spacing: 12) {
        HStack {
          AbschnittTitel(titel: "Zeitreihe", untertitel: "Echte Tageswerte aus YouTube Analytics")
          Spacer()
          Picker("Metrik", selection: $metric) {
            ForEach(AnalyticsMetric.allCases.filter { $0 != .revenue || summary.estimatedRevenue != nil }) { Text($0.rawValue).tag($0) }
          }.pickerStyle(.segmented).frame(maxWidth: 420)
        }
        if points.isEmpty {
          VStack(spacing: 10) {
            Image(systemName: "chart.xyaxis.line")
              .font(.system(size: 30, weight: .medium))
              .foregroundStyle(Color.bsMuted)
            Text("Keine Analytics für diesen Zeitraum")
              .font(.system(size: 13, weight: .semibold))
              .foregroundStyle(Color.bsText)
            Text("Blackstock erzeugt keine Demo- oder Zufallswerte. Synchronisiere einen verbundenen YouTube-Kanal.")
              .font(.system(size: 10))
              .foregroundStyle(Color.bsMuted)
              .multilineTextAlignment(.center)
          }
          .frame(maxWidth: .infinity)
          .frame(height: 300)
        } else {
          Chart(points) { point in
            LineMark(x: .value("Tag", point.date), y: .value(metric.rawValue, value(point)))
            AreaMark(x: .value("Tag", point.date), y: .value(metric.rawValue, value(point))).opacity(0.08)
          }.frame(height: 320)
        }
      }.blackstockCard(elevated: true)
    }
  }

  private var contentTab: some View {
    VStack(alignment: .leading, spacing: 12) {
      AbschnittTitel(titel: "Inhalte", untertitel: "Per-Video-Kennzahlen sind Lifetime-basiert und damit innerhalb einer Zeile zeitlich konsistent")
      if selectedVideos.isEmpty {
        VStack(spacing: 10) {
          Image(systemName: "play.rectangle")
            .font(.system(size: 28, weight: .medium))
            .foregroundStyle(Color.bsMuted)
          Text("Keine synchronisierten Videos")
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(Color.bsText)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
      } else {
        Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 8) {
          GridRow {
            Text("Video"); Text("Format"); Text("Views"); Text("Watchtime"); Text("Abo +"); Text("CTR"); Text("Revenue")
          }.font(.system(size: 8.5, weight: .bold)).foregroundStyle(Color.bsMuted)
          Divider().gridCellColumns(7)
          ForEach(selectedVideos.prefix(60)) { video in
            GridRow {
              VStack(alignment: .leading, spacing: 2) {
                Text(video.titel).font(.system(size: 10, weight: .medium)).lineLimit(1)
                Text(store.kanalName(fuer: video.kanalID)).font(.system(size: 8)).foregroundStyle(Color.bsMuted)
              }
              Text(video.format.rawValue)
              Text(video.views.kompakt).monospacedDigit()
              Text(watchtime(Double(video.watchtimeMinuten)))
              Text("+\(video.abonnentenGewonnen.kompakt)")
              Text(video.thumbnailCTR.map { String(format: "%.1f %%", $0) } ?? "–")
              Text(video.umsatzVerfuegbar == true ? video.umsatz.euro : "–")
            }.font(.system(size: 9.5)).foregroundStyle(Color.bsText)
            Divider().gridCellColumns(7)
          }
        }
      }
    }.blackstockCard()
  }

  private var revenueTab: some View {
    VStack(alignment: .leading, spacing: 14) {
      AbschnittTitel(titel: "Revenue", untertitel: "Wird nur angezeigt, wenn Google monetäre Analytics tatsächlich autorisiert hat")
      if !revenueConnected {
        VStack(alignment: .leading, spacing: 10) {
          Label("Revenue-Zugriff nicht verbunden", systemImage: "lock")
            .font(.system(size: 13, weight: .semibold)).foregroundStyle(Color.bsText)
          Text("Blackstock zeigt bewusst kein 0,00 € an, solange monetäre Analytics fehlen.")
            .font(.system(size: 10)).foregroundStyle(Color.bsMuted)
          if let id = channelID ?? store.liveKanaele.first?.id {
            Button("Monetarisierungsdaten verbinden") { Task { await store.revenueZugriffVerbinden(channelID: id) } }
              .buttonStyle(.borderedProminent).tint(Color.bsRed).foregroundStyle(.white)
          }
        }.padding(.vertical, 8)
      } else {
        HStack(spacing: 12) {
          KPIKarte(titel: "Estimated Revenue", wert: summary.estimatedRevenue.map { $0.euro } ?? "Keine Daten", delta: range.rawValue, symbol: "eurosign.circle.fill", akzent: .bsGreen)
          KPIKarte(titel: "Revenue Videos", wert: "\(selectedVideos.filter { $0.umsatzVerfuegbar == true }.count)", delta: "mit verfügbaren Monetärdaten", symbol: "play.rectangle")
        }
        Text("Der exakte YouTube-Partnerprogramm-Status wird von Blackstock nicht aus Revenue-Werten abgeleitet. Den verbindlichen Status findest du in YouTube Studio.")
          .font(.system(size: 9.5)).foregroundStyle(Color.bsMuted)
      }
    }.blackstockCard(elevated: true)
  }

  private func value(_ point: AnalyticsDailyPoint) -> Double {
    switch metric {
    case .views: Double(point.views)
    case .watchTime: point.watchTimeMinutes / 60
    case .subscribers: Double(point.subscribersNet)
    case .revenue: point.estimatedRevenue ?? 0
    }
  }
  private func watchtime(_ minutes: Double) -> String { String(format: minutes >= 60_000 ? "%.1fK h" : "%.0f h", minutes >= 60_000 ? minutes / 60_000 : minutes / 60) }
  private func signed(_ value: Int) -> String { value > 0 ? "+\(value.kompakt)" : value.kompakt }
}
