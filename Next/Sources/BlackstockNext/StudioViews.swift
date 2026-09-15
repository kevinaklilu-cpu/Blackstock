import SwiftUI
import UniformTypeIdentifiers
import AVKit
import WebKit

struct StudioRootView: View {
    @StateObject private var model = StudioModel()

    var body: some View {
        NavigationSplitView {
            List(StudioModel.Section.allCases, selection: $model.section) { section in
                Label(section.rawValue, systemImage: icon(section)).tag(section)
            }
            .navigationSplitViewColumnWidth(210)
            .safeAreaInset(edge: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("BLACKSTOCK").font(.system(size: 21, weight: .black))
                    Text(model.youtubeConnected ? model.channelName : "YouTube Editing Studio")
                        .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
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
            .padding(26)
            .overlay(alignment: .bottom) {
                if model.isBusy {
                    HStack(spacing: 12) {
                        ProgressView(value: model.progress > 0 ? model.progress : nil).frame(width: 130)
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
        } message: { Text(model.alertMessage ?? "") }
    }

    private func icon(_ section: StudioModel.Section) -> String {
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
    @ObservedObject var model: StudioModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                PageHeader(title: "Dashboard", subtitle: "Die nächste starke Aktion für deinen Kanal.")
                channelCard
                if let opportunity = model.filteredOpportunities.first { opportunityCard(opportunity) }
                else if model.youtubeConnected { compactMessage("Noch keine passende Marktchance geladen.", action: "Trends aktualisieren") { Task { await model.refreshTrends() } } }
                if let project = model.project { projectCard(project) }
                else { compactMessage("Noch kein Schnittprojekt.", action: "Videodatei wählen") { model.section = .cut } }
            }
        }
    }

    private var channelCard: some View {
        GroupBox("Aktiver Kanal") {
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(model.channelName).font(.title2.bold())
                    Text(model.channelTopic).foregroundStyle(.secondary)
                }
                Spacer()
                if model.youtubeConnected {
                    Button("Aktualisieren") { Task { await model.refreshChannel() } }
                } else {
                    Button("Kanal verbinden") { model.section = .channel }.buttonStyle(.borderedProminent)
                }
            }.frame(maxWidth: .infinity)
        }
    }

    private func opportunityCard(_ opportunity: Opportunity) -> some View {
        GroupBox("Beste aktuelle Opportunity") {
            HStack(alignment: .top, spacing: 18) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(opportunity.title).font(.title3.bold()).lineLimit(2)
                    Text(opportunity.channelTitle).foregroundStyle(.secondary)
                    FlowReasonRow(reasons: model.opportunityReasons(opportunity))
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 8) {
                    Text("\(Int(opportunity.score))").font(.title.bold()).monospacedDigit()
                    Text("Opportunity").font(.caption).foregroundStyle(.secondary)
                    Button("Ansehen") { model.selectedOpportunityID = opportunity.id; model.section = .trends }.buttonStyle(.borderedProminent)
                }
            }.frame(maxWidth: .infinity)
        }
    }

    private func projectCard(_ project: BlackstockProject) -> some View {
        GroupBox("Aktives Projekt") {
            HStack {
                VStack(alignment: .leading, spacing: 5) {
                    Text(URL(fileURLWithPath: project.sourcePath).lastPathComponent).font(.headline)
                    Text(project.stage.rawValue).foregroundStyle(.secondary)
                    if let clip = project.selectedClip { Text("Schnitt \(formatTime(clip.start))–\(formatTime(clip.end)) · \(Int(clip.duration)) s").font(.caption).foregroundStyle(.secondary) }
                }
                Spacer()
                Button(project.renderedPath == nil ? "Weiter schneiden" : "Zu Content") {
                    model.section = project.renderedPath == nil ? .cut : .content
                }
            }.frame(maxWidth: .infinity)
        }
    }
}

struct TrendsView: View {
    @ObservedObject var model: StudioModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            PageHeader(title: "Trends", subtitle: "Channel-Fit und Geschwindigkeit statt einer generischen Viral-Liste.")
            if !model.youtubeConnected {
                EmptyState(title: "Kanal zuerst verbinden", detail: "Blackstock braucht deine Channel DNA, damit Trends tatsächlich zu deinem Kanal passen.", button: "Zum Kanal") { model.section = .channel }
            } else {
                controls
                HSplitView {
                    ScrollView {
                        LazyVStack(spacing: 9) {
                            ForEach(model.filteredOpportunities) { opportunity in
                                OpportunityRow(
                                    opportunity: opportunity,
                                    reasons: model.opportunityReasons(opportunity),
                                    selected: model.selectedOpportunity?.id == opportunity.id
                                ) { model.selectedOpportunityID = opportunity.id }
                            }
                        }.padding(.trailing, 8)
                    }.frame(minWidth: 400)
                    detail.frame(minWidth: 440)
                }
            }
        }
    }

    private var controls: some View {
        HStack {
            TextField("Chancen durchsuchen", text: $model.trendSearch).textFieldStyle(.roundedBorder).frame(maxWidth: 330)
            Picker("Sortierung", selection: $model.sortByMomentum) {
                Text("Für meinen Kanal").tag(false)
                Text("Momentum").tag(true)
            }.frame(width: 190)
            Spacer()
            Button("Aktualisieren") { Task { await model.refreshTrends() } }
        }
    }

    @ViewBuilder private var detail: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let opportunity = model.selectedOpportunity {
                YouTubeEmbed(videoID: opportunity.videoID)
                    .frame(minHeight: 315)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                Text(opportunity.title).font(.title3.bold()).lineLimit(2)
                Text(opportunity.channelTitle).foregroundStyle(.secondary)
                FlowReasonRow(reasons: model.opportunityReasons(opportunity))
                HStack {
                    Label("Fit \(Int(opportunity.relevance * 100)) %", systemImage: "scope")
                    Label("Momentum \(Int(opportunity.momentum * 100)) %", systemImage: "bolt.fill")
                    Label(formatViews(opportunity.viewCount), systemImage: "eye")
                }.font(.caption).foregroundStyle(.secondary)
                Text("YouTube-only Material bleibt im offiziellen YouTube-Workflow. Blackstock lädt fremde YouTube-Videos nicht verdeckt herunter.")
                    .font(.caption).foregroundStyle(.secondary)
                Button("Auf YouTube öffnen · Remix prüfen") { model.openOpportunity(opportunity) }.buttonStyle(.borderedProminent)
            } else {
                Text("Keine relevanten Chancen geladen.").foregroundStyle(.secondary)
            }
            Spacer()
        }.padding(.leading, 8)
    }
}

struct OpportunityRow: View {
    let opportunity: Opportunity
    let reasons: [String]
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 7) {
                Text(opportunity.title).font(.headline).lineLimit(2).multilineTextAlignment(.leading)
                HStack { Text(opportunity.channelTitle).lineLimit(1); Spacer(); Text("\(Int(opportunity.score))").font(.headline.monospacedDigit()) }
                    .font(.caption).foregroundStyle(.secondary)
                Text(reasons.prefix(2).joined(separator: " · ")).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(selected ? Color.primary.opacity(0.09) : Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 10))
        }.buttonStyle(.plain)
    }
}

struct CutView: View {
    @ObservedObject var model: StudioModel
    @State private var importer = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                PageHeader(title: "Schneiden", subtitle: "Bestehende Quelle → bester Moment → sauberer Export.")
                sourceBox
                if let source = model.sourceURL { VideoPreview(url: source).frame(height: 320).clipShape(RoundedRectangle(cornerRadius: 12)) }
                if !model.clipEvaluations.isEmpty { clipsBox }
                if let quality = model.qualityDecision { qualityBox(quality) }
                if model.selectedClip != nil { finishBox }
            }
        }
        .fileImporter(isPresented: $importer, allowedContentTypes: [.movie], allowsMultipleSelection: false) { result in
            if case .success(let urls) = result, let url = urls.first { Task { await model.importSource(url) } }
        }
    }

    private var sourceBox: some View {
        GroupBox("Quelle") {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(model.sourceURL?.lastPathComponent ?? "Noch keine Videodatei gewählt").font(.headline)
                        if let probe = model.sourceProbe {
                            Text("\(Int(probe.naturalSize.width))×\(Int(probe.naturalSize.height)) · \(String(format: "%.2f", probe.frameRate)) fps · \(formatDuration(probe.duration)) · \(probe.hasAudio ? "Audio" : "kein Audio")")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    Button("Videodatei wählen") { importer = true }
                }
                Toggle("Ich darf diese Datei für den vorgesehenen Zweck verwenden", isOn: Binding(get: { model.rightsConfirmed }, set: model.setRights))
                HStack {
                    Picker("Format", selection: Binding(get: { model.outputFormat }, set: model.setOutputFormat)) {
                        ForEach(OutputFormatPreference.allCases) { Text($0.rawValue).tag($0) }
                    }.frame(width: 220)
                    Toggle("Captions", isOn: Binding(get: { model.captionsEnabled }, set: model.setCaptionsEnabled)).toggleStyle(.switch)
                    Picker("Stil", selection: Binding(get: { model.captionStyle }, set: model.setCaptionStyle)) {
                        ForEach(CaptionStyle.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }.frame(width: 155)
                    Spacer()
                    Button(model.transcriptText.isEmpty ? "Analysieren" : "Neu analysieren") { Task { await model.analyzeSource() } }
                        .buttonStyle(.borderedProminent).disabled(model.sourceProbe == nil)
                }
                if let recommendation = model.formatRecommendation, model.outputFormat == .automatic {
                    Label("Empfehlung: \(recommendation.label) · \(recommendation.reason)", systemImage: "wand.and.stars")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }.frame(maxWidth: .infinity)
        }
    }

    private var clipsBox: some View {
        GroupBox("Beste Momente") {
            VStack(alignment: .leading, spacing: 9) {
                ForEach(Array(model.clipEvaluations.prefix(7))) { evaluation in
                    Button { model.selectClip(evaluation) } label: {
                        HStack(alignment: .top, spacing: 11) {
                            Image(systemName: model.selectedClip?.id == evaluation.candidate.id ? "checkmark.circle.fill" : "circle")
                            VStack(alignment: .leading, spacing: 4) {
                                Text(evaluation.candidate.transcript).lineLimit(2).multilineTextAlignment(.leading)
                                Text("\(formatTime(evaluation.candidate.start))–\(formatTime(evaluation.candidate.end)) · \(Int(evaluation.candidate.duration)) s · Clip \(Int(evaluation.score))/100")
                                    .font(.caption).foregroundStyle(.secondary)
                                if !evaluation.reasons.isEmpty { Text(evaluation.reasons.joined(separator: " · ")).font(.caption2).foregroundStyle(.secondary) }
                            }
                            Spacer()
                        }
                        .padding(9)
                        .background(model.selectedClip?.id == evaluation.candidate.id ? Color.primary.opacity(0.07) : Color.clear, in: RoundedRectangle(cornerRadius: 8))
                    }.buttonStyle(.plain)
                }
                DisclosureGroup("Transkript") { Text(model.transcriptText).textSelection(.enabled).padding(.top, 6) }
            }.frame(maxWidth: .infinity)
        }
    }

    private func qualityBox(_ quality: QualityDecision) -> some View {
        GroupBox("Qualität") {
            VStack(alignment: .leading, spacing: 7) {
                Label(qualityLabel(quality.action), systemImage: qualityIcon(quality.action)).font(.headline)
                ForEach(quality.messages, id: \.self) { Text($0).font(.caption).foregroundStyle(.secondary) }
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var finishBox: some View {
        GroupBox("Fertigstellen") {
            HStack(alignment: .center) {
                if let clip = model.selectedClip {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Ausgewählter Schnitt").font(.headline)
                        Text("\(formatTime(clip.start))–\(formatTime(clip.end)) · \(Int(clip.duration)) Sekunden").foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Button("High-Quality-Export") { Task { await model.render() } }
                    .buttonStyle(.borderedProminent).disabled(!model.rightsConfirmed)
            }.frame(maxWidth: .infinity)
        }
    }
}

struct ContentView: View {
    @ObservedObject var model: StudioModel
    @State private var thumbnailImporter = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                PageHeader(title: "Content", subtitle: "Projekt, Packaging, Export und Veröffentlichung in einem Flow.")
                projectList
                if let project = model.project { projectDetail(project) }
            }
        }
        .fileImporter(isPresented: $thumbnailImporter, allowedContentTypes: [.image], allowsMultipleSelection: false) { result in
            if case .success(let urls) = result, let url = urls.first { model.setThumbnail(url) }
        }
    }

    private var projectList: some View {
        GroupBox("Projekte") {
            VStack(spacing: 7) {
                if model.projects.isEmpty { Text("Noch keine Projekte.").foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading) }
                ForEach(model.projects.prefix(12)) { project in
                    HStack {
                        Button { Task { await model.selectProject(project.id) } } label: {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(URL(fileURLWithPath: project.sourcePath).lastPathComponent).font(.headline).lineLimit(1)
                                Text(project.stage.rawValue).font(.caption).foregroundStyle(.secondary)
                            }.frame(maxWidth: .infinity, alignment: .leading)
                        }.buttonStyle(.plain)
                        if project.youtubeVideoID != nil { Image(systemName: "checkmark.seal.fill").foregroundStyle(.secondary) }
                        Button(role: .destructive) { model.deleteProject(project.id) } label: { Image(systemName: "trash") }.buttonStyle(.borderless)
                    }
                    .padding(.vertical, 5)
                }
            }
        }
    }

    private func projectDetail(_ project: BlackstockProject) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            if let rendered = model.renderedURL {
                GroupBox("Fertiges Video") {
                    VStack(alignment: .leading, spacing: 9) {
                        VideoPreview(url: rendered).frame(height: 300).clipShape(RoundedRectangle(cornerRadius: 10))
                        HStack { Text(rendered.lastPathComponent).font(.caption).foregroundStyle(.secondary); Spacer(); Button("Im Finder zeigen") { model.revealExport() } }
                    }
                }
                packagingBox
                publishingBox(project)
            } else {
                compactMessage("Für dieses Projekt gibt es noch keinen finalen Export.", action: "Zum Schnitt") { model.section = .cut }
            }
        }
    }

    private var packagingBox: some View {
        GroupBox("Packaging") {
            VStack(alignment: .leading, spacing: 9) {
                Text("Titel und Thumbnail sollen dasselbe Versprechen ergänzen, nicht doppeln.").font(.caption).foregroundStyle(.secondary)
                ForEach(model.packagingConcepts.prefix(4)) { concept in
                    Button { model.applyPackaging(concept) } label: {
                        HStack(alignment: .top) {
                            Image(systemName: model.selectedPackagingID == concept.id ? "checkmark.circle.fill" : "circle")
                            VStack(alignment: .leading, spacing: 3) {
                                Text(concept.angle.rawValue).font(.caption.bold()).foregroundStyle(.secondary)
                                Text(concept.title).font(.headline).multilineTextAlignment(.leading)
                                Text("Thumbnail: \(concept.thumbnailPromise)").font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                        }.padding(7)
                    }.buttonStyle(.plain)
                }
            }.frame(maxWidth: .infinity)
        }
    }

    private func publishingBox(_ project: BlackstockProject) -> some View {
        GroupBox("YouTube veröffentlichen") {
            VStack(alignment: .leading, spacing: 11) {
                TextField("Titel", text: Binding(get: { model.publication?.title ?? "" }, set: model.updateTitle))
                TextEditor(text: Binding(get: { model.publication?.description ?? "" }, set: model.updateDescription))
                    .frame(minHeight: 88)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.25)))
                TextField("Tags, durch Kommas getrennt", text: Binding(get: { model.publication?.tags.joined(separator: ", ") ?? "" }, set: model.updateTags))
                HStack {
                    Picker("Sichtbarkeit", selection: Binding(get: { model.publication?.privacy ?? .private }, set: model.updatePrivacy)) {
                        ForEach(PublicationSettings.Privacy.allCases) { Text($0.label).tag($0) }
                    }.frame(width: 220)
                    Toggle("Für Kinder", isOn: Binding(get: { model.publication?.madeForKids ?? false }, set: model.updateMadeForKids))
                    TextField("Sprache", text: Binding(get: { model.publication?.defaultLanguage ?? "de" }, set: model.updateLanguage)).frame(width: 95)
                    Spacer()
                }
                HStack {
                    Picker("Playlist", selection: Binding(get: { model.publication?.playlistID ?? "" }, set: { model.updatePlaylist($0.isEmpty ? nil : $0) })) {
                        Text("Keine Playlist").tag("")
                        ForEach(model.playlists) { Text($0.title).tag($0.id) }
                    }.frame(width: 290)
                    Button(project.publication.thumbnailPath == nil ? "Thumbnail wählen" : "Thumbnail ändern") { thumbnailImporter = true }
                    if project.publication.thumbnailPath != nil { Label("gesetzt", systemImage: "checkmark.circle.fill").font(.caption).foregroundStyle(.secondary) }
                    Spacer()
                }
                Toggle("Veröffentlichung planen", isOn: Binding(
                    get: { model.publication?.scheduledAt != nil },
                    set: { model.updateSchedule($0 ? Date().addingTimeInterval(3600) : nil) }
                ))
                if let scheduled = model.publication?.scheduledAt {
                    DatePicker("Zeitpunkt", selection: Binding(get: { scheduled }, set: model.updateSchedule), in: Date()..., displayedComponents: [.date, .hourAndMinute])
                }
                if let progress = model.publishingProgress { ProgressView(value: progress.fraction) { Text(progress.detail) } }
                HStack {
                    if project.youtubeVideoID != nil { Button("Auf YouTube ansehen") { model.openPublished() } }
                    Spacer()
                    Button(project.uploadRecovery == nil ? "Auf YouTube veröffentlichen" : "Upload fortsetzen") { Task { await model.publish() } }
                        .buttonStyle(.borderedProminent)
                        .disabled(!model.youtubeConnected || model.publication?.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false)
                }
                if let error = project.lastError { Text(error).font(.caption).foregroundStyle(.secondary) }
            }.frame(maxWidth: .infinity)
        }
    }
}

struct AnalyticsView: View {
    @ObservedObject var model: StudioModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                PageHeader(title: "Analytics", subtitle: "Wenige echte Kennzahlen, aus denen die nächste Entscheidung entsteht.")
                if !model.youtubeConnected {
                    EmptyState(title: "Noch keine Kanaldaten", detail: "Verbinde YouTube, damit Blackstock echte Analytics statt Schätzwerte nutzt.", button: "Kanal verbinden") { model.section = .channel }
                } else if let analytics = model.analytics {
                    HStack(spacing: 11) {
                        MetricCard(title: "Views · 28 Tage", value: formatViews(analytics.views))
                        MetricCard(title: "Watchtime", value: "\(Int(analytics.estimatedMinutesWatched / 60)) h")
                        MetricCard(title: "Ø Wiedergabe", value: formatDuration(analytics.averageViewDuration))
                        MetricCard(title: "Neue Abos", value: "+\(analytics.subscribersGained)")
                    }
                    if let opportunity = model.filteredOpportunities.first {
                        GroupBox("Nächste Entscheidung") {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(opportunity.title).font(.headline)
                                FlowReasonRow(reasons: model.opportunityReasons(opportunity))
                                Button("Opportunity ansehen") { model.selectedOpportunityID = opportunity.id; model.section = .trends }
                            }.frame(maxWidth: .infinity, alignment: .leading)
                        }
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
    @ObservedObject var model: StudioModel
    @State private var oauthImporter = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                PageHeader(title: "Kanal", subtitle: "Kanalidentität, Channel DNA und sichere YouTube-Verbindung.")
                GroupBox("YouTube-Verbindung") {
                    VStack(alignment: .leading, spacing: 10) {
                        if !model.oauthConfigured {
                            Text("Blackstock benötigt eine echte Google OAuth Desktop-Konfiguration. Die importierte Client-Konfiguration und Tokens werden sicher im macOS-Keychain verwaltet.")
                                .foregroundStyle(.secondary)
                            Button("Google OAuth JSON importieren") { oauthImporter = true }.buttonStyle(.borderedProminent)
                        } else if !model.youtubeConnected {
                            Text("Google OAuth ist konfiguriert. Verbinde jetzt den YouTube-Kanal.").foregroundStyle(.secondary)
                            HStack {
                                Button("Mit YouTube verbinden") { Task { await model.connectYouTube() } }.buttonStyle(.borderedProminent)
                                Button("OAuth-Konfiguration ersetzen") { oauthImporter = true }
                            }
                        } else if let channel = model.channel {
                            HStack(alignment: .top) {
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(channel.identity.name).font(.title2.bold())
                                    Text(model.channelTopic).foregroundStyle(.secondary)
                                    Text("\(formatViews(channel.subscriberCount)) Abonnenten · \(formatViews(channel.videoCount)) Videos · \(formatViews(channel.viewCount)) Kanalaufrufe")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Button("Aktualisieren") { Task { await model.refreshChannel() } }
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
                GroupBox("Source-first") {
                    Text("YouTube-only Material bleibt im offiziellen YouTube-Workflow. Lokale Quellen werden erst nach Rechtebestätigung verarbeitet. Das Quellvideo bleibt lokal; nur der freigegebene finale Export wird auf Wunsch zu YouTube hochgeladen.")
                        .foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .fileImporter(isPresented: $oauthImporter, allowedContentTypes: [.json], allowsMultipleSelection: false) { result in
            if case .success(let urls) = result, let url = urls.first { model.importOAuthClient(url) }
        }
    }
}

struct VideoPreview: View {
    let url: URL
    @State private var player = AVPlayer()
    var body: some View {
        VideoPlayer(player: player)
            .onAppear { player.replaceCurrentItem(with: AVPlayerItem(url: url)) }
            .onChange(of: url) { value in player.replaceCurrentItem(with: AVPlayerItem(url: value)) }
            .onDisappear { player.pause() }
    }
}

struct YouTubeEmbed: NSViewRepresentable {
    let videoID: String
    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.setValue(false, forKey: "drawsBackground")
        return view
    }
    func updateNSView(_ webView: WKWebView, context: Context) {
        let marker = "/embed/\(videoID)"
        if webView.url?.absoluteString.contains(marker) == true { return }
        guard let url = URL(string: "https://www.youtube-nocookie.com/embed/\(videoID)?playsinline=1&rel=0") else { return }
        webView.load(URLRequest(url: url))
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
        .padding(15)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 12))
    }
}

struct FlowReasonRow: View {
    let reasons: [String]
    var body: some View {
        HStack(spacing: 7) {
            ForEach(Array(reasons.prefix(3)), id: \.self) { reason in
                Text(reason).font(.caption2).padding(.horizontal, 8).padding(.vertical, 4).background(Color.primary.opacity(0.06), in: Capsule())
            }
        }.foregroundStyle(.secondary)
    }
}

struct EmptyState: View {
    let title: String
    let detail: String
    let button: String
    let action: () -> Void
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "sparkles").font(.system(size: 28)).foregroundStyle(.secondary)
            Text(title).font(.title3.bold())
            Text(detail).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 520)
            Button(button, action: action).buttonStyle(.borderedProminent)
        }
        .padding(44)
        .frame(maxWidth: .infinity)
    }
}

func compactMessage(_ text: String, action: String, handler: @escaping () -> Void) -> some View {
    GroupBox {
        HStack { Text(text).foregroundStyle(.secondary); Spacer(); Button(action, action: handler) }
    }
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
