import Foundation
import AppKit

@MainActor
final class StudioModel: ObservableObject {
    enum Section: String, CaseIterable, Identifiable {
        case dashboard = "Dashboard"
        case trends = "Trends"
        case cut = "Schneiden"
        case content = "Content"
        case analytics = "Analytics"
        case channel = "Kanal"
        var id: String { rawValue }
    }

    @Published var section: Section = .dashboard
    @Published private(set) var project: BlackstockProject?
    @Published private(set) var projects: [BlackstockProject] = []
    @Published private(set) var sourceProbe: SourceProbe?
    @Published private(set) var clipEvaluations: [ClipEvaluation] = []
    @Published private(set) var transcriptText = ""
    @Published var captionsEnabled = true
    @Published var captionStyle: CaptionStyle = .clean
    @Published var outputFormat: OutputFormatPreference = .automatic
    @Published private(set) var qualityDecision: QualityDecision?

    @Published private(set) var channel: YouTubeChannelSnapshot?
    @Published private(set) var channelDNA: ChannelDNA?
    @Published private(set) var opportunities: [Opportunity] = []
    @Published var selectedOpportunityID: String?
    @Published private(set) var playlists: [YouTubePlaylist] = []
    @Published private(set) var analytics: AnalyticsSummary?

    @Published private(set) var packagingConcepts: [PackagingConcept] = []
    @Published var selectedPackagingID: UUID?
    @Published var trendSearch = ""
    @Published var sortByMomentum = false

    @Published private(set) var isBusy = false
    @Published private(set) var status = "Bereit"
    @Published private(set) var progress: Double = 0
    @Published private(set) var publishingProgress: PublishingProgress?
    @Published var alertMessage: String?

    let store: ProjectStore
    let oauth: GoogleOAuthService

    private let inspector = LocalMediaInspector()
    private let speech = SpeechTranscriptionService()
    private let clipGenerator = ClipCandidateGenerator()
    private let clipEngine = ClipIntelligenceEngine()
    private let captionEngine = CaptionEngine()
    private let qualityPolicy = MassMarketQualityPolicy()
    private let renderService = HighQualityRenderService()
    private let dataService = YouTubeDataService()
    private let analyticsService = YouTubeAnalyticsService()
    private let publisher = PublishingCoordinator()
    private let dnaEngine = ChannelDNAEngine()
    private let formatEngine = FormatRecommendationEngine()
    private let packagingGenerator = PackagingGenerator()
    private let opportunityExplainer = OpportunityExplainer()
    private var bootstrapped = false

    init(store: ProjectStore = ProjectStore(), oauth: GoogleOAuthService = GoogleOAuthService()) {
        self.store = store
        self.oauth = oauth
        projects = store.projects
        if let value = store.selected { applyProjectState(value) }
    }

    var youtubeConnected: Bool { oauth.connected }
    var oauthConfigured: Bool { GoogleOAuthCredentials.current() != nil }
    var channelName: String { channel?.identity.name ?? "Kein Kanal verbunden" }
    var channelTopic: String { channelDNA?.primaryTopic ?? "Channel DNA wird nach Verbindung automatisch gelernt" }
    var sourceURL: URL? { project?.resolvedSourceURL() }
    var renderedURL: URL? {
        guard let path = project?.renderedPath, FileManager.default.fileExists(atPath: path) else { return nil }
        return URL(fileURLWithPath: path)
    }
    var selectedClip: ClipCandidate? { project?.selectedClip }
    var rightsConfirmed: Bool { project?.rightsConfirmed ?? false }
    var publication: PublicationSettings? { project?.publication }

    var filteredOpportunities: [Opportunity] {
        let query = trendSearch.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        var values = query.isEmpty ? opportunities : opportunities.filter {
            ($0.title + " " + $0.channelTitle + " " + $0.description).lowercased().contains(query)
        }
        if sortByMomentum { values.sort { $0.momentum > $1.momentum } }
        else { values.sort { $0.score > $1.score } }
        return values
    }

    var selectedOpportunity: Opportunity? {
        guard let selectedOpportunityID else { return filteredOpportunities.first }
        return opportunities.first(where: { $0.id == selectedOpportunityID }) ?? filteredOpportunities.first
    }

    var formatRecommendation: FormatRecommendation? {
        guard let sourceProbe, let selectedClip else { return nil }
        return formatEngine.recommend(source: sourceProbe, clip: selectedClip)
    }

    var resolvedPortrait: Bool {
        switch outputFormat {
        case .short: return true
        case .video: return false
        case .automatic: return formatRecommendation?.portrait ?? false
        }
    }

    func bootstrap() async {
        guard !bootstrapped else { return }
        bootstrapped = true
        if let project { await inspectProjectSource(project) }
        if youtubeConnected, oauthConfigured { await refreshChannel(showErrors: false) }
    }

    func opportunityReasons(_ opportunity: Opportunity) -> [String] {
        opportunityExplainer.reasons(opportunity)
    }

    func importSource(_ url: URL) async {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        isBusy = true
        progress = 0.05
        status = "Quelle wird geprüft …"
        defer { isBusy = false }
        do {
            let probe = try await inspector.probe(url: url)
            let id = store.create(sourceURL: url, channelID: channel?.identity.id)
            projects = store.projects
            guard let value = projects.first(where: { $0.id == id }) else { return }
            applyProjectState(value)
            sourceProbe = probe
            progress = 1
            status = "Quelle bereit"
            refreshQuality()
            section = .cut
        } catch { fail(error) }
    }

    func selectProject(_ id: UUID) async {
        guard let value = store.projects.first(where: { $0.id == id }) else { return }
        store.select(id)
        applyProjectState(value)
        await inspectProjectSource(value)
    }

    func deleteProject(_ id: UUID) {
        store.remove(id)
        projects = store.projects
        if let selected = store.selected { applyProjectState(selected) }
        else { project = nil; sourceProbe = nil; clipEvaluations = []; transcriptText = "" }
    }

    func setRights(_ value: Bool) {
        mutateProject { $0.rightsConfirmed = value }
        refreshQuality()
    }

    func setCaptionStyle(_ value: CaptionStyle) {
        captionStyle = value
        mutateProject { $0.captionStyle = value }
    }

    func setOutputFormat(_ value: OutputFormatPreference) {
        outputFormat = value
        mutateProject { $0.outputPortrait = value == .automatic ? nil : (value == .short) }
        rerankCandidates()
    }

    func setCaptionsEnabled(_ value: Bool) {
        captionsEnabled = value
        refreshQuality()
    }

    func analyzeSource() async {
        guard let sourceURL, let probe = sourceProbe, project != nil else {
            alertMessage = "Wähle zuerst eine Videodatei."
            return
        }
        isBusy = true
        progress = 0.08
        status = "Tonspur wird transkribiert …"
        let access = sourceURL.startAccessingSecurityScopedResource()
        defer { if access { sourceURL.stopAccessingSecurityScopedResource() }; isBusy = false }
        do {
            let language = channelDNA?.language ?? project?.publication.defaultLanguage ?? "de"
            let transcription = try await speech.transcribe(fileURL: sourceURL, language: language)
            transcriptText = transcription.fullText
            progress = 0.48
            status = "Beste Momente werden bewertet …"
            let candidates = clipGenerator.generate(
                words: transcription.words,
                preferredDuration: targetDurationRange(),
                sourceDuration: probe.duration
            )
            let ranked = clipEngine.rank(candidates, targetDuration: targetDurationRange())
            guard let best = ranked.first else {
                throw YouTubeUploadError(message: "Blackstock konnte keinen vollständigen Clip-Kandidaten finden.")
            }
            let cues = captionEngine.cues(from: transcription.words)
            mutateProject { value in
                value.transcriptWords = transcription.words
                value.transcriptText = transcription.fullText
                value.clipCandidates = ranked.map(\.candidate)
                value.selectedClip = best.candidate
                value.captions = cues
                value.captionStyle = captionStyle
                value.publication.defaultLanguage = transcription.locale.components(separatedBy: "-").first ?? value.publication.defaultLanguage
                value.stage = .analyzed
                value.renderedPath = nil
                value.uploadRecovery = nil
                value.youtubeVideoID = nil
                value.lastError = nil
            }
            clipEvaluations = Array(ranked.prefix(24))
            buildPackaging()
            refreshQuality()
            progress = 1
            status = "\(ranked.count) Momente bewertet · bester Schnitt ausgewählt"
        } catch {
            mutateProject { $0.stage = .failed; $0.lastError = error.localizedDescription }
            fail(error)
        }
    }

    func selectClip(_ evaluation: ClipEvaluation) {
        mutateProject { value in
            value.selectedClip = evaluation.candidate
            value.stage = .edited
            value.renderedPath = nil
            value.uploadRecovery = nil
            value.youtubeVideoID = nil
        }
        buildPackaging()
        refreshQuality()
    }

    func render() async {
        guard rightsConfirmed else {
            alertMessage = "Bestätige vor dem lokalen Export, dass du die Quelle für diesen Zweck verwenden darfst."
            return
        }
        guard let sourceURL, let probe = sourceProbe, let clip = selectedClip, let project else {
            alertMessage = "Analysiere zuerst die Quelle und wähle einen Schnitt."
            return
        }
        isBusy = true
        progress = 0.08
        status = "High-Quality-Export wird vorbereitet …"
        let access = sourceURL.startAccessingSecurityScopedResource()
        defer { if access { sourceURL.stopAccessingSecurityScopedResource() }; isBusy = false }
        do {
            let spec = ProductionQualityDefaults().exportSpec(
                for: probe,
                portrait: resolvedPortrait,
                captions: captionsEnabled
            )
            let output = try exportURL(projectID: project.id)
            progress = 0.20
            status = "Video wird einmalig in hoher Qualität gerendert …"
            let result = try await renderService.render(
                sourceURL: sourceURL,
                clip: clip,
                spec: spec,
                captions: captionsEnabled ? project.captions : [],
                captionStyle: captionStyle,
                outputURL: output
            )
            guard result.quality.passes else {
                throw YouTubeUploadError(message: result.quality.errors.first ?? "Der technische Exportcheck ist fehlgeschlagen.")
            }
            mutateProject { value in
                value.renderedPath = result.outputURL.path
                value.outputPortrait = resolvedPortrait
                value.stage = .rendered
                value.lastError = nil
                value.uploadRecovery = nil
                value.youtubeVideoID = nil
            }
            progress = 1
            status = "Export geprüft und bereit für YouTube"
            section = .content
        } catch {
            mutateProject { $0.stage = .failed; $0.lastError = error.localizedDescription }
            fail(error)
        }
    }

    func applyPackaging(_ concept: PackagingConcept) {
        selectedPackagingID = concept.id
        updatePublication { $0.title = concept.title }
    }

    func updateTitle(_ value: String) { updatePublication { $0.title = String(value.prefix(100)) } }
    func updateDescription(_ value: String) { updatePublication { $0.description = String(value.prefix(5_000)) } }
    func updateTags(_ value: String) {
        updatePublication {
            $0.tags = value.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        }
    }
    func updatePrivacy(_ value: PublicationSettings.Privacy) { updatePublication { $0.privacy = value } }
    func updateMadeForKids(_ value: Bool) { updatePublication { $0.madeForKids = value } }
    func updateLanguage(_ value: String) { updatePublication { $0.defaultLanguage = value } }
    func updatePlaylist(_ value: String?) { updatePublication { $0.playlistID = value } }
    func updateSchedule(_ value: Date?) { updatePublication { $0.scheduledAt = value } }

    func setThumbnail(_ url: URL?) {
        guard let url else { updatePublication { $0.thumbnailPath = nil }; return }
        do {
            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            let size = (attributes[.size] as? NSNumber)?.intValue ?? 0
            guard size <= 2 * 1024 * 1024 else {
                throw YouTubeUploadError(message: "Das YouTube-Thumbnail darf höchstens 2 MB groß sein.")
            }
            let copied = try persistThumbnail(url)
            updatePublication { $0.thumbnailPath = copied.path }
        } catch { fail(error) }
    }

    func publish() async {
        guard var current = project, renderedURL != nil else {
            alertMessage = "Exportiere den Clip zuerst."
            return
        }
        guard youtubeConnected, let credentials = GoogleOAuthCredentials.current() else {
            alertMessage = "Verbinde zuerst den Zielkanal im Kanal-Bereich."
            return
        }
        guard !current.publication.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            alertMessage = "Der YouTube-Titel darf nicht leer sein."
            return
        }
        isBusy = true
        progress = 0.02
        status = "YouTube-Upload wird vorbereitet …"
        current.stage = .uploading
        save(current)
        defer { isBusy = false }
        do {
            let token = try await oauth.accessToken(credentials: credentials)
            let projectID = current.id
            let result = try await publisher.publish(
                project: current,
                accessToken: token,
                onRecovery: { [weak self] recovery in
                    Task { @MainActor in
                        guard let self, var saved = self.store.projects.first(where: { $0.id == projectID }) else { return }
                        saved.uploadRecovery = recovery
                        saved.stage = .uploading
                        self.save(saved)
                    }
                },
                onProgress: { [weak self] value in
                    Task { @MainActor in
                        self?.publishingProgress = value
                        self?.progress = value.fraction
                        self?.status = value.detail
                    }
                }
            )
            guard var finished = store.projects.first(where: { $0.id == projectID }) else { return }
            finished.stage = .published
            finished.youtubeVideoID = result.0.videoID
            finished.uploadRecovery = result.1
            finished.lastError = nil
            save(finished)
            progress = 1
            status = "Auf YouTube veröffentlicht"
        } catch {
            mutateProject { $0.stage = .failed; $0.lastError = error.localizedDescription }
            status = "Upload unterbrochen · Fortschritt bleibt gespeichert"
            alertMessage = error.localizedDescription
        }
    }

    func importOAuthClient(_ url: URL) {
        do {
            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }
            try oauth.importCredentials(Data(contentsOf: url))
            status = "Google-OAuth-Konfiguration sicher gespeichert"
            objectWillChange.send()
        } catch { fail(error) }
    }

    func connectYouTube() async {
        guard let credentials = GoogleOAuthCredentials.current() else {
            alertMessage = "Importiere zuerst die Google OAuth Desktop-JSON für Blackstock."
            return
        }
        isBusy = true
        status = "Google-Anmeldung wird geöffnet …"
        defer { isBusy = false }
        do {
            try await oauth.connect(credentials: credentials)
            await refreshChannel(showErrors: true)
        } catch { fail(error) }
    }

    func disconnectYouTube() {
        oauth.disconnect()
        channel = nil
        channelDNA = nil
        opportunities = []
        playlists = []
        analytics = nil
        status = "YouTube getrennt"
        objectWillChange.send()
    }

    func refreshChannel(showErrors: Bool = true) async {
        guard youtubeConnected, let credentials = GoogleOAuthCredentials.current() else { return }
        isBusy = true
        status = "Kanal wird analysiert …"
        defer { isBusy = false }
        do {
            let token = try await oauth.accessToken(credentials: credentials)
            let snapshot = try await dataService.myChannel(accessToken: token)
            async let videosTask = dataService.channelVideos(uploadsPlaylistID: snapshot.uploadsPlaylistID, accessToken: token, maximum: 100)
            async let playlistsTask = dataService.playlists(accessToken: token)
            async let analyticsTask = analyticsService.summary(days: 28, accessToken: token)
            let videos = try await videosTask
            let dna = dnaEngine.build(identity: snapshot.identity, videos: videos)
            channel = snapshot
            channelDNA = dna
            playlists = try await playlistsTask
            analytics = try? await analyticsTask
            await refreshTrends(showErrors: false)
            buildPackaging()
            status = "\(snapshot.identity.name) · \(dna.evidenceCount) Videos gelernt"
        } catch {
            if showErrors { fail(error) }
        }
    }

    func refreshTrends(showErrors: Bool = true) async {
        guard let dna = channelDNA, youtubeConnected, let credentials = GoogleOAuthCredentials.current() else {
            if showErrors { alertMessage = "Verbinde zuerst deinen YouTube-Kanal." }
            return
        }
        status = "Relevante Marktchancen werden geladen …"
        do {
            let token = try await oauth.accessToken(credentials: credentials)
            let values = try await dataService.discover(regionCode: "DE", dna: dna, accessToken: token)
            opportunities = values
            selectedOpportunityID = values.first?.id
            status = "\(values.count) relevante Chancen"
        } catch {
            if showErrors { fail(error) }
        }
    }

    func refreshAnalytics() async {
        guard youtubeConnected, let credentials = GoogleOAuthCredentials.current() else { return }
        do {
            let token = try await oauth.accessToken(credentials: credentials)
            analytics = try await analyticsService.summary(days: 28, accessToken: token)
        } catch { fail(error) }
    }

    func openOpportunity(_ opportunity: Opportunity) {
        guard let url = URL(string: "https://www.youtube.com/watch?v=\(opportunity.videoID)") else { return }
        NSWorkspace.shared.open(url)
    }

    func openPublished() {
        guard let id = project?.youtubeVideoID,
              let url = URL(string: "https://www.youtube.com/watch?v=\(id)") else { return }
        NSWorkspace.shared.open(url)
    }

    func revealExport() {
        guard let renderedURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([renderedURL])
    }

    private func inspectProjectSource(_ value: BlackstockProject) async {
        let url = value.resolvedSourceURL()
        guard FileManager.default.fileExists(atPath: url.path) else {
            sourceProbe = nil
            qualityDecision = .init(action: .block, messages: ["Die Quelldatei wurde verschoben oder gelöscht."])
            status = "Quelle fehlt"
            return
        }
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        do {
            sourceProbe = try await inspector.probe(url: url)
            refreshQuality()
        } catch { fail(error) }
    }

    private func applyProjectState(_ value: BlackstockProject) {
        project = value
        transcriptText = value.transcriptText ?? ""
        captionStyle = value.captionStyle
        captionsEnabled = !value.captions.isEmpty || value.transcriptWords == nil
        if let portrait = value.outputPortrait { outputFormat = portrait ? .short : .video }
        else { outputFormat = .automatic }
        if let candidates = value.clipCandidates {
            clipEvaluations = Array(clipEngine.rank(candidates, targetDuration: targetDurationRange()).prefix(24))
        } else { clipEvaluations = [] }
        buildPackaging()
    }

    private func rerankCandidates() {
        guard let candidates = project?.clipCandidates else { return }
        clipEvaluations = Array(clipEngine.rank(candidates, targetDuration: targetDurationRange()).prefix(24))
    }

    private func targetDurationRange() -> ClosedRange<Double> {
        switch outputFormat {
        case .short: return 15...75
        case .video: return 45...300
        case .automatic:
            guard let range = channelDNA?.preferredDuration else { return 20...120 }
            let lower = max(15, min(90, range.lowerBound))
            let upper = max(lower + 15, min(300, range.upperBound))
            return lower...upper
        }
    }

    private func refreshQuality() {
        let rights = RightsPolicy().decision(for: .init(kind: .localLicensed, userConfirmedRights: rightsConfirmed))
        let report: CaptionQualityReport?
        if captionsEnabled, let probe = sourceProbe, let cues = project?.captions, !cues.isEmpty {
            report = captionEngine.qualityReport(cues: cues, videoDuration: probe.duration)
        } else { report = nil }
        qualityDecision = qualityPolicy.decide(captions: report, source: sourceProbe, rights: rights)
    }

    private func buildPackaging() {
        guard let clip = selectedClip else { packagingConcepts = []; selectedPackagingID = nil; return }
        let sourceTitle = URL(fileURLWithPath: project?.sourcePath ?? "Video").deletingPathExtension().lastPathComponent
        packagingConcepts = packagingGenerator.concepts(for: clip, dna: channelDNA, sourceTitle: sourceTitle)
        if !packagingConcepts.contains(where: { $0.id == selectedPackagingID }) { selectedPackagingID = packagingConcepts.first?.id }
    }

    private func updatePublication(_ mutation: (inout PublicationSettings) -> Void) {
        mutateProject { mutation(&$0.publication) }
    }

    private func mutateProject(_ mutation: (inout BlackstockProject) -> Void) {
        guard var value = project else { return }
        mutation(&value)
        save(value)
    }

    private func save(_ value: BlackstockProject) {
        project = value
        store.update(value)
        projects = store.projects
    }

    private func exportURL(projectID: UUID) throws -> URL {
        let fm = FileManager.default
        let base = try fm.url(for: .moviesDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        let directory = base.appendingPathComponent("Blackstock Exports", isDirectory: true)
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("Blackstock-\(projectID.uuidString.prefix(8))-final.mp4")
    }

    private func persistThumbnail(_ url: URL) throws -> URL {
        let fm = FileManager.default
        let base = try fm.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        let directory = base.appendingPathComponent("Blackstock/Thumbnails", isDirectory: true)
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        let target = directory.appendingPathComponent("\(project?.id.uuidString ?? UUID().uuidString).\(url.pathExtension.isEmpty ? "jpg" : url.pathExtension)")
        try? fm.removeItem(at: target)
        try fm.copyItem(at: url, to: target)
        return target
    }

    private func fail(_ error: Error) {
        alertMessage = error.localizedDescription
        status = error.localizedDescription
    }
}
