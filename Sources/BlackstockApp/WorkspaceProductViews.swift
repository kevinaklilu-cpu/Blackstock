#if os(macOS)
import Foundation
import SwiftUI
import BlackstockCore

struct OpportunityWorkspaceView: View {
    @ObservedObject var session: BlackstockSession
    let onProjectCreated: () -> Void

    @State private var query = ""
    @State private var sortMode: OpportunitySortMode = .relevance
    @State private var selectedOpportunityID: String?
    @State private var hasLoadedInitially = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header

            HStack(spacing: 10) {
                TextField(
                    "Thema oder Suchbegriff",
                    text: $query
                )
                .textFieldStyle(.roundedBorder)
                .onSubmit {
                    Task { await loadOpportunities() }
                }

                Picker("Sortierung", selection: $sortMode) {
                    ForEach(OpportunitySortMode.allCases, id: \.self) { mode in
                        Text(mode.germanTitle).tag(mode)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 175)

                Button {
                    Task { await loadOpportunities() }
                } label: {
                    HStack {
                        if session.isWorking {
                            ProgressView().controlSize(.small)
                        }
                        Label(
                            session.isWorking
                                ? "Lädt …"
                                : "Suchen",
                            systemImage: "magnifyingglass"
                        )
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(
                    session.isWorking
                    || query.trimmingCharacters(
                        in: .whitespacesAndNewlines
                    ).isEmpty
                )
            }

            if let error = session.errorMessage {
                Label(
                    error,
                    systemImage: "exclamationmark.triangle.fill"
                )
                .font(.caption)
                .foregroundStyle(.red)
            }

            if session.opportunities.isEmpty {
                emptyState
            } else {
                opportunityContent
            }

            Spacer(minLength: 0)
        }
        .padding(28)
        .task {
            guard !hasLoadedInitially else { return }
            hasLoadedInitially = true
            if query.isEmpty {
                query = session.primaryTopic
            }
            if session.opportunities.isEmpty,
               !query.trimmingCharacters(
                    in: .whitespacesAndNewlines
               ).isEmpty {
                await loadOpportunities()
            } else {
                selectedOpportunityID =
                    session.opportunities.first?.id
            }
        }
        .onChange(of: sortMode) { _ in
            guard hasLoadedInitially,
                  !query.trimmingCharacters(
                    in: .whitespacesAndNewlines
                  ).isEmpty else {
                return
            }
            Task { await loadOpportunities() }
        }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Entdecken")
                    .font(.largeTitle.bold())
                Text("Videos und Themen finden")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    private var emptyState: some View {
        GroupBox {
            VStack(spacing: 12) {
                Image(systemName: "sparkle.magnifyingglass")
                    .font(.largeTitle)
                    .foregroundStyle(.secondary)
                Text("Suche nach einem Thema")
                    .font(.headline)
                Text("Blackstock zeigt passende YouTube-Videos.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 36)
        }
    }

    private var opportunityContent: some View {
        HSplitView {
            ScrollView {
                LazyVStack(spacing: 10) {
                    ForEach(session.opportunities) { item in
                        opportunityRow(item)
                    }
                }
                .padding(.vertical, 2)
            }
            .frame(minWidth: 360, idealWidth: 430)

            ScrollView {
                if let selectedOpportunity {
                    opportunityDetail(selectedOpportunity)
                        .padding(.leading, 18)
                } else {
                    Text("Wähle ein Video.")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 280)
                }
            }
            .frame(minWidth: 480)
        }
    }

    private func opportunityRow(
        _ item: YouTubeOpportunityCandidate
    ) -> some View {
        Button {
            selectedOpportunityID = item.id
        } label: {
            HStack(alignment: .top, spacing: 12) {
                AsyncImage(url: item.thumbnailURL) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    Rectangle()
                        .fill(Color.primary.opacity(0.06))
                }
                .frame(width: 150, height: 84)
                .clipShape(RoundedRectangle(cornerRadius: 9))

                VStack(alignment: .leading, spacing: 5) {
                    Text(item.title)
                        .font(.headline)
                        .lineLimit(2)
                    Text(item.channelTitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    HStack(spacing: 10) {
                        if let views = item.metrics.viewCount {
                            Label(
                                compactNumber(views),
                                systemImage: "play.rectangle"
                            )
                        }
                        if let date = item.publishedAt {
                            Text(
                                date.formatted(
                                    date: .abbreviated,
                                    time: .omitted
                                )
                            )
                        }
                    }
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
                }

                Spacer()
            }
            .padding(10)
            .background(
                selectedOpportunity?.id == item.id
                    ? Color.accentColor.opacity(0.10)
                    : Color.primary.opacity(0.025),
                in: RoundedRectangle(cornerRadius: 12)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(
                        selectedOpportunity?.id == item.id
                            ? Color.accentColor.opacity(0.35)
                            : Color.clear
                    )
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func opportunityDetail(
        _ item: YouTubeOpportunityCandidate
    ) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            if item.embeddable != false {
                YouTubeEmbeddedPlayer(videoID: item.videoID)
                    .accessibilityLabel(
                        "YouTube-Vorschau: \(item.title)"
                    )
                    .frame(minHeight: 300)
                    .clipShape(
                        RoundedRectangle(cornerRadius: 14)
                    )
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: 14)
                        .fill(Color.primary.opacity(0.04))
                    VStack(spacing: 8) {
                        Image(systemName: "play.slash")
                            .font(.title)
                        Text("YouTube-Vorschau hier nicht verfügbar.")
                            .font(.headline)
                    }
                }
                .frame(minHeight: 260)
            }

            Text(item.title)
                .font(.title2.bold())
                .textSelection(.enabled)
            Text(item.channelTitle)
                .foregroundStyle(.secondary)

            signalStrip(item)

            DisclosureGroup("Details") {
                VStack(alignment: .leading, spacing: 7) {
                    Text("Suche: \(item.query)")
                    Text("Sortierung: \(sortMode.germanTitle)")
                    Text(
                        "Geladen: "
                        + item.retrievedAt.formatted(
                            date: .abbreviated,
                            time: .shortened
                        )
                    )
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.top, 6)
            }

            if !session.workspaceRightsResponsibilityAccepted {
                GroupBox("Nutzungsrechte") {
                    Toggle(
                        isOn: Binding(
                            get: {
                                session.workspaceRightsResponsibilityAccepted
                            },
                            set: {
                                _ = session
                                    .setWorkspaceRightsResponsibilityAccepted(
                                        $0
                                    )
                            }
                        )
                    ) {
                        Text("Ich darf diese Inhalte bearbeiten und veröffentlichen.")
                            .font(.caption)
                    }
                    .toggleStyle(.switch)
                }
            }

            HStack(spacing: 10) {
                Button {
                    let previousID = session.activeProject?.id
                    session.useOpportunity(item)
                    if session.activeProject?.id != previousID {
                        onProjectCreated()
                    }
                } label: {
                    Label(
                        "Projekt starten",
                        systemImage: "plus.rectangle.on.folder"
                    )
                }
                .buttonStyle(.bordered)

                Button {
                    let previousID = session.activeProject?.id
                    session.useOpportunityAsClip(item)
                    if session.activeProject?.id != previousID {
                        onProjectCreated()
                    }
                } label: {
                    Label(
                        "Clip-Projekt",
                        systemImage: "scissors"
                    )
                }
                .buttonStyle(.borderedProminent)
                .disabled(
                    !session.workspaceRightsResponsibilityAccepted
                )
            }
        }
    }

    private func signalStrip(
        _ item: YouTubeOpportunityCandidate
    ) -> some View {
        HStack(spacing: 8) {
            if let views = item.metrics.viewCount {
                metricChip(
                    "Views",
                    compactNumber(views),
                    systemImage: "play.rectangle"
                )
            }
            if let likes = item.metrics.likeCount {
                metricChip(
                    "Likes",
                    compactNumber(likes),
                    systemImage: "hand.thumbsup"
                )
            }
            if let comments = item.metrics.commentCount {
                metricChip(
                    "Kommentare",
                    compactNumber(comments),
                    systemImage: "bubble.left"
                )
            }
        }
    }

    private func metricChip(
        _ title: String,
        _ value: String,
        systemImage: String
    ) -> some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
            VStack(alignment: .leading, spacing: 1) {
                Text(value)
                    .font(
                        .caption.weight(.semibold)
                            .monospacedDigit()
                    )
                Text(title)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .background(
            Color.primary.opacity(0.04),
            in: RoundedRectangle(cornerRadius: 9)
        )
    }

    private var selectedOpportunity:
        YouTubeOpportunityCandidate? {
        if let selectedOpportunityID,
           let selected = session.opportunities.first(
                where: { $0.id == selectedOpportunityID }
           ) {
            return selected
        }
        return session.opportunities.first
    }

    private func loadOpportunities() async {
        selectedOpportunityID = nil
        await session.loadWorkspaceOpportunities(
            query: query,
            order: sortMode
        )
        selectedOpportunityID =
            session.opportunities.first?.id
    }

    private func compactNumber(_ value: Int) -> String {
        if value >= 1_000_000 {
            return String(
                format: "%.1fM",
                Double(value) / 1_000_000
            )
        }
        if value >= 1_000 {
            return String(
                format: "%.1fK",
                Double(value) / 1_000
            )
        }
        return String(value)
    }
}

struct ProjectLibraryView: View {
    @ObservedObject var session: BlackstockSession
    let onOpenProject: (BlackstockProject) -> Void
    let onFindOpportunity: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Projekte")
                        .font(.largeTitle.bold())
                    Text("Alle laufenden und fertigen Projekte")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    onFindOpportunity()
                } label: {
                    Label(
                        "Entdecken",
                        systemImage: "sparkle.magnifyingglass"
                    )
                }
                .buttonStyle(.borderedProminent)
            }

            if session.projects.isEmpty {
                GroupBox {
                    VStack(spacing: 12) {
                        Image(systemName: "tray")
                            .font(.largeTitle)
                            .foregroundStyle(.secondary)
                        Text("Noch keine Projekte")
                            .font(.headline)
                        Text("Starte mit einem Video unter „Entdecken“.")
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.secondary)
                        Button("Entdecken") {
                            onFindOpportunity()
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 36)
                }
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(session.projects) { project in
                            projectRow(project)
                        }
                    }
                }
            }

            Spacer(minLength: 0)
        }
        .padding(28)
    }

    private func projectRow(
        _ project: BlackstockProject
    ) -> some View {
        HStack(spacing: 14) {
            Image(
                systemName:
                    session.activeProject?.id == project.id
                    ? "folder.fill.badge.checkmark"
                    : "folder"
            )
            .font(.title2)
            .frame(width: 34)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(project.title)
                        .font(.headline)
                    if session.productionIntent(
                        for: project.id
                    )?.isLinkFirstClip == true {
                        Label(
                            "CLIP",
                            systemImage: "scissors"
                        )
                        .font(.caption2.weight(.bold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            Color.primary.opacity(0.07),
                            in: Capsule()
                        )
                    }
                    if session.activeProject?.id == project.id {
                        Text("AKTIV")
                            .font(.caption2.weight(.bold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(
                                Color.primary.opacity(0.07),
                                in: Capsule()
                            )
                    }
                }

                Text(project.stage.journeyGuidance.title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                HStack(spacing: 12) {
                    Text(
                        "Aktualisiert: "
                        + project.updatedAt.formatted(
                            date: .abbreviated,
                            time: .shortened
                        )
                    )
                }
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 6) {
                Text(
                    "Schritt \(project.stage.canonicalProgressPosition)/\(BlackstockStage.canonicalProgressCount)"
                )
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)

                if session.activeProject?.id == project.id {
                    Button {
                        onOpenProject(project)
                    } label: {
                        Label(
                            "Fortfahren",
                            systemImage: "arrow.right.circle"
                        )
                    }
                    .buttonStyle(.borderedProminent)
                } else {
                    Button {
                        onOpenProject(project)
                    } label: {
                        Label(
                            "Öffnen",
                            systemImage: "arrow.right.circle"
                        )
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
        .padding(14)
        .background(
            Color.primary.opacity(0.025),
            in: RoundedRectangle(cornerRadius: 12)
        )
    }
}
#endif
