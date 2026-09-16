#if os(macOS)
import SwiftUI

struct AnalyticsView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Analytics").font(.largeTitle.bold())
                Text("Blackstock zeigt hier nur Werte, die tatsächlich aus deinem Kanal oder importierten Daten stammen. Keine erfundenen Scores.").foregroundStyle(.secondary)
                BlackstockCard {
                    EmptyState(title: "Noch keine Kanaldaten verbunden", systemImage: "chart.xyaxis.line", message: "Bis echte Daten vorhanden sind, zeigt Blackstock bewusst keine geschätzten Leistungswerte.")
                }
            }.padding(24)
        }
    }
}
#endif
