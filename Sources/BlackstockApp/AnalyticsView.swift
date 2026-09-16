#if os(macOS)
import SwiftUI
import UniformTypeIdentifiers
import BlackstockCore

struct AnalyticsView: View {
    @State private var dataset: AnalyticsDataset?
    @State private var importing = false
    @State private var errorMessage: String?
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack { VStack(alignment: .leading, spacing: 4) { Text("Analytics").font(.largeTitle.bold()); Text("Echte YouTube-Studio-Daten, keine geschätzten Scores.").foregroundStyle(.secondary) }; Spacer(); Button("CSV importieren") { importing = true }.buttonStyle(.borderedProminent) }
                if let dataset {
                    HStack(spacing: 12) { metric("Aufrufe", BlackstockFormat.compact(dataset.views)); metric("Wiedergabezeit", String(format: "%.1f h", dataset.watchTimeHours)); metric("Impressionen", BlackstockFormat.compact(dataset.impressions)); metric("CTR", dataset.weightedCTR.map { String(format: "%.1f %%", $0 * 100) } ?? "—") }
                    Text("Videos / Zeilen").font(.title2.bold())
                    LazyVStack(spacing: 8) {
                        ForEach(dataset.rows.sorted { $0.views > $1.views }.prefix(100)) { row in
                            HStack { VStack(alignment: .leading, spacing: 3) { Text(row.title).font(.headline).lineLimit(1); Text("\(BlackstockFormat.compact(row.views)) Aufrufe · \(String(format: "%.1f", row.watchTimeHours)) h · \(BlackstockFormat.compact(row.impressions)) Impressionen").font(.caption).foregroundStyle(.secondary) }; Spacer(); if let ctr = row.clickThroughRate { Text(String(format: "%.1f %% CTR", ctr * 100)).font(.caption.monospacedDigit()) } }.padding(.vertical, 6); Divider()
                        }
                    }
                } else {
                    BlackstockCard { EmptyState(title: "Noch keine Analytics importiert", systemImage: "chart.xyaxis.line", message: "Exportiere in YouTube Studio eine Analytics-CSV und importiere sie hier. Blackstock zeigt nur Werte, die in dieser Datei tatsächlich vorhanden sind.") }
                }
                if let errorMessage { Text(errorMessage).font(.caption).foregroundStyle(.red) }
            }.padding(24)
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.commaSeparatedText, .plainText]) { result in
            switch result {
            case .success(let url): importCSV(url)
            case .failure(let error): errorMessage = error.localizedDescription
            }
        }
    }
    private func metric(_ label: String, _ value: String) -> some View { BlackstockCard { MetricLabel(value: value, label: label).frame(maxWidth: .infinity, alignment: .leading) } }
    private func importCSV(_ url: URL) {
        let access = url.startAccessingSecurityScopedResource(); defer { if access { url.stopAccessingSecurityScopedResource() } }
        do { let text = try String(contentsOf: url, encoding: .utf8); dataset = try AnalyticsCSVParser().parse(text); errorMessage = nil } catch { errorMessage = error.localizedDescription }
    }
}
#endif
