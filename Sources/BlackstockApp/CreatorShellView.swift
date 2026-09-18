#if os(macOS)
import SwiftUI
import BlackstockCore

struct CreatorShellView: View {
    @EnvironmentObject private var app: AppState
    @EnvironmentObject private var auth: GoogleYouTubeAuth
    @ObservedObject var trends: TrendViewModel
    private var accessToken: String { GoogleYouTubeAuth.accessToken(channelID: app.channel.id) }
    @State private var expanded = true
    @State private var showAccounts = false
    @State private var createHovered = false

    private let discover: [AppState.Section] = [.dashboard, .trends, .research, .ideas]
    private let produce: [AppState.Section] = [.projects, .studio, .publish]
    private let measure: [AppState.Section] = [.analytics]

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Rectangle().fill(Color.primary.opacity(0.07)).frame(width: 1)
            VStack(spacing: 0) {
                topBar
                Rectangle().fill(Color.primary.opacity(0.07)).frame(height: 1)
                ZStack(alignment: .bottom) {
                    content
                        .id(app.selection?.id ?? "dashboard")
                        .transition(.opacity)
                        .animation(.easeInOut(duration: 0.15), value: app.selection)
                    if let project = app.activeProject { activeProjectDock(project) }
                }
            }
        }
        .background(
            ZStack {
                Color.blackstockSurface
                RadialGradient(colors: [Color.blackstockRed.opacity(0.028), .clear], center: .topTrailing, startRadius: 30, endRadius: 760)
            }
        )
        .sheet(isPresented: $showAccounts) {
            AccountConnectionSheet().environmentObject(app).environmentObject(auth)
        }
    }

    private var sidebar: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                BlackstockBrandLockup(compact: !expanded)
                Spacer(minLength: 0)
                if expanded {
                    Button { withAnimation(.spring(response: 0.26, dampingFraction: 0.9)) { expanded = false } } label: {
                        Image(systemName: "sidebar.left").frame(width: 28, height: 28)
                    }
                    .buttonStyle(.plain).foregroundStyle(.secondary).help("Sidebar einklappen")
                }
            }
            .padding(.horizontal, expanded ? 16 : 12)
            .frame(height: 66)

            Button { app.createProject() } label: {
                HStack(spacing: 10) {
                    Image(systemName: "plus").font(.system(size: 15, weight: .bold))
                    if expanded { Text("Erstellen").font(.headline); Spacer(); Text("⌘N").font(.caption2.monospaced()).opacity(0.72) }
                }
                .foregroundStyle(.white)
                .padding(.horizontal, expanded ? 15 : 0)
                .frame(maxWidth: .infinity)
                .frame(height: 42)
                .background(Color.blackstockRed.opacity(createHovered ? 0.88 : 1), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                .shadow(color: Color.blackstockRed.opacity(createHovered ? 0.25 : 0.13), radius: createHovered ? 13 : 7, y: 5)
                .scaleEffect(createHovered ? 1.012 : 1)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 10)
            .padding(.bottom, 8)
            .onHover { inside in withAnimation(.spring(response: 0.2, dampingFraction: 0.85)) { createHovered = inside } }
            .help("Neues Video-Projekt")

            ScrollView(showsIndicators: false) {
                VStack(spacing: 2) {
                    SidebarGroupLabel(title: "Entdecken", expanded: expanded)
                    ForEach(discover) { section in row(section) }
                    SidebarGroupLabel(title: "Produktion", expanded: expanded)
                    ForEach(produce) { section in row(section) }
                    SidebarGroupLabel(title: "Performance", expanded: expanded)
                    ForEach(measure) { section in row(section) }
                }
                .padding(.horizontal, 7)
                .padding(.bottom, 12)
            }

            VStack(spacing: 6) {
                SidebarDestinationRow(section: .settings, expanded: expanded, selected: app.selection == .settings) { app.selection = .settings }

                Button { showAccounts = true } label: {
                    HStack(spacing: 10) {
                        ZStack(alignment: .bottomTrailing) {
                            ChannelAvatar(title: app.channel.title, size: 34)
                            Circle()
                                .fill(app.hasAuthenticatedChannel ? Color.green : Color.secondary)
                                .frame(width: 9, height: 9)
                                .overlay(Circle().stroke(Color.blackstockSidebar, lineWidth: 2))
                        }
                        if expanded {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(app.channel.title).font(.subheadline.weight(.semibold)).lineLimit(1)
                                Text(app.hasAuthenticatedChannel ? "YouTube verbunden" : "Kanal verbinden")
                                    .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                            }
                            Spacer()
                            Image(systemName: "chevron.up.chevron.down").font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                    .padding(.horizontal, 9).padding(.vertical, 9)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 13))
                .overlay(RoundedRectangle(cornerRadius: 13).strokeBorder(Color.primary.opacity(0.055)))
            }
            .padding(8)
        }
        .frame(width: expanded ? 238 : 74)
        .background(.ultraThinMaterial)
        .overlay(alignment: .topTrailing) {
            if !expanded {
                Button { withAnimation(.spring(response: 0.26, dampingFraction: 0.9)) { expanded = true } } label: {
                    Image(systemName: "chevron.right").font(.caption.weight(.bold)).frame(width: 25, height: 25)
                }
                .buttonStyle(.plain)
                .background(.regularMaterial, in: Circle())
                .overlay(Circle().strokeBorder(Color.primary.opacity(0.08)))
                .offset(x: 12, y: 20)
                .help("Sidebar öffnen")
            }
        }
    }

    private func row(_ section: AppState.Section) -> some View {
        SidebarDestinationRow(section: section, expanded: expanded, selected: app.selection == section) { app.selection = section }
    }

    private var topBar: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 1) {
                Text(app.selection?.rawValue ?? "Übersicht").font(.headline)
                Text(app.channel.id == "local" ? "Blackstock Workspace" : app.channel.title)
                    .font(.caption2).foregroundStyle(.secondary)
            }
            .frame(width: 150, alignment: .leading)

            HStack(spacing: 9) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("YouTube durchsuchen, Trends und Creator finden …", text: $trends.query)
                    .textFieldStyle(.plain)
                    .onSubmit { runGlobalSearch() }
                if !trends.query.isEmpty {
                    Button { trends.query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
                        .buttonStyle(.plain)
                } else {
                    Text("↵").font(.caption.monospaced()).foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 14).padding(.vertical, 9)
            .frame(maxWidth: 610)
            .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.primary.opacity(0.075)))

            Spacer()
            if trends.isLoading { ProgressView().controlSize(.small).help("Trenddaten werden geladen") }
            LiveStatusPill(text: app.hasAuthenticatedChannel ? "Kanal live" : "Nicht verbunden", connected: app.hasAuthenticatedChannel)
            Button { app.createProject() } label: {
                Image(systemName: "video.badge.plus").font(.system(size: 16, weight: .semibold)).frame(width: 34, height: 34)
            }
            .buttonStyle(.plain).background(Color.primary.opacity(0.045), in: Circle()).help("Erstellen")
            Button { showAccounts = true } label: { ChannelAvatar(title: app.channel.title, size: 35) }.buttonStyle(.plain)
        }
        .padding(.horizontal, 18)
        .frame(height: 60)
        .background(.ultraThinMaterial)
    }

    @ViewBuilder private var content: some View {
        switch app.selection ?? .dashboard {
        case .dashboard: DashboardView(trends: trends, accessToken: accessToken)
        case .trends: TrendsView(model: trends, accessToken: accessToken)
        case .research: ResearchView(trends: trends)
        case .ideas: IdeasView(trends: trends)
        case .projects: ProjectsView()
        case .studio: StudioView()
        case .publish: PublishView()
        case .analytics: AnalyticsView()
        case .settings: SettingsView()
        }
    }

    private func activeProjectDock(_ project: Project) -> some View {
        HStack(spacing: 11) {
            Image(systemName: project.targetFormat == .short ? "rectangle.portrait.fill" : "play.rectangle.fill")
                .foregroundStyle(Color.blackstockRed)
            VStack(alignment: .leading, spacing: 1) {
                Text(project.title).font(.caption.weight(.semibold)).lineLimit(1)
                Text(projectDockSubtitle(project)).font(.caption2).foregroundStyle(.secondary)
            }
            Divider().frame(height: 24)
            Button("Studio") { app.selection = .studio }.buttonStyle(.plain)
            Button("Publishing") { app.selection = .publish }.buttonStyle(.plain)
            Button { app.activeProject = nil } label: { Image(systemName: "xmark").font(.caption) }.buttonStyle(.plain).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14).padding(.vertical, 9)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(Color.primary.opacity(0.08)))
        .shadow(color: .black.opacity(0.12), radius: 18, y: 8)
        .padding(.bottom, 14)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    private func projectDockSubtitle(_ project: Project) -> String {
        let stage = ProjectWorkflowEngine().stage(for: project)
        switch stage {
        case .idea: return "Idee"
        case .editing: return "Im Studio"
        case .rendered: return "Render fertig"
        case .packaging: return "Packaging"
        case .ready: return "Bereit zum Upload"
        }
    }

    private func runGlobalSearch() {
        app.selection = .trends
        trends.search(accessToken: accessToken, regionCode: app.regionCode, channel: app.channel)
    }
}

private struct SidebarDestinationRow: View {
    let section: AppState.Section
    let expanded: Bool
    let selected: Bool
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 11) {
                ZStack {
                    if selected { RoundedRectangle(cornerRadius: 8).fill(Color.blackstockRed.opacity(0.11)).frame(width: 31, height: 29) }
                    Image(systemName: section.icon)
                        .font(.system(size: 14, weight: selected ? .semibold : .regular))
                        .foregroundStyle(selected ? Color.blackstockRed : Color.secondary)
                        .frame(width: 25)
                }
                if expanded {
                    Text(section.rawValue).font(.subheadline.weight(selected ? .semibold : .regular))
                    Spacer()
                    if selected { Capsule().fill(Color.blackstockRed).frame(width: 3, height: 17) }
                }
            }
            .foregroundStyle(selected ? Color.primary : Color.secondary)
            .padding(.horizontal, 8).padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(selected ? Color.primary.opacity(0.065) : (hovered ? Color.primary.opacity(0.045) : Color.clear))
            )
        }
        .buttonStyle(.plain)
        .onHover { inside in withAnimation(.easeOut(duration: 0.11)) { hovered = inside } }
        .help(expanded ? "" : section.rawValue)
    }
}

struct AccountConnectionSheet: View {
    @EnvironmentObject private var app: AppState
    @EnvironmentObject private var auth: GoogleYouTubeAuth
    @Environment(\.dismiss) private var dismiss
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                BlackstockBrandLockup()
                Spacer()
                Button("Fertig") { dismiss() }.keyboardShortcut(.defaultAction)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("YouTube-Kanäle").font(.largeTitle.bold())
                Text("Der aktive Kanal bestimmt Projekte, Publishing und kanalbezogene Auswertungen.")
                    .foregroundStyle(.secondary)
            }

            if !app.connectedChannels.isEmpty {
                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(app.connectedChannels, id: \.id) { channel in
                            HStack(spacing: 12) {
                                ChannelAvatar(title: channel.title, size: 40)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(channel.title).font(.headline)
                                    Text("\(BlackstockFormat.compact(channel.subscriberCount)) Abonnenten")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                if app.channel.id == channel.id {
                                    Label("Aktiv", systemImage: "checkmark.circle.fill")
                                        .foregroundStyle(Color.blackstockRed)
                                } else {
                                    Button("Wechseln") { app.selectChannel(id: channel.id) }
                                }
                                Menu {
                                    Button("Verbindung entfernen", role: .destructive) {
                                        auth.disconnect(channelID: channel.id)
                                        app.removeConnectedChannel(id: channel.id)
                                    }
                                } label: {
                                    Image(systemName: "ellipsis")
                                }
                            }
                            .padding(12)
                            .background(Color.blackstockPanel, in: RoundedRectangle(cornerRadius: 13))
                            .overlay(RoundedRectangle(cornerRadius: 13).strokeBorder(Color.blackstockBorder))
                        }
                    }
                }
                .frame(maxHeight: 250)
            }

            HStack {
                Button { connectAnotherAccount() } label: {
                    HStack {
                        if auth.isConnecting { ProgressView().controlSize(.small) }
                        Image(systemName: "person.crop.circle.badge.plus")
                        Text(auth.isConnecting ? "Warte auf Google …" : "Weiteren YouTube-Account verbinden")
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(.blackstockRed)
                .disabled(auth.isConnecting)

                if auth.isConnecting {
                    Button("Abbrechen") { auth.cancelConnection() }
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            if let message = auth.statusMessage {
                Text(message).font(.caption).foregroundStyle(.secondary)
            }
            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption).foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
        }
        .padding(24)
        .frame(width: 640, height: 520)
    }

    private func connectAnotherAccount() {
        errorMessage = nil
        Task {
            do {
                let session = try await auth.connect()
                app.addConnectedChannels(session.channels)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}
#endif
