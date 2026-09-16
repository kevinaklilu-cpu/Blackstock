#if os(macOS)
import SwiftUI
import BlackstockCore

struct IdeasView: View {
    @EnvironmentObject private var app: AppState
    @ObservedObject var trends: TrendViewModel
    private var ideas: [ContentIdea] { IdeaEngine().ideas(from: trends.items) }
    var body: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 330), spacing: 14)], spacing: 14) {
                ForEach(ideas) { idea in
                    BlackstockCard {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack { Text(idea.topic.capitalized).font(.caption.weight(.semibold)).foregroundStyle(.secondary); Spacer(); Text(idea.recommendedFormat == .short ? "Short" : "Longform").font(.caption.weight(.semibold)).padding(.horizontal, 8).padding(.vertical, 4).background(.quaternary, in: Capsule()) }
                            Text(idea.workingTitle).font(.title3.weight(.semibold))
                            VStack(alignment: .leading, spacing: 6) { ForEach(Array(idea.evidence.enumerated()), id: \.offset) { _, evidence in Label(evidence, systemImage: "checkmark.circle").font(.caption).foregroundStyle(.secondary) } }
                            Spacer(minLength: 4)
                            Button("Als Projekt starten") { app.startProject(from: idea) }.buttonStyle(.borderedProminent)
                        }.frame(minHeight: 190, alignment: .topLeading)
                    }
                }
            }.padding(20)
        }
        .navigationTitle("Ideen")
        .overlay { if ideas.isEmpty { EmptyState(title: "Noch keine Ideen", systemImage: "lightbulb", message: "Lade zuerst Trends. Blackstock leitet Ideen nur aus vorhandenen Belegen ab.") } }
    }
}
#endif
