import Foundation
import SwiftUI
import AppKit
import Security
import UniformTypeIdentifiers

private struct PersistedState: Codable {
    var channels: [ConnectedChannel]
    var activeChannelID: UUID?
    var opportunities: [Opportunity]
    var project: CutProject
}

public enum SecretVault {
    private static let service = "de.blackstock.marketready"
    private static let account = "youtube-public-api-key"

    public static func loadAPIKey() -> String {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account, kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess, let data = item as? Data, let value = String(data: data, encoding: .utf8) else { return "" }
        return value
    }

    public static func saveAPIKey(_ value: String) {
        let base: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account]
        SecItemDelete(base as CFDictionary)
        guard !value.isEmpty, let data = value.data(using: .utf8) else { return }
        var add = base
        add[kSecValueData as String] = data
        SecItemAdd(add as CFDictionary, nil)
    }
}

@MainActor
public final class BlackstockState: ObservableObject {
    @Published public var route: BlackstockRoute = .channel
    @Published public var channels: [ConnectedChannel] = []
    @Published public var activeChannelID: UUID?
    @Published public var opportunities: [Opportunity] = []
    @Published public var selectedOpportunityID: String?
    @Published public var project = CutProject()
    @Published public var isBusy = false
    @Published public var statusMessage = ""
    @Published public var lastError: String?
    @Published public var apiKey = ""

    private let youtube = YouTubePublicClient()
    private let transcriber = LocalSpeechTranscriber()

    public init() { apiKey = SecretVault.loadAPIKey(); restore() }

    public var activeChannel: ConnectedChannel? { guard let activeChannelID else { return nil }; return channels.first(where: { $0.id == activeChannelID }) }
    public var selectedOpportunity: Opportunity? { guard let selectedOpportunityID else { return nil }; return opportunities.first(where: { $0.id == selectedOpportunityID }) }

    public func saveAPIKey() {
        let trimmed = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        apiKey = trimmed
        SecretVault.saveAPIKey(trimmed)
        statusMessage = trimmed.isEmpty ? "API-Schlüssel entfernt." : "API-Schlüssel sicher im macOS-Schlüsselbund gespeichert."
    }

    public func connectChannel(_ input: String) async {
        guard !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        await runBusy("Kanal wird analysiert …") {
            var channel = try await self.youtube.resolveChannel(input, apiKey: self.apiKey)
            let recent = try await self.youtube.recentVideos(channelID: channel.youtubeChannelID, apiKey: self.apiKey, maxResults: 30)
            channel.dna = ChannelDNAService.build(from: recent)
            if let index = self.channels.firstIndex(where: { $0.youtubeChannelID == channel.youtubeChannelID }) { channel.id = self.channels[index].id; self.channels[index] = channel } else { self.channels.append(channel) }
            self.activeChannelID = channel.id
            self.opportunities = []
            self.selectedOpportunityID = nil
            self.project = CutProject(channelID: channel.id)
            self.persist()
            self.statusMessage = "\(channel.name) ist verbunden. Channel-DNA aus \(channel.dna.sampleSize) Videos erstellt."
        }
    }

    public func activateChannel(_ id: UUID?) {
        activeChannelID = id
        opportunities = []
        selectedOpportunityID = nil
        project = CutProject(channelID: id)
        persist()
    }

    public func removeActiveChannel() {
        guard let activeChannelID else { return }
        channels.removeAll { $0.id == activeChannelID }
        self.activeChannelID = channels.first?.id
        opportunities = []
        selectedOpportunityID = nil
        project = CutProject(channelID: self.activeChannelID)
        persist()
    }

    public func refreshOpportunities() async {
        guard let channel = activeChannel else { route = .channel; lastError = "Verbinde zuerst einen Kanal."; return }
        await runBusy("Markt wird für \(channel.name) geprüft …") {
            let query = Array(channel.dna.keywords.prefix(4)).joined(separator: " ")
            let videos = try await self.youtube.discover(query: query.isEmpty ? channel.name : query, apiKey: self.apiKey, publishedAfter: Date().addingTimeInterval(-14 * 86400), maxResults: 40)
            self.opportunities = OpportunityEngine.rank(videos: videos.filter { $0.channelID != channel.youtubeChannelID }, dna: channel.dna)
            self.selectedOpportunityID = self.opportunities.first?.id
            self.persist()
            self.statusMessage = self.opportunities.isEmpty ? "Keine belastbare Chance gefunden." : "\(self.opportunities.count) relevante Videos bewertet."
        }
    }

    public func selectOpportunity(_ opportunity: Opportunity) async {
        selectedOpportunityID = opportunity.id
        project = CutProject(channelID: activeChannelID, youtubeVideoID: opportunity.video.videoID, sourceAccess: .youtubeNative, moments: [])
        persist()
        await loadYouTubeMomentSignals(for: opportunity)
    }

    public func loadYouTubeMomentSignals(for opportunity: Opportunity) async {
        guard !apiKey.isEmpty else { return }
        do {
            let moments = try await youtube.timestampedCommentMoments(videoID: opportunity.video.videoID, apiKey: apiKey, duration: opportunity.video.durationSeconds)
            guard project.youtubeVideoID == opportunity.video.videoID else { return }
            project.moments = moments
            project.selectedMomentID = moments.first?.id
            persist()
        } catch { statusMessage = "Zeitmarken konnten nicht geladen werden; der YouTube-native Workflow bleibt verfügbar." }
    }

    public func openYouTubeNative(moment: ClipMoment? = nil) {
        guard let videoID = project.youtubeVideoID ?? selectedOpportunity?.video.videoID else { return }
        let seconds = Int((moment?.start ?? 0).rounded(.down))
        var components = URLComponents(string: "https://www.youtube.com/watch")!
        components.queryItems = [URLQueryItem(name: "v", value: videoID), URLQueryItem(name: "t", value: "\(seconds)s")]
        if let url = components.url { NSWorkspace.shared.open(url) }
        statusMessage = "YouTube geöffnet. Remix-/Ausschneiden-Verfügbarkeit wird von YouTube selbst bestimmt."
    }

    public func importLocalSource(_ url: URL) async {
        await runBusy("Quelldatei wird technisch geprüft …") {
            let info = try await MediaInspector.inspect(url)
            self.project.sourceURL = url
            self.project.sourceAccess = .localLicensed
            self.project.sourceRightsConfirmed = false
            self.project.mediaInfo = info
            self.project.transcript = []
            self.project.moments = []
            self.project.selectedMomentID = nil
            self.project.exportedURL = nil
            self.project.qualityReport = nil
            self.persist()
            self.statusMessage = "Quelle geladen: \(info.width)×\(info.height) · \(String(format: "%.1f", info.fps)) fps. Rechtebestätigung ist vor Analyse/Export erforderlich."
        }
    }

    public func setRightsConfirmed(_ confirmed: Bool) { project.sourceRightsConfirmed = confirmed; persist() }

    public func analyzeLocalSource() async {
        guard let url = project.sourceURL else { return }
        guard project.sourceRightsConfirmed else { lastError = BlackstockError.rightsNotConfirmed.localizedDescription; return }
        await runBusy("Original wird lokal transkribiert und auf starke Momente geprüft …") {
            let transcript = try await self.transcriber.transcribe(videoURL: url, languageHint: self.activeChannel?.dna.languageHint)
            let duration = self.project.mediaInfo?.duration ?? transcript.last.map { $0.start + $0.duration } ?? 0
            let moments = MomentEngine.rank(transcript: transcript, mediaDuration: duration)
            guard !moments.isEmpty else { throw BlackstockError.noMoments }
            self.project.transcript = transcript
            self.project.moments = moments
            self.project.selectedMomentID = moments.first?.id
            self.persist()
            self.statusMessage = "\(moments.count) starke Schnittmomente aus dem lokalen Original gefunden."
        }
    }

    public func selectMoment(_ id: UUID) { project.selectedMomentID = id; persist() }
    public func setAspect(_ aspect: AspectMode) { project.aspect = aspect; persist() }

    public func exportSelectedMoment() async {
        guard let sourceURL = project.sourceURL, let moment = project.selectedMoment, let sourceInfo = project.mediaInfo else { lastError = "Quelle oder Schnittmoment fehlt."; return }
        guard project.sourceRightsConfirmed else { lastError = BlackstockError.rightsNotConfirmed.localizedDescription; return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.quickTimeMovie]
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = "Blackstock-\(Int(moment.start))-\(project.aspect.rawValue.replacingOccurrences(of: ":", with: "x")).mov"
        panel.title = "Hochwertigen Schnitt exportieren"
        guard panel.runModal() == .OK, let destination = panel.url else { return }
        await runBusy("High-Quality-Export läuft lokal …") {
            try await HighQualityRenderService.export(sourceURL: sourceURL, moment: moment, aspect: self.project.aspect, destination: destination)
            let report = await QualityGate.verify(source: sourceInfo, outputURL: destination, requestedMoment: moment, aspect: self.project.aspect)
            self.project.exportedURL = destination
            self.project.qualityReport = report
            self.persist()
            self.statusMessage = report.passed ? "Export abgeschlossen und Qualitätsprüfung bestanden." : "Export abgeschlossen; Qualitätsprüfung enthält Warnungen."
        }
    }

    public func revealExport() { guard let url = project.exportedURL else { return }; NSWorkspace.shared.activateFileViewerSelecting([url]) }

    private func runBusy(_ message: String, operation: @escaping () async throws -> Void) async {
        isBusy = true; lastError = nil; statusMessage = message
        do { try await operation() } catch { lastError = error.localizedDescription }
        isBusy = false
    }

    private var stateURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!.appendingPathComponent("BlackstockMarketReady", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base.appendingPathComponent("state.json")
    }

    private func persist() {
        let state = PersistedState(channels: channels, activeChannelID: activeChannelID, opportunities: opportunities, project: project)
        guard let data = try? JSONEncoder().encode(state) else { return }
        try? data.write(to: stateURL, options: .atomic)
    }

    private func restore() {
        guard let data = try? Data(contentsOf: stateURL), let saved = try? JSONDecoder().decode(PersistedState.self, from: data) else { return }
        channels = saved.channels; activeChannelID = saved.activeChannelID; opportunities = saved.opportunities; project = saved.project; selectedOpportunityID = opportunities.first?.id
    }
}
