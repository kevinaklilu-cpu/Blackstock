import SwiftUI
import WebKit
import UniformTypeIdentifiers

public struct BlackstockRootView: View {
    @ObservedObject var state: BlackstockState

    public init(state: BlackstockState) { self.state = state }

    public var body: some View {
        NavigationSplitView {
            VStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("BLACKSTOCK").font(.system(size: 18, weight: .black, design: .rounded))
                    Text("Source-first creator intelligence").font(.caption2).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)

                if !state.channels.isEmpty {
                    Picker("Kanal", selection: Binding(get: { state.activeChannelID }, set: { state.activateChannel($0) })) {
                        ForEach(state.channels) { channel in Text(channel.name).tag(Optional(channel.id)) }
                    }
                    .labelsHidden()
                    .padding(.horizontal, 8)
                }

                VStack(spacing: 4) {
                    ForEach(BlackstockRoute.allCases) { route in
                        Button {
                            state.route = route
                        } label: {
                            HStack(spacing: 9) {
                                Image(systemName: icon(for: route)).frame(width: 18)
                                Text(route.rawValue)
                                Spacer()
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .background(state.route == route ? Color.accentColor.opacity(0.12) : Color.clear)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 8)
                Spacer(minLength: 0)

                VStack(alignment: .leading, spacing: 5) {
                    if state.isBusy { ProgressView().controlSize(.small) }
                    if !state.statusMessage.isEmpty {
                        Text(state.statusMessage).font(.caption2).foregroundStyle(.secondary).lineLimit(4)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
            }
            .navigationSplitViewColumnWidth(min: 210, ideal: 240, max: 280)
        } detail: {
            Group {
                switch state.route {
                case .channel: ChannelView(state: state)
                case .opportunities: OpportunitiesView(state: state)
                case .cut: CutWorkspaceView(state: state)
                case .quality: QualityView(state: state)
                case .settings: SettingsView(state: state)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .alert("Blackstock", isPresented: Binding(get: { state.lastError != nil }, set: { if !$0 { state.lastError = nil } })) {
                Button("OK") { state.lastError = nil }
            } message: {
                Text(state.lastError ?? "")
            }
        }
    }

    private func icon(for route: BlackstockRoute) -> String {
        switch route {
        case .channel: return "person.crop.rectangle.stack"
        case .opportunities: return "scope"
        case .cut: return "scissors"
        case .quality: return "checkmark.seal"
        case .settings: return "gearshape"
        }
    }
}

private struct PageHeader: View {
    let title: String
    let subtitle: String
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.system(size: 28, weight: .bold, design: .rounded))
            Text(subtitle).font(.system(size: 12)).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct Card<Content: View>: View {
    let content: Content
    init(@ViewBuilder content: () -> Content) { self.content = content() }
    var body: some View {
        content
            .padding(16)
            .background(.background)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.secondary.opacity(0.18)))
    }
}

public struct ChannelView: View {
    @ObservedObject var state: BlackstockState
    @State private var channelInput = ""

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                PageHeader(title: "Kanal", subtitle: "Ein verbundener Kanal bestimmt Thema, Sprache und alle Empfehlungen. Kein manuelles Themen-Hopping im normalen Workflow.")

                Card {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("YouTube-Datenzugriff").font(.headline)
                        Text("Blackstock nutzt die offizielle YouTube Data API für öffentliche Kanal- und Videodaten. Der Schlüssel bleibt im macOS-Schlüsselbund.")
                            .font(.caption).foregroundStyle(.secondary)
                        HStack {
                            SecureField("YouTube Data API Key", text: $state.apiKey)
                                .textFieldStyle(.roundedBorder)
                            Button("Speichern") { state.saveAPIKey() }.disabled(state.apiKey.isEmpty)
                        }
                    }
                }

                Card {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Kanal verbinden").font(.headline)
                        TextField("@handle, Kanal-URL oder Channel-ID", text: $channelInput)
                            .textFieldStyle(.roundedBorder)
                            .onSubmit { Task { await state.connectChannel(channelInput) } }
                        HStack {
                            Button { Task { await state.connectChannel(channelInput) } } label: {
                                Label("Kanal analysieren", systemImage: "link")
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(state.isBusy || channelInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || state.apiKey.isEmpty)
                            Spacer()
                            Text("Kein Upload · keine Passwortabfrage")
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                }

                if let channel = state.activeChannel {
                    Card {
                        VStack(alignment: .leading, spacing: 14) {
                            HStack(spacing: 12) {
                                if let url = channel.thumbnailURL {
                                    AsyncImage(url: url) { image in image.resizable().scaledToFill() } placeholder: { Color.secondary.opacity(0.12) }
                                        .frame(width: 54, height: 54).clipShape(Circle())
                                }
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(channel.name).font(.title3.bold())
                                    Text("\(formatCount(channel.subscriberCount)) Abonnenten · \(formatCount(channel.videoCount)) Videos")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Button("Trennen", role: .destructive) { state.removeActiveChannel() }
                            }
                            Divider()
                            Text("CHANNEL DNA").font(.caption.bold()).foregroundStyle(.secondary)
                            HStack(alignment: .top, spacing: 30) {
                                metric("Hauptthema", channel.dna.primaryTopic)
                                metric("Sprache", channel.dna.languageHint)
                                metric("Analysiert", "\(channel.dna.sampleSize) Videos")
                            }
                            if !channel.dna.contentPillars.isEmpty { FlowTags(values: channel.dna.contentPillars) }
                            Text("Diese DNA ist an genau diesen Kanal gebunden. Beim Kanalwechsel wechseln Chancen und Schnittentscheidungen mit.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .padding(24)
            .frame(maxWidth: 1050, alignment: .leading)
        }
    }

    private func metric(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption2).foregroundStyle(.secondary)
            Text(value).font(.system(size: 14, weight: .semibold))
        }
    }
}

private struct FlowTags: View {
    let values: [String]
    var body: some View {
        HStack(spacing: 7) {
            ForEach(values, id: \.self) { value in
                Text(value).font(.caption2.weight(.semibold)).padding(.horizontal, 9).padding(.vertical, 5)
                    .background(.secondary.opacity(0.1)).clipShape(Capsule())
            }
        }
    }
}

public struct OpportunitiesView: View {
    @ObservedObject var state: BlackstockState

    public var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .bottom) {
                PageHeader(title: "Chancen", subtitle: state.activeChannel.map { "Nur Chancen, die zu \($0.name) passen – Fit, Momentum und Frische statt erfundener Viral-Garantie." } ?? "Verbinde zuerst einen Kanal.")
                Button { Task { await state.refreshOpportunities() } } label: {
                    Label("Markt aktualisieren", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.borderedProminent)
                .disabled(state.activeChannel == nil || state.apiKey.isEmpty || state.isBusy)
            }
            .padding(24)
            Divider()
            if state.opportunities.isEmpty {
                EmptyState(title: "Noch keine Chancen", icon: "scope", message: "Blackstock durchsucht erst nach einem verbundenen Kanal den relevanten YouTube-Markt.")
            } else {
                HSplitView {
                    ScrollView {
                        LazyVStack(spacing: 10) {
                            ForEach(state.opportunities) { opportunity in
                                OpportunityRow(opportunity: opportunity, selected: state.selectedOpportunityID == opportunity.id) {
                                    Task { await state.selectOpportunity(opportunity) }
                                }
                            }
                        }
                        .padding(16)
                    }
                    .frame(minWidth: 380, idealWidth: 470)
                    OpportunityDetail(state: state).frame(minWidth: 430)
                }
            }
        }
    }
}

private struct OpportunityRow: View {
    let opportunity: Opportunity
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                if let url = opportunity.video.thumbnailURL {
                    AsyncImage(url: url) { image in image.resizable().scaledToFill() } placeholder: { Color.secondary.opacity(0.1) }
                        .frame(width: 120, height: 68).clipped().clipShape(RoundedRectangle(cornerRadius: 8))
                }
                VStack(alignment: .leading, spacing: 5) {
                    Text(opportunity.video.title).font(.system(size: 13, weight: .semibold)).lineLimit(2).foregroundStyle(.primary)
                    Text(opportunity.video.channelTitle).font(.caption2).foregroundStyle(.secondary)
                    HStack(spacing: 8) {
                        scorePill("Fit", opportunity.channelFit)
                        scorePill("Momentum", opportunity.momentum)
                        Text(formatDuration(opportunity.video.durationSeconds)).font(.caption2).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                VStack(spacing: 1) {
                    Text(String(Int(opportunity.score.rounded()))).font(.title3.bold())
                    Text("Chance").font(.caption2).foregroundStyle(.secondary)
                }
            }
            .padding(11)
            .background(selected ? Color.accentColor.opacity(0.09) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(selected ? Color.accentColor.opacity(0.35) : Color.secondary.opacity(0.12)))
        }
        .buttonStyle(.plain)
    }
}

private struct OpportunityDetail: View {
    @ObservedObject var state: BlackstockState

    var body: some View {
        ScrollView {
            if let opportunity = state.selectedOpportunity {
                VStack(alignment: .leading, spacing: 16) {
                    YouTubeEmbedView(videoID: opportunity.video.videoID)
                        .aspectRatio(16/9, contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                    Text(opportunity.video.title).font(.title3.bold())
                    Text(opportunity.video.channelTitle).font(.caption).foregroundStyle(.secondary)
                    Card {
                        VStack(alignment: .leading, spacing: 9) {
                            Text("Warum Blackstock das zeigt").font(.headline)
                            ForEach(opportunity.reasons, id: \.self) { reason in Label(reason, systemImage: "checkmark.circle") }
                            Text("Score = 52 % Channel-Fit + 33 % View-Geschwindigkeit + 15 % Frische. Keine Viral-Garantie.")
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                    Card {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("YouTube-only Workflow").font(.headline)
                            Text("Blackstock lädt dieses Video nicht herunter. Öffentliche Kommentar-Zeitmarken dienen nur als Signal; Remix/Cut wird ausschließlich in YouTube geöffnet und dort von YouTube freigegeben oder abgelehnt.")
                                .font(.caption).foregroundStyle(.secondary)
                            if state.project.youtubeVideoID == opportunity.video.videoID && !state.project.moments.isEmpty {
                                ForEach(state.project.moments.prefix(4)) { moment in
                                    HStack {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(moment.title).font(.caption.bold())
                                            Text(moment.rationale.first ?? "Publikums-Signal").font(.caption2).foregroundStyle(.secondary)
                                        }
                                        Spacer()
                                        Button("Öffnen") { state.openYouTubeNative(moment: moment) }
                                    }
                                }
                            } else {
                                Text("Keine belastbaren öffentlichen Zeitmarken gefunden. Blackstock erfindet dann keine künstlichen Schnittpunkte.")
                                    .font(.caption2).foregroundStyle(.secondary)
                            }
                            Button { state.openYouTubeNative(moment: state.project.selectedMoment) } label: {
                                Label("In YouTube öffnen · Remix prüfen", systemImage: "play.rectangle.fill")
                            }
                            .buttonStyle(.borderedProminent)
                        }
                    }
                    Button { state.route = .cut } label: { Label("Eigene erlaubte Quelldatei schneiden", systemImage: "scissors") }
                        .buttonStyle(.bordered)
                }
                .padding(20)
            }
        }
    }
}

public struct CutWorkspaceView: View {
    @ObservedObject var state: BlackstockState
    @State private var importer = false

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                PageHeader(title: "Schnitt", subtitle: "Nur bestehendes Originalmaterial. Lokale Dateien bleiben auf diesem Mac; Blackstock erzeugt keine synthetischen Ersatzvideos.")

                Card {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Originalquelle").font(.headline)
                                Text("Wähle eine Datei, die du bearbeiten und für deinen Zweck verwenden darfst.").font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button { importer = true } label: {
                                Label(state.project.sourceURL == nil ? "Videodatei wählen" : "Quelle wechseln", systemImage: "folder")
                            }
                            .buttonStyle(.borderedProminent)
                        }
                        if let info = state.project.mediaInfo {
                            Divider()
                            HStack(spacing: 24) {
                                mediaMetric("Auflösung", "\(info.width)×\(info.height)")
                                mediaMetric("FPS", String(format: "%.2f", info.fps))
                                mediaMetric("Dauer", formatDuration(info.duration))
                                mediaMetric("Audio", info.hasAudio ? "vorhanden" : "keins")
                            }
                            Toggle("Ich bestätige, dass ich diese Quelldatei bearbeiten und für den vorgesehenen Zweck verwenden darf.", isOn: Binding(get: { state.project.sourceRightsConfirmed }, set: { state.setRightsConfirmed($0) }))
                                .font(.caption)
                            Text("Diese Bestätigung ist keine Rechtsberatung. Blackstock lädt keine YouTube-Videodatei für dich herunter.")
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                }

                if state.project.sourceURL != nil {
                    Card {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Momentanalyse").font(.headline)
                                Text("Lokale Spracherkennung bewertet inhaltlich vollständige Abschnitte; das Originalaudio bleibt erhalten.")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button { Task { await state.analyzeLocalSource() } } label: {
                                Label("Starke Momente finden", systemImage: "waveform.and.magnifyingglass")
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(!state.project.sourceRightsConfirmed || state.isBusy)
                        }
                    }
                }

                if !state.project.moments.isEmpty && state.project.sourceURL != nil {
                    Card {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Beste Schnittmomente").font(.headline)
                            ForEach(state.project.moments) { moment in
                                MomentRow(moment: moment, selected: state.project.selectedMomentID == moment.id) {
                                    state.selectMoment(moment.id)
                                }
                            }
                        }
                    }

                    Card {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Export").font(.headline)
                            Picker("Format", selection: Binding(get: { state.project.aspect }, set: { state.setAspect($0) })) {
                                ForEach(AspectMode.allCases) { Text($0.rawValue).tag($0) }
                            }
                            .pickerStyle(.segmented)
                            Text("Original = höchste Quelltreue. 9:16/1:1 verwenden einen hochwertigen Center-Crop ohne künstliches Upscaling, generierte Bilder, KI-Stimme oder zusätzliche Musik.")
                                .font(.caption2).foregroundStyle(.secondary)
                            HStack {
                                Button { Task { await state.exportSelectedMoment() } } label: {
                                    Label("High-Quality exportieren", systemImage: "square.and.arrow.up")
                                }
                                .buttonStyle(.borderedProminent)
                                .disabled(state.project.selectedMoment == nil || !state.project.sourceRightsConfirmed || state.isBusy)
                                if state.project.exportedURL != nil {
                                    Button("Im Finder zeigen") { state.revealExport() }
                                    Button("Prüfbericht") { state.route = .quality }
                                }
                            }
                        }
                    }
                }
            }
            .padding(24)
            .frame(maxWidth: 1050, alignment: .leading)
        }
        .fileImporter(isPresented: $importer, allowedContentTypes: [.movie], allowsMultipleSelection: false) { result in
            switch result {
            case .success(let urls): if let url = urls.first { Task { await state.importLocalSource(url) } }
            case .failure(let error): state.lastError = error.localizedDescription
            }
        }
    }

    private func mediaMetric(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption2).foregroundStyle(.secondary)
            Text(value).font(.caption.bold())
        }
    }
}

private struct MomentRow: View {
    let moment: ClipMoment
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(formatTime(moment.start) + " – " + formatTime(moment.end)).font(.caption.monospacedDigit().bold())
                        Text("· \(Int(moment.score.rounded()))").font(.caption2).foregroundStyle(.secondary)
                    }
                    Text(moment.previewText).font(.caption).lineLimit(2).foregroundStyle(.primary)
                    Text(moment.rationale.joined(separator: " · ")).font(.caption2).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(selected ? Color.accentColor : Color.secondary)
            }
            .padding(10)
            .background(selected ? Color.accentColor.opacity(0.08) : Color.secondary.opacity(0.04))
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }
}

public struct QualityView: View {
    @ObservedObject var state: BlackstockState

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                PageHeader(title: "Prüfungen", subtitle: "Ein Export gilt erst als fertig, nachdem Blackstock Dauer, Audio, Framerate, Auflösung und Dateiplausibilität erneut geprüft hat.")
                if let report = state.project.qualityReport {
                    Card {
                        VStack(alignment: .leading, spacing: 12) {
                            Label(report.passed ? "Qualitätsprüfung bestanden" : "Export mit Warnungen", systemImage: report.passed ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                                .font(.title3.bold())
                                .foregroundStyle(report.passed ? Color.green : Color.orange)
                            ForEach(report.checks, id: \.self) { Label($0, systemImage: "checkmark") }
                            ForEach(report.warnings, id: \.self) { Label($0, systemImage: "exclamationmark.triangle").foregroundStyle(.orange) }
                            if let output = report.output {
                                Divider()
                                Text("Ausgabe: \(output.width)×\(output.height) · \(String(format: "%.2f", output.fps)) fps · \(formatDuration(output.duration))")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                } else {
                    EmptyState(title: "Noch kein geprüfter Export", icon: "checkmark.seal", message: "Nach einem lokalen High-Quality-Export erscheint hier der technische Prüfbericht.")
                }
            }
            .padding(24)
            .frame(maxWidth: 900, alignment: .leading)
        }
    }
}

public struct SettingsView: View {
    @ObservedObject var state: BlackstockState

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                PageHeader(title: "Einstellungen", subtitle: "Blackstock ist source-first: keine generierten Ersatzvideos, kein versteckter YouTube-Downloader, kein automatischer Upload.")
                Card {
                    VStack(alignment: .leading, spacing: 9) {
                        Text("Produktvertrag").font(.headline)
                        contract("YouTube-Videos", "werden im eingebetteten Player angesehen und für Remix/Cut an YouTube übergeben.")
                        contract("Lokale Quelldateien", "werden nur nach Rechtebestätigung lokal analysiert und gerendert.")
                        contract("Audio", "Originalaudio bleibt erhalten; Blackstock fügt standardmäßig weder KI-Stimme noch Musik hinzu.")
                        contract("Export", "wird nach dem Render technisch erneut geprüft.")
                        contract("Uploads", "führt diese Blackstock-Version nicht selbstständig aus.")
                    }
                }
                Card {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Marktreife-Gates").font(.headline)
                        Text("Funktionen werden erst als fertig betrachtet, wenn Technik, UX, Ergebnisqualität und Business-Nutzen gemeinsam bestehen.")
                            .font(.caption).foregroundStyle(.secondary)
                        Label("Kanalgebundene Channel-DNA", systemImage: "checkmark.circle")
                        Label("YouTube-native Übergabe ohne Download", systemImage: "checkmark.circle")
                        Label("Lokale Momentanalyse für erlaubte Quellen", systemImage: "checkmark.circle")
                        Label("High-Quality-Export + Post-Export-Prüfung", systemImage: "checkmark.circle")
                    }
                }
            }
            .padding(24)
            .frame(maxWidth: 900, alignment: .leading)
        }
    }

    private func contract(_ title: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
            Text(title + ": " + text)
        }
        .font(.caption)
    }
}

public struct YouTubeEmbedView: NSViewRepresentable {
    let videoID: String

    public func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.mediaTypesRequiringUserActionForPlayback = []
        let view = WKWebView(frame: .zero, configuration: config)
        view.setValue(false, forKey: "drawsBackground")
        return view
    }

    public func updateNSView(_ webView: WKWebView, context: Context) {
        let html = """
        <!doctype html><html><head><meta name='viewport' content='width=device-width,initial-scale=1'></head>
        <body style='margin:0;background:#000;overflow:hidden'>
        <iframe width='100%' height='100%' src='https://www.youtube.com/embed/\(videoID)?playsinline=1&rel=0' frameborder='0' allow='accelerometer; autoplay; clipboard-write; encrypted-media; gyroscope; picture-in-picture' allowfullscreen></iframe>
        </body></html>
        """
        if webView.url == nil {
            webView.loadHTMLString(html, baseURL: URL(string: "https://www.youtube.com"))
        }
    }
}

private struct EmptyState: View {
    let title: String
    let icon: String
    let message: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon).font(.system(size: 34)).foregroundStyle(.secondary)
            Text(title).font(.headline)
            Text(message).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 380)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }
}

private func scorePill(_ label: String, _ score: Double) -> some View {
    Text("\(label) \(Int(score.rounded()))")
        .font(.caption2.weight(.semibold))
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(.secondary.opacity(0.1))
        .clipShape(Capsule())
}

private func formatDuration(_ seconds: Double) -> String {
    let total = max(0, Int(seconds.rounded()))
    if total >= 3600 { return String(format: "%d:%02d:%02d", total / 3600, (total % 3600) / 60, total % 60) }
    return String(format: "%d:%02d", total / 60, total % 60)
}

private func formatTime(_ seconds: Double) -> String { formatDuration(seconds) }
private func formatCount(_ value: Int) -> String {
    if value >= 1_000_000 { return String(format: "%.1f Mio.", Double(value) / 1_000_000) }
    if value >= 1_000 { return String(format: "%.1f Tsd.", Double(value) / 1_000) }
    return String(value)
}
