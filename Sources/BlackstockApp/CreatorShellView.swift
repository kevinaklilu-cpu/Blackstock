#if os(macOS)
import SwiftUI
import BlackstockCore

struct CreatorShellView: View {
    @EnvironmentObject private var app: AppState
    @EnvironmentObject private var auth: GoogleYouTubeAuth
    @ObservedObject var trends: TrendViewModel
    let apiKey: String
    @State private var expanded = true
    @State private var showAccounts = false

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Rectangle().fill(Color.primary.opacity(0.07)).frame(width: 1)
            VStack(spacing: 0) {
                topBar
                Rectangle().fill(Color.primary.opacity(0.07)).frame(height: 1)
                content
                    .id(app.selection?.id ?? "dashboard")
                    .transition(.opacity)
                    .animation(.easeInOut(duration: 0.16), value: app.selection)
            }
        }
        .background(Color.blackstockSurface)
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
                    Button { withAnimation(.easeInOut(duration: 0.18)) { expanded = false } } label: {
                        Image(systemName: "sidebar.left").frame(width: 28, height: 28)
                    }.buttonStyle(.plain).help("Sidebar einklappen")
                }
            }
            .padding(.horizontal, expanded ? 16 : 14)
            .frame(height: 64)

            Button {
                app.createProject()
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "plus").font(.system(size: 16, weight: .bold))
                    if expanded { Text("Erstellen").font(.headline) }
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 11)
                .background(Color.blackstockRed, in: Capsule())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 12)
            .padding(.bottom, 14)
            .help("Neues Video-Projekt")

            ScrollView(showsIndicators: false) {
                VStack(spacing: 3) {
                    ForEach(AppState.Section.allCases.filter { $0 != .settings }) { section in
                        SidebarDestinationRow(section: section, expanded: expanded, selected: app.selection == section) {
                            app.selection = section
                        }
                    }
                }
                .padding(.horizontal, 8)
            }

            VStack(spacing: 5) {
                SidebarDestinationRow(section: .settings, expanded: expanded, selected: app.selection == .settings) {
                    app.selection = .settings
                }

                Button { showAccounts = true } label: {
                    HStack(spacing: 10) {
                        ChannelAvatar(title: app.channel.title, size: 32)
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
                    .padding(.horizontal, 10).padding(.vertical, 9)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 12))
            }
            .padding(8)
        }
        .frame(width: expanded ? 236 : 76)
        .background(Color.blackstockSidebar)
        .overlay(alignment: .topTrailing) {
            if !expanded {
                Button { withAnimation(.easeInOut(duration: 0.18)) { expanded = true } } label: {
                    Image(systemName: "chevron.right").font(.caption.weight(.bold)).frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
                .background(.regularMaterial, in: Circle())
                .offset(x: 12, y: 20)
            }
        }
    }

    private var topBar: some View {
        HStack(spacing: 14) {
            HStack(spacing: 9) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("YouTube durchsuchen, Trends finden …", text: $trends.query)
                    .textFieldStyle(.plain)
                    .onSubmit { runGlobalSearch() }
                if !trends.query.isEmpty {
                    Button { trends.query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
                        .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 14).padding(.vertical, 9)
            .frame(maxWidth: 560)
            .background(Color.primary.opacity(0.055), in: Capsule())
            .overlay(Capsule().strokeBorder(Color.primary.opacity(0.08)))

            Spacer()
            LiveStatusPill(text: app.hasAuthenticatedChannel ? "Kanal live" : "Offline", connected: app.hasAuthenticatedChannel)
            Button { app.createProject() } label: { Image(systemName: "video.badge.plus").font(.system(size: 16, weight: .semibold)).frame(width: 32, height: 32) }
                .buttonStyle(.plain).help("Erstellen")
            Button { showAccounts = true } label: { ChannelAvatar(title: app.channel.title, size: 34) }.buttonStyle(.plain)
        }
        .padding(.horizontal, 18)
        .frame(height: 58)
        .background(.ultraThinMaterial)
    }

    @ViewBuilder private var content: some View {
        switch app.selection ?? .dashboard {
        case .dashboard: DashboardView(trends: trends, apiKey: apiKey)
        case .trends: TrendsView(model: trends, apiKey: apiKey)
        case .research: ResearchView(trends: trends)
        case .ideas: IdeasView(trends: trends)
        case .projects: ProjectsView()
        case .studio: StudioView()
        case .publish: PublishView()
        case .analytics: AnalyticsView()
        case .settings: SettingsView(apiKey: .constant(apiKey))
        }
    }

    private func runGlobalSearch() {
        app.selection = .trends
        trends.search(apiKey: apiKey, regionCode: app.regionCode, channel: app.channel)
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
            HStack(spacing: 12) {
                Image(systemName: section.icon)
                    .font(.system(size: 15, weight: selected ? .semibold : .regular))
                    .frame(width: 25)
                if expanded {
                    Text(section.rawValue).font(.subheadline.weight(selected ? .semibold : .regular))
                    Spacer()
                    if section == .projects && selected { Circle().fill(Color.blackstockRed).frame(width: 6, height: 6) }
                }
            }
            .foregroundStyle(selected ? Color.primary : Color.secondary)
            .padding(.horizontal, 10).padding(.vertical, 9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(selected ? Color.primary.opacity(0.095) : (hovered ? Color.primary.opacity(0.055) : Color.clear))
            )
        }
        .buttonStyle(.plain)
        .onHover { inside in withAnimation(.easeOut(duration: 0.10)) { hovered = inside } }
        .help(expanded ? "" : section.rawValue)
    }
}

struct AccountConnectionSheet: View {
    @EnvironmentObject private var app: AppState
    @EnvironmentObject private var auth: GoogleYouTubeAuth
    @Environment(\.dismiss) private var dismiss
    @State private var errorMessage: String?
    @State private var manualClientID = GoogleYouTubeAuth.configuredClientID

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                BlackstockBrandLockup()
                Spacer()
                Button("Fertig") { dismiss() }.keyboardShortcut(.defaultAction)
            }
            Text("YouTube-Kanäle").font(.largeTitle.bold())
            Text("Der aktive Kanal bestimmt Trends, Projekte, Publishing und Analytics in Blackstock.").foregroundStyle(.secondary)

            if !app.connectedChannels.isEmpty {
                VStack(spacing: 8) {
                    ForEach(app.connectedChannels, id: \.id) { channel in
                        HStack(spacing: 12) {
                            ChannelAvatar(title: channel.title, size: 38)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(channel.title).font(.headline)
                                Text("\(BlackstockFormat.compact(channel.subscriberCount)) Abonnenten")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if app.channel.id == channel.id { Label("Aktiv", systemImage: "checkmark.circle.fill").foregroundStyle(Color.blackstockRed) }
                            else { Button("Wechseln") { app.selectChannel(id: channel.id) } }
                            Menu { Button("Verbindung entfernen", role: .destructive) { auth.disconnect(channelID: channel.id); app.removeConnectedChannel(id: channel.id) } } label: { Image(systemName: "ellipsis") }
                        }
                        .padding(12)
                        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 13))
                    }
                }
            }

            if GoogleYouTubeAuth.configuredClientID.isEmpty {
                VStack(alignment: .leading, spacing: 7) {
                    Text("Google-Verbindung konfigurieren").font(.headline)
                    Text("Für Entwicklungs-Builds kann die Desktop OAuth Client-ID einmalig hier gesetzt werden. Produktions-Builds erhalten sie automatisch beim Paketieren.")
                        .font(.caption).foregroundStyle(.secondary)
                    TextField("…apps.googleusercontent.com", text: $manualClientID).textFieldStyle(.roundedBorder)
                }
            }

            HStack {
                Button {
                    connectAnotherAccount()
                } label: {
                    HStack { if auth.isConnecting { ProgressView().controlSize(.small) }; Image(systemName: "person.crop.circle.badge.plus"); Text(auth.isConnecting ? "Google wird verbunden …" : "Weiteren YouTube-Account verbinden") }
                }
                .buttonStyle(.borderedProminent)
                .tint(.blackstockRed)
                .disabled(auth.isConnecting)
                Spacer()
            }
            if let message = auth.statusMessage { Text(message).font(.caption).foregroundStyle(.secondary) }
            if let errorMessage { Text(errorMessage).font(.caption).foregroundStyle(.red) }
            Spacer()
        }
        .padding(24)
        .frame(width: 620, height: 520)
    }

    private func connectAnotherAccount() {
        errorMessage = nil
        let clientID = manualClientID.trimmingCharacters(in: .whitespacesAndNewlines)
        if !clientID.isEmpty { Keychain.write(clientID, account: "youtube-oauth-client-id") }
        Task {
            do {
                let session = try await auth.connect(clientID: clientID.isEmpty ? nil : clientID)
                app.addConnectedChannels(session.channels)
            } catch { errorMessage = error.localizedDescription }
        }
    }
}
#endif
