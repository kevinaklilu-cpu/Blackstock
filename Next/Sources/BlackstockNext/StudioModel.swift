import Foundation
import SwiftUI
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
    @Published private(set) var projects: [BlackstockProject] = []
    @Published var project: BlackstockProject?
    @Published var sourceProbe: SourceProbe?
    @Published var clipEvaluations: [ClipEvaluation] = []
    @Published var transcriptText = ""
    @Published var qualityDecision: QualityDecision?
    @Published var outputFormat: OutputFormatPreference = .automatic
    @Published var captionsEnabled = true
    @Published var captionStyle: CaptionStyle = .clean
    @Published var publicationDraft = PublicationSettings(
        title: "",
        description: "",
        tags: [],
        categoryID: "22",
        privacy: .private,
        madeForKids: false,
        defaultLanguage: "de",
        playlistID: nil,
        scheduledAt: nil,
        thumbnailPath: nil
    )
    @Published var packagingConcepts: [PackagingConcept] = []
    @Published var selectedPackagingID: UUID?

    @Published private(set) var channel: YouTubeChannelSnapshot?
    @Published private(set) var channelDNA: ChannelDNA?
    @Published private(set) var playlists: [YouTubePlaylist] = []
    @Published private(set) var opportunities: [Opportunity] = []
    @Published var selectedOpportunityID: String?
    @Published private(set) var analyticsSummary: AnalyticsSummary?
    @Published private(set) var youtubeConnected = false
    @Published private(set) var oauthConfigured = false

    @Published var status = "Bereit"
    @Published var isBusy = false
    @Published var progress: Double?
    @Published var publishingProgress: PublishingProgress?
    @Published var alertMessage: String?

    private let store: ProjectStore
    private let oauth: GoogleOAuthService
    private let inspector = LocalMediaInspector()
    private let speech = SpeechTranscriptionService()
    private let candidateGenerator = ClipCandidateGenerator()
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
    private var activeTask: Task<Void, Never>?

    init(store: ProjectStore = ProjectStore(), oauth: GoogleOAuthService = GoogleOAuthService()) {
        self.store = store
        self.oauth = oauth
        projects = store.projects
        oauthConfigured = GoogleOAuthCredentials.current() != nil
        youtubeConnected = oauth.connected
        if let selected = store.selected {
            restore(selected)
        }
        if youtubeConnected, oauthConfigured {
            Task { [weak self] in await self?.refreshChannel() }
        }
    }

    var channelName: String { channel?.identity.name ?? "Kein Kanal verbunden" }
    var channelTopic: String { channelDNA?.primaryTopic ?? "Channel DNA wird nach Verbindung automatisch gelernt" }
    var selectedOpportunity: Opportunity? {
        guard let selectedOpportunityID else { return opportunities.first }
        return opportunities.first(where: { $0.id == selectedOpportunityID }) ?? opportunities.first
    }
    var selectedClip: ClipCandidate? { project?.selectedClip }
    var sourceURL: URL? { project?.resolvedSourceURL() }
    var renderedURL: URL? {
        guard let path = project?.renderedPath, FileManager.default.fileExists(atPath: path) else { return nil }
        return URL(fileURLWithPath: path)
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
    var canPublish: Bool {
        renderedURL != nil && youtubeConnected && oauthConfigured && !publicationDraft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func clearAlert() { alertMessage = nil }

    func importSource(_ url: URL) {
        cancelCurrentWork()
        let id = store.create(sourceURL: url, channelID: channel?.identity.id)
        projects = store.projects
        guard let created = projects.first(where: { $0.id == id }) else { return }
        restore(created)
        activeTask = Task { [weak self] in await self?.inspectCurrentSource() }
    }

    func selectProject(_ id: UUID) {
        guard let value = store.projects.first(where: { $0.id == id }) else { return }
        store.select(id)
        restore(value)
        activeTask = Task { [weak self] in await self?.inspectCurrentSource() }
    }

    func removeProject(_ id: UUID) {
        if project?.id == id { project = nil }
        store.remove(id)
        projects = store.projects
        if let selected = store.selected { restore(selected) }
    }

    func setRightsConfirmed(_ value: Bool) {
        guard var project else { return }
        project.rightsConfirmed = value
        save(project)
        refreshQuality()
    }

    func setCaptionStyle(_ style: CaptionStyle) {
        captionStyle = style
        guard var project else { return }
        project.captionStyle = style
        save(project)
    }

    func setOutputFormat(_ preference: OutputFormatPreference) {
        outputFormat = preference
        guard var project else { return }
        project.outputPortrait = preference == .automatic ? nil : (preference == .short)
        save(project)
        rerankStoredCandidates()
    }

    func persistPublication() {
        guard var project else { return }
        var sanitized = publicationDraft
        sanitized.title = String(sanitized.title.trimmingCharacters(in: .whitespacesAndNewlines).prefix(100))
        sanitized.description = String(sanitized.description.prefix(5_000))
        sanitized.tags = Array(NSOrderedSet(array: sanitized.tags.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty })) as? [String] ?? sanitized.tags)
        if let scheduled = sanitized.scheduledAt, scheduled <= Date().addingTimeInterval(60) { sanitized.scheduledAt = nil }
        publicationDraft = sanitized
        project.publication = sanitized
        save(project)
    }

    func applyPackaging(_ concept: PackagingConcept) {
        publicationDraft.title = concept.title
        selectedPackagingID = concept.id
        persistPublication()
    }

    func chooseClip(_ candidate: ClipCandidate) {
        guard var project else { return }
        project.selectedClip = candidate
        project.stage = .edited
        project.renderedPath = nil
        project.youtubeVideoID = nil
        project.uploadRecovery = nil
        save(project)
        buildPackaging()
        refreshQuality()
    }

    func beginAnalysis() {
        guard !isBusy else { return }
        activeTask = Task { [weak self] in await self?.analyzeCurrentSource() }
    }

    func beginRender() {
        guard !isBusy else { return }
        activeTask = Task { [weak self] in await self?.renderCurrentProject() }
    }

    func beginPublish() {
        guard !isBusy else { return }
        activeTask = Task { [weak self] in await self?.publishCurrentProject() }
    }

    func cancelCurrentWork() {
        activeTask?.cancel()
        activeTask = nil
        if isBusy {
            status = "Vorgang wird beendet …"
        }
    }

    func importOAuthCredentials(_ url: URL) {
        do {
            try oauth.importCredentials(Data(contentsOf: url))
            oauthConfigured = GoogleOAuthCredentials.current() != nil
            status = "Google-Verbindung ist konfiguriert"
        } catch {
            fail(error)
        }
    }

    func beginYouTubeConnect() {
        guard !isBusy else { return }
        activeTask = Task { [weak self] in await self?.connectYouTube() }
    }

    func disconnectYouTube() {
        oauth.disconnect()
        youtubeConnected = false
        channel = nil
        channelDNA = nil
        playlists = []
        opportunities = []
        analyticsSummary = nil
        status = "YouTube getrennt"
    }

    func beginRefreshChannel() {
        guard !isBusy else { return }
        activeTask = Task { [weak self] in await self?.refreshChannel() }
    }

    func openSelectedOpportunityOnYouTube() {
        guard let opportunity = selectedOpportunity,
              let url = URL(string: "https://www.youtube.com/watch?v=\(opportunity.videoID)") else { return }
        NSWorkspace.shared.open(url)
    }

    func openPublishedVideo() {
        guard let id = project?.youtubeVideoID,
              let url = URL(string: "https://www.youtube.com/watch?v=\(id)") else { return }
        NSWorkspace.shared.open(url)
    }

    private func restore(_ value: BlackstockProject) {
        project = value
        transcriptText = value.transcriptText ?? ""
        captionStyle = value.captionStyle
        publicationDraft = value.publication
        captionsEnabled = !value.captions.isEmpty || value.transcriptWords == nil
        if let portrait = value.outputPortrait {
            outputFormat = portrait ? .short : .video
        } else {
            outputFormat = .automatic
        }
        sourceProbe = nil
        clipEvaluations = []
        if let candidates = value.clipCandidates {
            clipEvaluations = clipEngine.rank(candidates, targetDuration: targetDurationRange())
        }
        buildPackaging()
        refreshQuality()
    }

    private func save(_ value: BlackstockProject) {
        project = value
        store.update(value)
        projects = store.projects
    }

    private func inspectCurrentSource() async {
        guard let sourceURL else { return }
        let access = sourceURL.startAccessingSecurityScopedResource()
        defer { if access { sourceURL.stopAccessingSecurityScopedResource() } }
        status = "Quelle wird geprüft …"
        do {
            let probe = try await inspector.probe(url: sourceURL)
            guard !Task.isCancelled else { return }
            sourceProbe = probe
            status = "Quelle bereit"
            refreshQuality()
            rerankStoredCandidates()
        } catch {
            sourceProbe = nil
            qualityDecision = .init(action: .block, messages: [error.localizedDescription])
            status = "Quelle nicht verwendbar"
            alertMessage = error.localizedDescription
        }
    }

    private func analyzeCurrentSource() async {
        guard let sourceURL, let sourceProbe else {
            alertMessage = "Bitte zuerst eine Videodatei auswählen."
            return
        }
        isBusy = true
        progress = nil
        status = "Sprache und Inhalt werden analysiert …"
        defer { isBusy = false; activeTask = nil }
        let access = sourceURL.startAccessingSecurityScopedResource()
        defer { if access { sourceURL.stopAccessingSecurityScopedResource() } }
        do {
            let language = channelDNA?.language ?? publicationDraft.defaultLanguage
            let transcription = try await speech.transcribe(fileURL: sourceURL, language: language)
            guard !Task.isCancelled else { status = "Analyse abgebrochen"; return }
            status = "Die stärksten Momente werden verglichen …"
            let target = targetDurationRange()
            let candidates = candidateGenerator.generate(words: transcription.words, preferredDuration: target, sourceDuration: sourceProbe.duration)
            let ranked = clipEngine.rank(candidates, targetDuration: target)
            guard let best = ranked.first else { throw YouTubeUploadError(message: "Blackstock konnte keinen ausreichend vollständigen Clip-Kandidaten finden.") }
            let cues = captionEngine.cues(from: transcription.words)
            var updated = project!
            updated.transcriptWords = transcription.words
            updated.transcriptText = transcription.fullText
            updated.clipCandidates = ranked.map(\.candidate)
            updated.selectedClip = best.candidate
            updated.captions = cues
            updated.captionStyle = captionStyle
            updated.publication.defaultLanguage = transcription.locale.components(separatedBy: "-").first ?? publicationDraft.defaultLanguage
            updated.stage = .analyzed
            updated.lastError = nil
            transcriptText = transcription.fullText
            clipEvaluations = ranked
            publicationDraft = updated.publication
            save(updated)
            buildPackaging()
            refreshQuality()
            status = "\(ranked.count) Momente bewertet · bester Schnitt ausgewählt"
        } catch {
            failProject(error)
        }
    }

    private func rerankStoredCandidates() {
        guard let candidates = project?.clipCandidates else { return }
        clipEvaluations = clipEngine.rank(candidates, targetDuration: targetDurationRange())
    }

    private func targetDurationRange() -> ClosedRange<Double> {
        switch outputFormat {
        case .short: return 15...75
        case .video: return 45...300
        case .automatic:
            if let preferred = channelDNA?.preferredDuration {
                let lower = max(15, min(90, preferred.lowerBound))
                let upper = max(lower + 15, min(300, preferred.upperBound))
                return lower...upper
            }
            return 20...120
        }
    }

    private func buildPackaging() {
        guard let clip = project?.selectedClip else {
            packagingConcepts = []
            selectedPackagingID = nil
            return
        }
        let title = URL(fileURLWithPath: project?.sourcePath ?? "Video").deletingPathExtension().lastPathComponent
        packagingConcepts = packagingGenerator.concepts(for: clip, dna: channelDNA, sourceTitle: title)
        if selectedPackagingID == nil { selectedPackagingID = packagingConcepts.first?.id }
    }

    private func refreshQuality() {
        let rights = RightsPolicy().decision(for: .init(kind: .localLicensed, userConfirmedRights: project?.rightsConfirmed ?? false))
        let captionReport: CaptionQualityReport?
        if captionsEnabled, let probe = sourceProbe, let cues = project?.captions, !cues.isEmpty {
            captionReport = captionEngine.qualityReport(cues: cues, videoDuration: probe.duration)
        } else {
            captionReport = nil
        }
        qualityDecision = qualityPolicy.decide(captions: captionReport, source: sourceProbe, rights: rights)
    }

    private func renderCurrentProject() async {
        guard var current = project,
              let sourceURL,
              let sourceProbe,
              let clip = current.selectedClip else {
            alertMessage = "Bitte zuerst Quelle analysieren und einen Schnitt auswählen."
            return
        }
        guard current.rightsConfirmed else {
            alertMessage = "Lokaler Export benötigt die Bestätigung, dass du die Quelle für diesen Zweck verwenden darfst."
            return
        }
        isBusy = true
        progress = nil
        status = "High-Quality-Export wird gerendert …"
        defer { isBusy = false; activeTask = nil }
        let access = sourceURL.startAccessingSecurityScopedResource()
        defer { if access { sourceURL.stopAccessingSecurityScopedResource() } }
        do {
            let spec = ProductionQualityDefaults().exportSpec(for: sourceProbe, portrait: resolvedPortrait, captions: captionsEnabled)
            let output = try exportURL(projectID: current.id)
            let result = try await renderService.render(
                sourceURL: sourceURL,
                clip: clip,
                spec: spec,
                captions: captionsEnabled ? current.captions : [],
                captionStyle: captionStyle,
                outputURL: output
            )
            guard !Task.isCancelled else { status = "Export abgebrochen"; return }
            guard result.quality.sourceReadable, result.quality.durationMatches, result.quality.dimensionsValid, result.quality.frameRateValid else {
                throw YouTubeUploadError(message: result.quality.errors.first ?? "Die technische Prüfung des Exports ist fehlgeschlagen.")
            }
            current.renderedPath = result.outputURL.path
            current.outputPortrait = resolvedPortrait
            current.stage = .rendered
            current.lastError = nil
            current.uploadRecovery = nil
            current.youtubeVideoID = nil
            save(current)
            status = "Export geprüft und bereit für YouTube"
            section = .content
        } catch {
            failProject(error)
        }
    }

    private func exportURL(projectID: UUID) throws -> URL {
        let fm = FileManager.default
        let base = try fm.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        let directory = base.appendingPathComponent("Blackstock/Exports", isDirectory: true)
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("\(projectID.uuidString)-final.mp4")
    }

    private func connectYouTube() async {
        guard let credentials = GoogleOAuthCredentials.current() else {
            oauthConfigured = false
            alertMessage = "Für die echte YouTube-Verbindung fehlt die Google-OAuth-Konfiguration. Importiere im Kanal-Bereich die Desktop-OAuth-JSON von Blackstock."
            return
        }
        isBusy = true
        status = "Google-Anmeldung wird geöffnet …"
        defer { isBusy = false; activeTask = nil }
        do {
            try await oauth.connect(credentials: credentials)
            youtubeConnected = true
            status = "YouTube verbunden · Kanal wird analysiert …"
            await refreshChannel(loadState: false)
        } catch {
            fail(error)
        }
    }

    func refreshChannel() async { await refreshChannel(loadState: true) }

    private func refreshChannel(loadState: Bool) async {
        guard let credentials = GoogleOAuthCredentials.current(), oauth.connected else { return }
        if loadState {
            isBusy = true
            status = "Kanal wird aktualisiert …"
        }
        defer {
            if loadState { isBusy = false; activeTask = nil }
        }
        do {
            let token = try await oauth.accessToken(credentials: credentials)
            async let snapshotTask = dataService.myChannel(accessToken: token)
            async let analyticsTask = analyticsService.summary(accessToken: token)
            let snapshot = try await snapshotTask
            let videos = try await dataService.channelVideos(uploadsPlaylistID: snapshot.uploadsPlaylistID, accessToken: token, maximum: 100)
            let dna = dnaEngine.build(identity: snapshot.identity, videos: videos)
            async let playlistTask = dataService.playlists(accessToken: token)
            async let opportunityTask = dataService.popular(regionCode: "DE", dna: dna, accessToken: token)
            channel = snapshot
            channelDNA = dna
            playlists = try await playlistTask
            opportunities = try await opportunityTask
            analyticsSummary = try? await analyticsTask
            youtubeConnected = true
            selectedOpportunityID = opportunities.first?.id
            buildPackaging()
            if var current = project, current.channelID == nil {
                current.channelID = snapshot.identity.id
                save(current)
            }
            status = "\(snapshot.identity.name) · \(dna.evidenceCount) Videos für Channel DNA ausgewertet"
        } catch {
            fail(error)
        }
    }

    private func publishCurrentProject() async {
        persistPublication()
        guard var current = project else { return }
        guard let credentials = GoogleOAuthCredentials.current(), oauth.connected else {
            alertMessage = "Verbinde zuerst den YouTube-Kanal."
            return
        }
        guard current.renderedPath != nil else {
            alertMessage = "Vor der Veröffentlichung muss der finale Export erstellt werden."
            return
        }
        guard !current.publication.title.isEmpty else {
            alertMessage = "Ein YouTube-Titel ist erforderlich."
            return
        }
        isBusy = true
        publishingProgress = .init(phase: .preparing, fraction: 0, detail: "YouTube wird vorbereitet")
        current.stage = .uploading
        save(current)
        defer { isBusy = false; activeTask = nil }
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
                onProgress: { [weak self] progress in
                    Task { @MainActor in
                        self?.publishingProgress = progress
                        self?.status = progress.detail
                    }
                }
            )
            guard var finished = store.projects.first(where: { $0.id == projectID }) else { return }
            finished.youtubeVideoID = result.0.videoID
            finished.uploadRecovery = result.1
            finished.stage = .published
            finished.lastError = nil
            save(finished)
            publishingProgress = .init(phase: .completed, fraction: 1, detail: "Auf YouTube veröffentlicht")
            status = "Veröffentlicht · Video-ID \(result.0.videoID)"
        } catch {
            if var failed = store.projects.first(where: { $0.id == current.id }) {
                failed.stage = .failed
                failed.lastError = error.localizedDescription
                save(failed)
            }
            fail(error)
        }
    }

    private func failProject(_ error: Error) {
        if var current = project {
            current.stage = .failed
            current.lastError = error.localizedDescription
            save(current)
        }
        fail(error)
    }

    private func fail(_ error: Error) {
        alertMessage = error.localizedDescription
        status = error.localizedDescription
        isBusy = false
        progress = nil
    }
}
