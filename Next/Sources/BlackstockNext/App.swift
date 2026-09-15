import SwiftUI
import UniformTypeIdentifiers
import AppKit
import AVKit
import WebKit

@main
struct BlackstockNextApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
                .frame(minWidth: 1120, minHeight: 760)
        }
        .commands {
            CommandGroup(after: .newItem) {
                Button("Schneiden öffnen") {
                    NotificationCenter.default.post(name: .blackstockOpenCut, object: nil)
                }
                .keyboardShortcut("e", modifiers: [.command])
            }
        }
    }
}

extension Notification.Name {
    static let blackstockOpenCut = Notification.Name("blackstock.open-cut")
}

@MainActor
final class AppModel: ObservableObject {
    enum Section: String, CaseIterable, Identifiable {
        case dashboard = "Dashboard"
        case trends = "Trends"
        case cut = "Schneiden"
        case content = "Content"
        case analytics = "Analytics"
        case channel = "Kanal"
        var id: String { rawValue }
    }

    enum OutputFormat: String, CaseIterable, Identifiable {
        case auto = "Automatisch"
        case short = "Short 9:16"
        case landscape = "Video 16:9"
        var id: String { rawValue }
    }

    enum TrendSort: String, CaseIterable, Identifiable {
        case channelFit = "Für meinen Kanal"
        case momentum = "Momentum"
        case newest = "Neu"
        var id: String { rawValue }
    }

    @Published var section: Section = .dashboard
    @Published var sourceURL: URL?
    @Published var sourceProbe: SourceProbe?
    @Published var rightsConfirmed = false
    @Published var captionsEnabled = true
    @Published var captionStyle: CaptionStyle = .clean
    @Published var outputFormat: OutputFormat = .auto
    @Published var qualityDecision: QualityDecision?
    @Published var status = "Bereit"
    @Published var isWorking = false
    @Published var workProgress = 0.0
    @Published var transcriptText = ""
    @Published var transcriptWords: [TranscriptWord] = []
    @Published var clipEvaluations: [ClipEvaluation] = []
    @Published var selectedClipID: UUID?
    @Published var channelSnapshot: YouTubeChannelSnapshot?
    @Published var channelDNA: ChannelDNA?
    @Published var opportunities: [Opportunity] = []
    @Published var selectedOpportunityID: String?
    @Published var trendSort: TrendSort = .channelFit
    @Published var trendSearch = ""
    @Published var playlists: [YouTubePlaylist] = []
    @Published var analytics: AnalyticsSummary?
    @Published var publishingProgress: PublishingProgress?
    @Published var alertMessage: String?

    let projectStore = ProjectStore()
    let oauth = GoogleOAuthService()

    private let inspector = LocalMediaInspector()
    private let qualityPolicy = MassMarketQualityPolicy()
    private let speech = SpeechTranscriptionService()
    private let generator = ClipCandidateGenerator()
    private let clipEngine = ClipIntelligenceEngine()
    private let captionEngine = CaptionEngine()
    private let renderService = HighQualityRenderService()
    private let dataService = YouTubeDataService()
    private let analyticsService = YouTubeAnalyticsService()
    private let publisher = PublishingCoordinator()
    private var didBootstrap = false

    var activeProject: BlackstockProject? { projectStore.selected }
    var selectedClip: ClipCandidate? {
        if let selectedClipID,
           let found = clipEvaluations.first(where: { $0.candidate.id == selectedClipID })?.candidate { return found }
        return activeProject?.selectedClip
    }
    var selectedOpportunity: Opportunity? {
        guard let selectedOpportunityID else { return filteredOpportunities.first }
        return opportunities.first(where: { $0.id == selectedOpportunityID }) ?? filteredOpportunities.first
    }
    var oauthConfigured: Bool { GoogleOAuthCredentials.current() != nil }
    var youtubeConnected: Bool { oauth.connected }
    var channelName: String { channelSnapshot?.identity.name ?? "Kein Kanal verbunden" }
    var channelTopic: String { channelDNA?.primaryTopic ?? "Kanal-DNA wird nach Verbindung automatisch gelernt" }
    var activeRenderedURL: URL? {
        guard let path = activeProject?.renderedPath else { return nil }
        return URL(fileURLWithPath: path)
    }

    var filteredOpportunities: [Opportunity] {
        var list = opportunities
        let query = trendSearch.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !query.isEmpty {
            list = list.filter { ($0.title + " " + $0.channelTitle + " " + $0.description).lowercased().contains(query) }
        }
        switch trendSort {
        case .channelFit: list.sort { $0.score > $1.score }
        case .momentum: list.sort { $0.momentum > $1.momentum }
        case .newest: list.sort { $0.publishedAt > $1.publishedAt }
        }
        return list
    }

    func bootstrap() async {
        guard !didBootstrap else { return }
        didBootstrap = true
        if let project = projectStore.selected { await restore(project) }
        if oauth.connected, oauthConfigured { await refreshChannelData(showErrors: false) }
    }

    func importOAuthClient(_ url: URL) async {
        do {
            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }
            try oauth.importCredentials(Data(contentsOf: url))
            status = "YouTube-Konfiguration gespeichert"
            objectWillChange.send()
        } catch { show(error) }
    }

    func connectYouTube() async {
        guard let credentials = GoogleOAuthCredentials.current() else {
            alertMessage = "Für die echte YouTube-Verbindung braucht Blackstock eine Google OAuth Desktop-Konfiguration. Du kannst sie im Kanal-Bereich direkt importieren."
            return
        }
        isWorking = true
        status = "Google-Anmeldung wird geöffnet …"
        defer { isWorking = false }
        do {
            try await oauth.connect(credentials: credentials)
            try await loadChannelData()
            status = "YouTube verbunden"
        } catch { show(error) }
    }

    func disconnectYouTube() {
        oauth.disconnect()
        channelSnapshot = nil
        channelDNA = nil
        opportunities = []
        playlists = []
        analytics = nil
        status = "YouTube getrennt"
    }

    func refreshChannelData(showErrors: Bool = true) async {
        guard youtubeConnected, oauthConfigured else { return }
        isWorking = true
        status = "Kanal wird aktualisiert …"
        defer { isWorking = false }
        do {
            try await loadChannelData()
            status = "Kanal aktuell"
        } catch {
            if showErrors { show(error) }
        }
    }

    private func loadChannelData() async throws {
        guard let credentials = GoogleOAuthCredentials.current() else { throw YouTubeUploadError(message: "Google OAuth ist noch nicht konfiguriert.") }
        let token = try await oauth.accessToken(credentials: credentials)
        let snapshot = try await dataService.myChannel(accessToken: token)
        async let videosTask = dataService.channelVideos(uploadsPlaylistID: snapshot.uploadsPlaylistID, accessToken: token, maximum: 100)
        async let playlistsTask = dataService.playlists(accessToken: token)
        let videos = try await videosTask
        let channelPlaylists = try await playlistsTask
        var identity = snapshot.identity
        if identity.language.isEmpty { identity.language = "de" }
        let dna = ChannelDNAEngine().build(identity: identity, videos: videos)
        channelSnapshot = snapshot
        channelDNA = dna
        playlists = channelPlaylists
        await refreshTrends(showErrors: false)
        await refreshAnalytics(showErrors: false)
    }

    func refreshTrends(showErrors: Bool = true) async {
        guard let dna = channelDNA else {
            if showErrors { alertMessage = "Verbinde zuerst deinen YouTube-Kanal, damit Trends zur Channel DNA passen." }
            return
        }
        guard let credentials = GoogleOAuthCredentials.current(), youtubeConnected else { return }
        isWorking = true
        status = "Markt wird analysiert …"
        defer { isWorking = false }
        do {
            let token = try await oauth.accessToken(credentials: credentials)
            let result = try await dataService.popular(regionCode: "DE", dna: dna, accessToken: token)
            opportunities = result
            selectedOpportunityID = result.first?.id
            status = "Chancen aktualisiert"
        } catch {
            if showErrors { show(error) }
        }
    }

    func refreshAnalytics(showErrors: Bool = true) async {
        guard let credentials = GoogleOAuthCredentials.current(), youtubeConnected else { return }
        do {
            let token = try await oauth.accessToken(credentials: credentials)
            analytics = try await analyticsService.summary(days: 28, accessToken: token)
        } catch {
            if showErrors { show(error) }
        }
    }

    func inspect(_ url: URL) async {
        sourceURL = url
        sourceProbe = nil
        transcriptText = ""
        transcriptWords = []
        clipEvaluations = []
        selectedClipID = nil
        rightsConfirmed = false
        qualityDecision = nil
        status = "Quelle wird geprüft …"
        isWorking = true
        defer { isWorking = false }
        do {
            sourceProbe = try await inspector.probe(url: url)
            _ = projectStore.create(sourceURL: url, channelID: channelSnapshot?.identity.id)
            objectWillChange.send()
            refreshQuality()
            status = "Quelle bereit"
        } catch {
            sourceProbe = nil
            qualityDecision = .init(action: .block, messages: [error.localizedDescription])
            status = "Quelle nicht verwendbar"
            show(error)
        }
    }

    func setRights(_ value: Bool) {
        rightsConfirmed = value
        if var project = activeProject {
            project.rightsConfirmed = value
            commit(project)
        }
        refreshQuality()
    }

    func analyzeSource() async {
        guard let sourceURL, let probe = sourceProbe else { alertMessage = "Wähle zuerst eine Videodatei."; return }
        isWorking = true
        workProgress = 0.08
        status = "Tonspur wird transkribiert …"
        defer { isWorking = false }
        do {
            let language = channelDNA?.language ?? activeProject?.publication.defaultLanguage ?? "de"
            let transcription = try await speech.transcribe(fileURL: sourceURL, language: language)
            transcriptWords = transcription.words
            transcriptText = transcription.fullText
            workProgress = 0.48
            status = "Beste Momente werden bewertet …"
            let target = targetDurationRange()
            let candidates = generator.generate(words: transcription.words, preferredDuration: target, sourceDuration: probe.duration)
            let ranked = clipEngine.rank(candidates, targetDuration: target)
            guard let best = ranked.first else { throw YouTubeUploadError(message: "In dieser Quelle wurde noch kein ausreichend vollständiger Clip-Kandidat erkannt.") }
            clipEvaluations = Array(ranked.prefix(18))
            selectedClipID = best.candidate.id
            let captions = captionEngine.cues(from: transcription.words)
            let captionReport = captionEngine.qualityReport(cues: captions, videoDuration: probe.duration)
            qualityDecision = qualityPolicy.decide(captions: captionsEnabled ? captionReport : nil, source: probe, rights: RightsPolicy().decision(for: .init(kind: .localLicensed, userConfirmedRights: rightsConfirmed)))
            if var project = activeProject {
                project.selectedClip = best.candidate
                project.captions = captionsEnabled ? captions : []
                project.captionStyle = captionStyle
                project.stage = .analyzed
                project.lastError = nil
                commit(project)
            }
            workProgress = 1
            status = "Analyse fertig · \(clipEvaluations.count) starke Varianten"
        } catch {
            status = "Analyse fehlgeschlagen"
            show(error)
        }
    }

    func selectClip(_ evaluation: ClipEvaluation) {
        selectedClipID = evaluation.candidate.id
        if var project = activeProject {
            project.selectedClip = evaluation.candidate
            commit(project)
        }
    }

    func setCaptionStyle(_ style: CaptionStyle) {
        captionStyle = style
        if var project = activeProject {
            project.captionStyle = style
            commit(project)
        }
    }

    func render() async {
        guard rightsConfirmed else { alertMessage = "Bestätige vor dem lokalen Export, dass du die Datei für diesen Zweck verwenden darfst."; return }
        guard let sourceURL, let probe = sourceProbe, let clip = selectedClip else { alertMessage = "Analysiere die Quelle und wähle zuerst einen Clip."; return }
        isWorking = true
        workProgress = 0.08
        status = "High-Quality-Export wird vorbereitet …"
        defer { isWorking = false }
        do {
            let output = try exportURL(for: activeProject?.id ?? UUID())
            let portrait: Bool
            switch outputFormat {
            case .short: portrait = true
            case .landscape: portrait = false
            case .auto: portrait = clip.duration <= 90
            }
            let spec = ProductionQualityDefaults().exportSpec(for: probe, portrait: portrait, captions: captionsEnabled)
            let captions = captionsEnabled ? (activeProject?.captions ?? []) : []
            workProgress = 0.22
            status = "Video wird einmalig in hoher Qualität gerendert …"
            let result = try await renderService.render(sourceURL: sourceURL, clip: clip, spec: spec, captions: captions, captionStyle: captionStyle, outputURL: output)
            guard result.quality.passes else {
                throw YouTubeUploadError(message: result.quality.errors.joined(separator: " ").isEmpty ? "Der technische Exportcheck ist fehlgeschlagen." : result.quality.errors.joined(separator: " "))
            }
            if var project = activeProject {
                project.renderedPath = result.outputURL.path
                project.stage = .rendered
                project.lastError = nil
                commit(project)
            }
            workProgress = 1
            status = "Video fertig · technischer Exportcheck bestanden"
            section = .content
        } catch {
            if var project = activeProject { project.stage = .failed; project.lastError = error.localizedDescription; commit(project) }
            status = "Export fehlgeschlagen"
            show(error)
        }
    }

    func loadProject(_ id: UUID) async {
        projectStore.selectedProjectID = id
        objectWillChange.send()
        guard let project = projectStore.selected else { return }
        await restore(project)
    }

    private func restore(_ project: BlackstockProject) async {
        let url = URL(fileURLWithPath: project.sourcePath)
        sourceURL = url
        rightsConfirmed = project.rightsConfirmed
        captionStyle = project.captionStyle
        selectedClipID = project.selectedClip?.id
        if !FileManager.default.fileExists(atPath: url.path) {
            sourceProbe = nil
            qualityDecision = .init(action: .block, messages: ["Die ursprüngliche Quelldatei wurde verschoben oder gelöscht."])
            return
        }
        do {
            sourceProbe = try await inspector.probe(url: url)
            refreshQuality()
        } catch {
            sourceProbe = nil
            show(error)
        }
    }

    func refreshQuality() {
        qualityDecision = qualityPolicy.decide(
            captions: nil,
            source: sourceProbe,
            rights: RightsPolicy().decision(for: .init(kind: .localLicensed, userConfirmedRights: rightsConfirmed))
        )
    }

    func setPublicationTitle(_ value: String) { mutatePublication { $0.title = value } }
    func setPublicationDescription(_ value: String) { mutatePublication { $0.description = value } }
    func setPublicationTags(_ value: String) { mutatePublication { $0.tags = value.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty } } }
    func setPublicationPrivacy(_ value: PublicationSettings.Privacy) { mutatePublication { $0.privacy = value } }
    func setMadeForKids(_ value: Bool) { mutatePublication { $0.madeForKids = value } }
    func setLanguage(_ value: String) { mutatePublication { $0.defaultLanguage = value } }
    func setPlaylist(_ value: String?) { mutatePublication { $0.playlistID = value } }
    func setSchedule(_ value: Date?) { mutatePublication { $0.scheduledAt = value } }
    func setThumbnail(_ url: URL?) {
        guard let url else { mutatePublication { $0.thumbnailPath = nil }; return }
        do {
            let size = ((try FileManager.default.attributesOfItem(atPath: url.path)[.size]) as? NSNumber)?.intValue ?? 0
            guard size <= 2 * 1024 * 1024 else { throw YouTubeUploadError(message: "YouTube-Thumbnails dürfen höchstens 2 MB groß sein.") }
            mutatePublication { $0.thumbnailPath = url.path }
        } catch { show(error) }
    }

    func packagingQuality() -> PackagingQuality? {
        guard let project = activeProject else { return nil }
        let title = project.publication.title
        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        let promise = project.selectedClip?.transcript.prefix(140).description ?? title
        let concept = PackagingConcept(angle: .curiosity, title: title, thumbnailPromise: project.publication.thumbnailPath == nil ? "" : "Visuelles Thumbnail", viewerPromise: promise)
        return PackagingQualityEngine().evaluate(concept)
    }

    func publishActiveProject() async {
        guard var project = activeProject, project.renderedPath != nil else { alertMessage = "Exportiere den Clip zuerst."; return }
        guard let credentials = GoogleOAuthCredentials.current(), youtubeConnected else { alertMessage = "Verbinde zuerst den Zielkanal im Kanal-Bereich."; return }
        guard !project.publication.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { alertMessage = "Der YouTube-Titel darf nicht leer sein."; return }
        isWorking = true
        project.stage = .uploading
        project.lastError = nil
        commit(project)
        status = "YouTube-Upload wird vorbereitet …"
        defer { isWorking = false }
        do {
            let token = try await oauth.accessToken(credentials: credentials)
            let result = try await publisher.publish(
                project: project,
                accessToken: token,
                onRecovery: { [weak self] recovery in
                    Task { @MainActor in self?.saveRecovery(recovery) }
                },
                onProgress: { [weak self] progress in
                    Task { @MainActor in
                        self?.publishingProgress = progress
                        self?.workProgress = progress.fraction
                        self?.status = progress.detail
                    }
                }
            )
            guard var finished = activeProject else { return }
            finished.stage = .published
            finished.youtubeVideoID = result.0.videoID
            finished.uploadRecovery = result.1
            finished.lastError = nil
            commit(finished)
            publishingProgress = .init(phase: .completed, fraction: 1, detail: "Veröffentlicht")
            status = "Auf YouTube veröffentlicht"
        } catch {
            if var failed = activeProject { failed.stage = .failed; failed.lastError = error.localizedDescription; commit(failed) }
            status = "Upload unterbrochen · Fortschritt bleibt gespeichert"
            show(error)
        }
    }

    private func saveRecovery(_ recovery: UploadRecoveryState) {
        guard var project = activeProject else { return }
        project.uploadRecovery = recovery
        project.stage = .uploading
        commit(project)
    }

    func revealRendered() {
        guard let url = activeRenderedURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    func openPublished(_ project: BlackstockProject? = nil) {
        let value = project ?? activeProject
        guard let id = value?.youtubeVideoID, let url = URL(string: "https://www.youtube.com/watch?v=\(id)") else { return }
        NSWorkspace.shared.open(url)
    }

    func openOpportunity(_ opportunity: Opportunity) {
        guard let url = URL(string: "https://www.youtube.com/watch?v=\(opportunity.videoID)") else { return }
        NSWorkspace.shared.open(url)
    }

    func deleteProject(_ id: UUID) {
        projectStore.remove(id)
        objectWillChange.send()
    }

    private func mutatePublication(_ mutation: (inout PublicationSettings) -> Void) {
        guard var project = activeProject else { return }
        mutation(&project.publication)
        commit(project)
    }

    private func commit(_ project: BlackstockProject) {
        projectStore.update(project)
        objectWillChange.send()
    }

    private func targetDurationRange() -> ClosedRange<Double> {
        switch outputFormat {
        case .short: return 18...58
        case .landscape: return 45...90
        case .auto: return 24...75
        }
    }

    private func exportURL(for projectID: UUID) throws -> URL {
        let base = try FileManager.default.url(for: .moviesDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        let directory = base.appendingPathComponent("Blackstock Exports", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("Blackstock-\(projectID.uuidString.prefix(8))-\(Int(Date().timeIntervalSince1970)).mp4")
    }

    private func show(_ error: Error) {
        alertMessage = error.localizedDescription
    }
}

struct RootView: View {
    @StateObject private var model = AppModel()

    var body: some View {
        NavigationSplitView {
            List(AppModel.Section.allCases, selection: $model.section) { item in
                Label(item.rawValue, systemImage: icon(item)).tag(item)
            }
            .safeAreaInset(edge: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("BLACKSTOCK").font(.system(size: 21, weight: .black))
                    Text(model.youtubeConnected ? model.channelName : "Source-first YouTube workflow")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .navigationSplitViewColumnWidth(210)
        } detail: {
            Group {
                switch model.section {
                case .dashboard: DashboardView(model: model)
                case .trends: TrendsView(model: model)
                case .cut: CutView(model: model)
                case .content: ContentView(model: model)
                case .analytics: AnalyticsView(model: model)
                case .channel: ChannelView(model: model)
                }
            }
            .padding(28)
            .overlay(alignment: .bottom) {
                if model.isWorking {
                    HStack(spacing: 12) {
                        ProgressView(value: model.workProgress > 0 ? model.workProgress : nil)
                            .frame(width: 120)
                        Text(model.status).font(.caption).foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 14).padding(.vertical, 9)
                    .background(.regularMaterial, in: Capsule())
                    .padding(18)
                }
            }
        }
        .task { await model.bootstrap() }
        .onReceive(NotificationCenter.default.publisher(for: .blackstockOpenCut)) { _ in model.section = .cut }
        .alert("Blackstock", isPresented: Binding(get: { model.alertMessage != nil }, set: { if !$0 { model.alertMessage = nil } })) {
            Button("OK", role: .cancel) { model.alertMessage = nil }
        } message: {
            Text(model.alertMessage ?? "")
        }
    }

    private func icon(_ section: AppModel.Section) -> String {
        switch section {
        case .dashboard: return "square.grid.2x2"
        case .trends: return "chart.line.uptrend.xyaxis"
        case .cut: return "scissors"
        case .content: return "play.rectangle.on.rectangle"
        case .analytics: return "chart.bar"
        case .channel: return "person.crop.rectangle.stack"
        }
    }
}

struct PageHeader: View {
    let title: String
    let subtitle: String
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.largeTitle.bold())
            Text(subtitle).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct DashboardView: View {
    @ObservedObject var model: AppModel
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                PageHeader(title: "Dashboard", subtitle: "Eine klare nächste Aktion statt Tool-Chaos.")
                channelCard
                if let opportunity = model.filteredOpportunities.first { opportunityCard(opportunity) }
                else if model.youtubeConnected {
                    GroupBox("Nächste Chance") { Text("Trends werden nach deiner Channel DNA gefiltert. Aktualisiere den Markt, um neue Chancen zu laden.").frame(maxWidth: .infinity, alignment: .leading) }
                }
                if let project = model.activeProject { activeProjectCard(project) }
            }
        }
    }

    private var channelCard: some View {
        GroupBox("Aktiver Kanal") {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 7) {
                    Text(model.channelName).font(.title2.bold())
                    Text(model.channelTopic).foregroundStyle(.secondary)
                }
                Spacer()
                if model.youtubeConnected { Button("Aktualisieren") { Task { await model.refreshChannelData() } } }
                else { Button("Kanal verbinden") { model.section = .channel }.buttonStyle(.borderedProminent) }
            }.frame(maxWidth: .infinity)
        }
    }

    private func opportunityCard(_ opportunity: Opportunity) -> some View {
        GroupBox("Beste aktuelle Opportunity") {
            HStack(alignment: .top, spacing: 18) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(opportunity.title).font(.title3.bold()).lineLimit(2)
                    Text(opportunity.channelTitle).foregroundStyle(.secondary)
                    HStack(spacing: 14) {
                        Label("\(Int(opportunity.score)) Opportunity", systemImage: "sparkles")
                        Text("Fit \(Int(opportunity.relevance * 100)) %")
                        Text("Momentum \(Int(opportunity.momentum * 100)) %")
                    }.font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Ansehen") { model.selectedOpportunityID = opportunity.id; model.section = .trends }
                    .buttonStyle(.borderedProminent)
            }.frame(maxWidth: .infinity)
        }
    }

    private func activeProjectCard(_ project: BlackstockProject) -> some View {
        GroupBox("Aktives Projekt") {
            HStack {
                VStack(alignment: .leading, spacing: 6) {
                    Text(URL(fileURLWithPath: project.sourcePath).lastPathComponent).font(.headline)
                    Text(project.stage.rawValue).foregroundStyle(.secondary)
                    if let error = project.lastError { Text(error).font(.caption).foregroundStyle(.secondary).lineLimit(2) }
                }
                Spacer()
                Button(project.renderedPath == nil ? "Weiter schneiden" : "Zu Content") { model.section = project.renderedPath == nil ? .cut : .content }
            }.frame(maxWidth: .infinity)
        }
    }
}

struct TrendsView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            PageHeader(title: "Trends", subtitle: "Relevante Chancen für den aktiven Kanal, nicht einfach die größten Videos.")
            if !model.youtubeConnected {
                emptyState(title: "YouTube-Kanal verbinden", detail: "Blackstock braucht deinen Kanal, um Marktchancen gegen deine Channel DNA zu bewerten.", button: "Zum Kanal") { model.section = .channel }
            } else {
                controls
                HSplitView {
                    ScrollView {
                        LazyVStack(spacing: 10) {
                            ForEach(model.filteredOpportunities) { opportunity in
                                OpportunityRow(opportunity: opportunity, selected: model.selectedOpportunity?.id == opportunity.id) {
                                    model.selectedOpportunityID = opportunity.id
                                }
                            }
                        }.padding(.trailing, 8)
                    }.frame(minWidth: 390)
                    VStack(alignment: .leading, spacing: 12) {
                        if let opportunity = model.selectedOpportunity {
                            YouTubeEmbedView(videoID: opportunity.videoID)
                                .frame(minHeight: 320)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                            Text(opportunity.title).font(.title3.bold()).lineLimit(2)
                            HStack { Text("Channel Fit \(Int(opportunity.relevance * 100)) %"); Text("Momentum \(Int(opportunity.momentum * 100)) %"); Spacer() }
                                .font(.caption).foregroundStyle(.secondary)
                            Text("Blackstock verwendet das YouTube-Video nur als Referenz. Für fremdes YouTube-only Material wird keine lokale Kopie erzeugt.")
                                .font(.caption).foregroundStyle(.secondary)
                            Button("Auf YouTube öffnen / Remix prüfen") { model.openOpportunity(opportunity) }
                                .buttonStyle(.borderedProminent)
                        } else {
                            Text("Keine passenden Chancen geladen.").foregroundStyle(.secondary)
                        }
                        Spacer()
                    }.padding(.leading, 8).frame(minWidth: 430)
                }
            }
        }
    }

    private var controls: some View {
        HStack {
            TextField("Trends durchsuchen", text: $model.trendSearch).textFieldStyle(.roundedBorder).frame(maxWidth: 320)
            Picker("Sortierung", selection: $model.trendSort) { ForEach(AppModel.TrendSort.allCases) { Text($0.rawValue).tag($0) } }.frame(width: 190)
            Spacer()
            Button("Aktualisieren") { Task { await model.refreshTrends() } }
        }
    }
}

struct OpportunityRow: View {
    let opportunity: Opportunity
    let selected: Bool
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 7) {
                Text(opportunity.title).font(.headline).lineLimit(2).multilineTextAlignment(.leading)
                HStack {
                    Text(opportunity.channelTitle).lineLimit(1)
                    Spacer()
                    Text("\(Int(opportunity.score))")
                        .font(.headline.monospacedDigit())
                }.font(.caption).foregroundStyle(.secondary)
                HStack { Text("Fit \(Int(opportunity.relevance * 100)) %"); Text("Momentum \(Int(opportunity.momentum * 100)) %"); Text(formatViews(opportunity.viewCount)) }
                    .font(.caption2).foregroundStyle(.secondary)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(selected ? Color.primary.opacity(0.08) : Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 10))
        }.buttonStyle(.plain)
    }
}

struct CutView: View {
    @ObservedObject var model: AppModel
    @State private var importer = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                PageHeader(title: "Schneiden", subtitle: "Bestehende Quelle → bester Moment → professioneller Export.")
                sourceBox
                if let url = model.sourceURL { VideoPreview(url: url).frame(height: 330).clipShape(RoundedRectangle(cornerRadius: 12)) }
                if !model.clipEvaluations.isEmpty { clipBox }
                qualityBox
                if model.selectedClip != nil { exportBox }
            }
        }
        .fileImporter(isPresented: $importer, allowedContentTypes: [.movie], allowsMultipleSelection: false) { result in
            if case .success(let urls) = result, let url = urls.first { Task { await model.inspect(url) } }
        }
    }

    private var sourceBox: some View {
        GroupBox("Quelle") {
            VStack(alignment: .leading, spacing: 11) {
                HStack {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(model.sourceURL?.lastPathComponent ?? "Noch keine Videodatei gewählt").font(.headline)
                        if let p = model.sourceProbe {
                            Text("\(Int(p.naturalSize.width))×\(Int(p.naturalSize.height)) · \(String(format: "%.2f", p.frameRate)) fps · \(formatDuration(p.duration)) · \(p.hasAudio ? "Audio" : "ohne Audio")")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    Button("Videodatei wählen") { importer = true }
                }
                Toggle("Ich darf diese Datei für den vorgesehenen Zweck verwenden", isOn: Binding(get: { model.rightsConfirmed }, set: model.setRights))
                HStack {
                    Picker("Format", selection: $model.outputFormat) { ForEach(AppModel.OutputFormat.allCases) { Text($0.rawValue).tag($0) } }.frame(width: 210)
                    Toggle("Captions", isOn: $model.captionsEnabled).toggleStyle(.switch)
                    Picker("Caption-Stil", selection: Binding(get: { model.captionStyle }, set: model.setCaptionStyle)) { ForEach(CaptionStyle.allCases, id: \.self) { Text($0.rawValue).tag($0) } }.frame(width: 170)
                    Spacer()
                    Button(model.transcriptText.isEmpty ? "Analysieren" : "Neu analysieren") { Task { await model.analyzeSource() } }
                        .buttonStyle(.borderedProminent)
                        .disabled(model.sourceProbe == nil)
                }
            }.frame(maxWidth: .infinity)
        }
    }

    private var clipBox: some View {
        GroupBox("Beste Momente") {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(Array(model.clipEvaluations.prefix(6))) { evaluation in
                    Button {
                        model.selectClip(evaluation)
                    } label: {
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: model.selectedClipID == evaluation.candidate.id ? "checkmark.circle.fill" : "circle")
                            VStack(alignment: .leading, spacing: 4) {
                                Text(evaluation.candidate.transcript).lineLimit(2).multilineTextAlignment(.leading)
                                Text("\(formatTime(evaluation.candidate.start))–\(formatTime(evaluation.candidate.end)) · \(Int(evaluation.candidate.duration)) s · Qualität \(Int(evaluation.score))")
                                    .font(.caption).foregroundStyle(.secondary)
                                if !evaluation.reasons.isEmpty { Text(evaluation.reasons.joined(separator: " · ")).font(.caption2).foregroundStyle(.secondary) }
                            }
                            Spacer()
                        }
                        .padding(9)
                        .background(model.selectedClipID == evaluation.candidate.id ? Color.primary.opacity(0.07) : Color.clear, in: RoundedRectangle(cornerRadius: 8))
                    }.buttonStyle(.plain)
                }
                DisclosureGroup("Transkript") { Text(model.transcriptText).textSelection(.enabled).padding(.top, 6) }
            }.frame(maxWidth: .infinity)
        }
    }

    @ViewBuilder private var qualityBox: some View {
        if let q = model.qualityDecision {
            GroupBox("Qualität") {
                VStack(alignment: .leading, spacing: 7) {
                    Label(qualityLabel(q.action), systemImage: qualityIcon(q.action)).font(.headline)
                    ForEach(q.messages, id: \.self) { Text($0).font(.caption).foregroundStyle(.secondary) }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var exportBox: some View {
        GroupBox("Fertigstellen") {
            HStack {
                if let clip = model.selectedClip {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Ausgewählter Schnitt").font(.headline)
                        Text("\(formatTime(clip.start))–\(formatTime(clip.end)) · \(Int(clip.duration)) Sekunden").foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Button("High-Quality-Export") { Task { await model.render() } }
                    .buttonStyle(.borderedProminent)
                    .disabled(!model.rightsConfirmed)
            }.frame(maxWidth: .infinity)
        }
    }
}

struct ContentView: View {
    @ObservedObject var model: AppModel
    @State private var thumbnailImporter = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                PageHeader(title: "Content", subtitle: "Projekte, Exporte und echte YouTube-Veröffentlichung.")
                projectList
                if let project = model.activeProject { projectDetail(project) }
            }
        }
        .fileImporter(isPresented: $thumbnailImporter, allowedContentTypes: [.image], allowsMultipleSelection: false) { result in
            if case .success(let urls) = result, let url = urls.first { model.setThumbnail(url) }
        }
    }

    private var projectList: some View {
        GroupBox("Projekte") {
            VStack(spacing: 8) {
                if model.projectStore.projects.isEmpty { Text("Noch keine Projekte.").foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading) }
                ForEach(model.projectStore.projects.prefix(12)) { project in
                    HStack {
                        Button {
                            Task { await model.loadProject(project.id) }
                        } label: {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(URL(fileURLWithPath: project.sourcePath).lastPathComponent).lineLimit(1)
                                Text(project.stage.rawValue + " · " + project.updatedAt.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(.secondary)
                            }.frame(maxWidth: .infinity, alignment: .leading)
                        }.buttonStyle(.plain)
                        if project.youtubeVideoID != nil { Button("YouTube") { model.openPublished(project) } }
                    }
                    Divider()
                }
            }
        }
    }

    private func projectDetail(_ project: BlackstockProject) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            if let rendered = project.renderedPath, FileManager.default.fileExists(atPath: rendered) {
                GroupBox("Fertiges Video") {
                    VStack(alignment: .leading, spacing: 10) {
                        VideoPreview(url: URL(fileURLWithPath: rendered)).frame(height: 300).clipShape(RoundedRectangle(cornerRadius: 10))
                        HStack { Text(URL(fileURLWithPath: rendered).lastPathComponent).font(.caption).foregroundStyle(.secondary); Spacer(); Button("Im Finder zeigen") { model.revealRendered() } }
                    }
                }
                publishingBox(project)
            } else {
                GroupBox("Noch kein Export") {
                    HStack { Text("Öffne das Projekt im Schnitt und exportiere zuerst das Ergebnis.").foregroundStyle(.secondary); Spacer(); Button("Zum Schnitt") { model.section = .cut } }
                }
            }
        }
    }

    private func publishingBox(_ project: BlackstockProject) -> some View {
        GroupBox("YouTube veröffentlichen") {
            VStack(alignment: .leading, spacing: 12) {
                TextField("Titel", text: Binding(get: { model.activeProject?.publication.title ?? "" }, set: model.setPublicationTitle))
                TextEditor(text: Binding(get: { model.activeProject?.publication.description ?? "" }, set: model.setPublicationDescription))
                    .frame(minHeight: 90).overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.25)))
                TextField("Tags, durch Kommas getrennt", text: Binding(get: { model.activeProject?.publication.tags.joined(separator: ", ") ?? "" }, set: model.setPublicationTags))
                HStack {
                    Picker("Sichtbarkeit", selection: Binding(get: { model.activeProject?.publication.privacy ?? .private }, set: model.setPublicationPrivacy)) {
                        Text("Privat").tag(PublicationSettings.Privacy.private)
                        Text("Nicht gelistet").tag(PublicationSettings.Privacy.unlisted)
                        Text("Öffentlich").tag(PublicationSettings.Privacy.public)
                    }.frame(width: 220)
                    Toggle("Für Kinder", isOn: Binding(get: { model.activeProject?.publication.madeForKids ?? false }, set: model.setMadeForKids))
                    Spacer()
                }
                HStack {
                    Picker("Playlist", selection: Binding(get: { model.activeProject?.publication.playlistID ?? "" }, set: { model.setPlaylist($0.isEmpty ? nil : $0) })) {
                        Text("Keine Playlist").tag("")
                        ForEach(model.playlists) { Text($0.title).tag($0.id) }
                    }.frame(width: 280)
                    Button(project.publication.thumbnailPath == nil ? "Thumbnail wählen" : "Thumbnail ändern") { thumbnailImporter = true }
                    if project.publication.thumbnailPath != nil { Label("gesetzt", systemImage: "checkmark.circle.fill").font(.caption).foregroundStyle(.secondary) }
                    Spacer()
                }
                Toggle("Veröffentlichung planen", isOn: Binding(get: { model.activeProject?.publication.scheduledAt != nil }, set: { model.setSchedule($0 ? Date().addingTimeInterval(3600) : nil) }))
                if let scheduled = model.activeProject?.publication.scheduledAt {
                    DatePicker("Zeitpunkt", selection: Binding(get: { scheduled }, set: { model.setSchedule($0) }), in: Date()..., displayedComponents: [.date, .hourAndMinute])
                }
                if let quality = model.packagingQuality() {
                    DisclosureGroup("Packaging-Check · \(Int(quality.score))/100") {
                        if quality.issues.isEmpty { Text("Titel und Packaging-Grundstruktur sind technisch schlüssig.").foregroundStyle(.secondary) }
                        else { ForEach(quality.issues, id: \.self) { Label($0, systemImage: "exclamationmark.circle").font(.caption) } }
                    }
                }
                if let progress = model.publishingProgress {
                    ProgressView(value: progress.fraction) { Text(progress.detail) }
                }
                HStack {
                    if project.youtubeVideoID != nil { Button("Auf YouTube ansehen") { model.openPublished() } }
                    Spacer()
                    Button(project.uploadRecovery == nil ? "Auf YouTube veröffentlichen" : "Upload fortsetzen") { Task { await model.publishActiveProject() } }
                        .buttonStyle(.borderedProminent)
                        .disabled(!model.youtubeConnected)
                }
                if let error = project.lastError { Text(error).font(.caption).foregroundStyle(.secondary) }
            }.frame(maxWidth: .infinity)
        }
    }
}

struct AnalyticsView: View {
    @ObservedObject var model: AppModel
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                PageHeader(title: "Analytics", subtitle: "Wenige Kennzahlen, die zur nächsten Entscheidung führen.")
                if !model.youtubeConnected {
                    emptyState(title: "Noch keine Kanaldaten", detail: "Verbinde YouTube, damit Blackstock echte Analytics statt Schätzwerte verwendet.", button: "Kanal verbinden") { model.section = .channel }
                } else if let summary = model.analytics {
                    HStack(spacing: 12) {
                        MetricCard(title: "Views · 28 Tage", value: formatViews(summary.views))
                        MetricCard(title: "Watchtime", value: "\(Int(summary.estimatedMinutesWatched / 60)) h")
                        MetricCard(title: "Ø Wiedergabe", value: formatDuration(summary.averageViewDuration))
                        MetricCard(title: "Neue Abos", value: "+\(summary.subscribersGained)")
                    }
                    GroupBox("Nächste Entscheidung") {
                        VStack(alignment: .leading, spacing: 7) {
                            if let best = model.filteredOpportunities.first {
                                Text("Aktuell stärkste Marktchance").font(.headline)
                                Text(best.title)
                                Text("Channel Fit \(Int(best.relevance * 100)) % · Momentum \(Int(best.momentum * 100)) %").font(.caption).foregroundStyle(.secondary)
                            } else {
                                Text("Aktualisiere Trends, damit Analytics und Marktchance zusammen bewertet werden.").foregroundStyle(.secondary)
                            }
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }
                    Button("Analytics aktualisieren") { Task { await model.refreshAnalytics() } }
                } else {
                    ProgressView("Analytics werden geladen …")
                }
            }
        }
    }
}

struct ChannelView: View {
    @ObservedObject var model: AppModel
    @State private var oauthImporter = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                PageHeader(title: "Kanal", subtitle: "Eine feste Channel DNA für Trends, Schnitt, Publishing und Lernen.")
                GroupBox("YouTube-Verbindung") {
                    VStack(alignment: .leading, spacing: 11) {
                        if !model.oauthConfigured {
                            Text("Die App enthält keine erfundene oder fremde Google-Client-ID. Importiere einmal eine Google OAuth Desktop-JSON; sie wird sicher im macOS-Keychain gespeichert.")
                                .foregroundStyle(.secondary)
                            Button("Google OAuth JSON importieren") { oauthImporter = true }.buttonStyle(.borderedProminent)
                        } else if !model.youtubeConnected {
                            Text("Google OAuth ist konfiguriert. Verbinde jetzt den YouTube-Kanal.").foregroundStyle(.secondary)
                            HStack { Button("Mit YouTube verbinden") { Task { await model.connectYouTube() } }.buttonStyle(.borderedProminent); Button("Andere OAuth-Konfiguration") { oauthImporter = true } }
                        } else if let channel = model.channelSnapshot {
                            HStack(alignment: .top) {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(channel.identity.name).font(.title2.bold())
                                    Text(model.channelTopic).foregroundStyle(.secondary)
                                    Text("\(formatViews(channel.subscriberCount)) Abonnenten · \(formatViews(channel.videoCount)) Videos · \(formatViews(channel.viewCount)) Kanalaufrufe")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Button("Aktualisieren") { Task { await model.refreshChannelData() } }
                                Button("Trennen", role: .destructive) { model.disconnectYouTube() }
                            }
                        }
                    }.frame(maxWidth: .infinity)
                }
                if let dna = model.channelDNA {
                    GroupBox("Channel DNA") {
                        VStack(alignment: .leading, spacing: 8) {
                            LabeledContent("Hauptthema", value: dna.primaryTopic)
                            LabeledContent("Sprache", value: dna.language)
                            LabeledContent("Gelernte Videos", value: "\(dna.evidenceCount)")
                            LabeledContent("Typische Länge", value: "\(Int(dna.preferredDuration.lowerBound))–\(Int(dna.preferredDuration.upperBound)) s")
                            Text(dna.topicKeywords.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary)
                        }.frame(maxWidth: .infinity)
                    }
                }
                GroupBox("Produktprinzip") {
                    Text("YouTube-only Material bleibt im offiziellen YouTube-Workflow. Lokale Quellen werden nur nach Rechtebestätigung verarbeitet. Quellvideos bleiben lokal; erst ein freigegebener finaler Export wird zu YouTube hochgeladen.")
                        .foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .fileImporter(isPresented: $oauthImporter, allowedContentTypes: [.json], allowsMultipleSelection: false) { result in
            if case .success(let urls) = result, let url = urls.first { Task { await model.importOAuthClient(url) } }
        }
    }
}

struct VideoPreview: View {
    let url: URL
    @State private var player = AVPlayer()
    var body: some View {
        VideoPlayer(player: player)
            .onAppear { player.replaceCurrentItem(with: AVPlayerItem(url: url)) }
            .onChange(of: url) { newURL in player.replaceCurrentItem(with: AVPlayerItem(url: newURL)) }
            .onDisappear { player.pause() }
    }
}

struct YouTubeEmbedView: NSViewRepresentable {
    let videoID: String
    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.allowsAirPlayForMediaPlayback = true
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.setValue(false, forKey: "drawsBackground")
        return view
    }
    func updateNSView(_ webView: WKWebView, context: Context) {
        let html = """
        <html><head><meta name='viewport' content='width=device-width, initial-scale=1.0'></head>
        <body style='margin:0;background:#000;overflow:hidden'>
        <iframe width='100%' height='100%' src='https://www.youtube.com/embed/\(videoID)?playsinline=1' title='YouTube video' frameborder='0' allow='accelerometer; autoplay; clipboard-write; encrypted-media; gyroscope; picture-in-picture; web-share' allowfullscreen></iframe>
        </body></html>
        """
        webView.loadHTMLString(html, baseURL: URL(string: "https://www.youtube.com"))
    }
}

struct MetricCard: View {
    let title: String
    let value: String
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.title2.bold()).monospacedDigit()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 12))
    }
}

func emptyState(title: String, detail: String, button: String, action: @escaping () -> Void) -> some View {
    VStack(spacing: 12) {
        Image(systemName: "sparkles").font(.system(size: 28)).foregroundStyle(.secondary)
        Text(title).font(.title3.bold())
        Text(detail).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 520)
        Button(button, action: action).buttonStyle(.borderedProminent)
    }
    .padding(44)
    .frame(maxWidth: .infinity)
}

func qualityLabel(_ action: QualityDecision.Action) -> String {
    switch action {
    case .pass: return "Bereit"
    case .autoFix: return "Blackstock korrigiert automatisch"
    case .warn: return "Bereit mit Hinweis"
    case .block: return "Aktion erforderlich"
    }
}

func qualityIcon(_ action: QualityDecision.Action) -> String {
    switch action {
    case .pass: return "checkmark.circle.fill"
    case .autoFix: return "wand.and.stars"
    case .warn: return "exclamationmark.circle"
    case .block: return "xmark.octagon"
    }
}

func formatDuration(_ seconds: Double) -> String {
    guard seconds.isFinite else { return "–" }
    let total = Int(max(0, seconds).rounded())
    if total >= 3600 { return String(format: "%d:%02d:%02d", total / 3600, (total / 60) % 60, total % 60) }
    return String(format: "%d:%02d", total / 60, total % 60)
}

func formatTime(_ seconds: Double) -> String { formatDuration(seconds) }

func formatViews(_ value: Int) -> String {
    if value >= 1_000_000 { return String(format: "%.1f Mio.", Double(value) / 1_000_000) }
    if value >= 1_000 { return String(format: "%.1f Tsd.", Double(value) / 1_000) }
    return "\(value)"
}
