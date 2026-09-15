import SwiftUI
import UniformTypeIdentifiers
import AppKit

@main
struct BlackstockNextApp: App {
    var body: some Scene {
        WindowGroup { RootView().frame(minWidth: 1100, minHeight: 720) }
    }
}

@MainActor
final class AppModel: ObservableObject {
    enum Section: String, CaseIterable, Identifiable {
        case dashboard = "Dashboard", trends = "Trends", cut = "Schneiden", content = "Content", analytics = "Analytics", channel = "Kanal"
        var id: String { rawValue }
    }

    @Published var section: Section = .dashboard
    @Published var sourceURL: URL?
    @Published var sourceProbe: SourceProbe?
    @Published var rightsConfirmed = false
    @Published var captionsEnabled = true
    @Published var qualityDecision: QualityDecision?
    @Published var status = "Bereit"
    @Published var channelName = "Kein Kanal verbunden"
    @Published var channelTopic = "Kanal-DNA wird nach Verbindung automatisch gelernt"
    @Published var uploadPrivacy = "private"
    let inspector = LocalMediaInspector()
    let policy = MassMarketQualityPolicy()

    func inspect(_ url: URL) async {
        sourceURL = url
        status = "Quelle wird geprüft …"
        do {
            sourceProbe = try await inspector.probe(url: url)
            refreshQuality()
            status = "Quelle bereit"
        } catch {
            sourceProbe = nil
            qualityDecision = .init(action: .block, messages: [error.localizedDescription])
            status = "Quelle nicht verwendbar"
        }
    }

    func refreshQuality() {
        let source = SourceDescriptor(kind: .localLicensed, userConfirmedRights: rightsConfirmed)
        qualityDecision = policy.decide(captions: nil, source: sourceProbe, rights: RightsPolicy().decision(for: source))
    }
}

struct RootView: View {
    @StateObject var model = AppModel()
    var body: some View {
        NavigationSplitView {
            List(AppModel.Section.allCases, selection: $model.section) { item in
                Label(item.rawValue, systemImage: icon(item)).tag(item)
            }
            .safeAreaInset(edge: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("BLACKSTOCK").font(.system(size: 20, weight: .black))
                    Text("Source-first YouTube workflow").font(.caption).foregroundStyle(.secondary)
                }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
            }
            .navigationSplitViewColumnWidth(210)
        } detail: {
            Group {
                switch model.section {
                case .dashboard: Dashboard(model: model)
                case .trends: Trends(model: model)
                case .cut: Cut(model: model)
                case .content: Content(model: model)
                case .analytics: Analytics(model: model)
                case .channel: Channel(model: model)
                }
            }.padding(28)
        }
    }
    func icon(_ s: AppModel.Section) -> String {
        switch s { case .dashboard: return "square.grid.2x2"; case .trends: return "chart.line.uptrend.xyaxis"; case .cut: return "scissors"; case .content: return "play.rectangle.on.rectangle"; case .analytics: return "chart.bar"; case .channel: return "person.crop.rectangle.stack" }
    }
}

struct Header: View {
    let title: String, subtitle: String
    var body: some View { VStack(alignment: .leading, spacing: 5) { Text(title).font(.largeTitle.bold()); Text(subtitle).foregroundStyle(.secondary) }.frame(maxWidth: .infinity, alignment: .leading) }
}

struct Dashboard: View {
    @ObservedObject var model: AppModel
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            Header(title: "Dashboard", subtitle: "Eine nächste sinnvolle Aktion statt Tool-Chaos.")
            GroupBox("Aktiver Kanal") { VStack(alignment: .leading, spacing: 8) { Text(model.channelName).font(.title2.bold()); Text(model.channelTopic).foregroundStyle(.secondary); Button("Trends ansehen") { model.section = .trends } }.frame(maxWidth: .infinity, alignment: .leading) }
            GroupBox("Produktprinzip") { Text("Bestehende Videos analysieren und hochwertig schneiden. YouTube-only Material bleibt im offiziellen Remix-Workflow. Lokale, erlaubte Quellen werden lokal verarbeitet und nur der finale Export kann nach Freigabe zu YouTube hochgeladen werden.").frame(maxWidth: .infinity, alignment: .leading) }
            Spacer()
        }
    }
}

struct Trends: View {
    @ObservedObject var model: AppModel
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            Header(title: "Trends", subtitle: "Kanalgebundene Chancen statt generischer Viral-Listen.")
            GroupBox("Channel Lock") { Label(model.channelTopic, systemImage: "lock.fill").frame(maxWidth: .infinity, alignment: .leading) }
            GroupBox("YouTube") { VStack(alignment: .leading, spacing: 9) { Text("Discovery wird über die offizielle YouTube Data API angebunden. Fremde Videos werden nicht verdeckt heruntergeladen."); Button("YouTube öffnen") { NSWorkspace.shared.open(URL(string: "https://www.youtube.com")!) } }.frame(maxWidth: .infinity, alignment: .leading) }
            Spacer()
        }
    }
}

struct Cut: View {
    @ObservedObject var model: AppModel
    @State var importer = false
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Header(title: "Schneiden", subtitle: "Source preservation, intelligente Defaults und Auto-Fix vor Stop.")
                GroupBox("Quelle") { VStack(alignment: .leading, spacing: 10) {
                    Text(model.sourceURL?.lastPathComponent ?? "Noch keine Videodatei gewählt")
                    if let p = model.sourceProbe { Text("\(Int(p.naturalSize.width))×\(Int(p.naturalSize.height)) · \(String(format: "%.2f", p.frameRate)) fps · \(Int(p.duration)) s").foregroundStyle(.secondary) }
                    Button("Videodatei wählen") { importer = true }
                    Toggle("Ich darf diese Datei für den vorgesehenen Zweck verwenden", isOn: $model.rightsConfirmed).onChange(of: model.rightsConfirmed) { _ in model.refreshQuality() }
                    Toggle("Captions automatisch optimieren", isOn: $model.captionsEnabled)
                }.frame(maxWidth: .infinity, alignment: .leading) }
                quality
                GroupBox("Nächster Schritt") { HStack { Text(model.status); Spacer(); Button("Export vorbereiten") { model.refreshQuality() }.buttonStyle(.borderedProminent).disabled(model.sourceProbe == nil || !model.rightsConfirmed) } }
            }
        }
        .fileImporter(isPresented: $importer, allowedContentTypes: [.movie], allowsMultipleSelection: false) { result in
            if case .success(let urls) = result, let url = urls.first { Task { await model.inspect(url) } }
        }
    }
    @ViewBuilder var quality: some View {
        if let q = model.qualityDecision {
            GroupBox("Qualität") { VStack(alignment: .leading, spacing: 7) {
                Label(label(q.action), systemImage: icon(q.action)).font(.headline)
                ForEach(q.messages, id: \.self) { Text($0).foregroundStyle(.secondary) }
            }.frame(maxWidth: .infinity, alignment: .leading) }
        }
    }
    func label(_ a: QualityDecision.Action) -> String { switch a { case .pass: return "Bereit"; case .autoFix: return "Blackstock korrigiert automatisch"; case .warn: return "Bereit mit Hinweis"; case .block: return "Aktion erforderlich" } }
    func icon(_ a: QualityDecision.Action) -> String { switch a { case .pass: return "checkmark.circle.fill"; case .autoFix: return "wand.and.stars"; case .warn: return "exclamationmark.circle"; case .block: return "xmark.octagon" } }
}

struct Content: View { @ObservedObject var model: AppModel; var body: some View { VStack(alignment: .leading, spacing: 20) { Header(title: "Content", subtitle: "Exports, Uploads und Veröffentlichungsstatus an einem Ort."); Text("Fertige Exporte werden hier mit Upload-Status und YouTube-Link verwaltet.").foregroundStyle(.secondary); Spacer() } } }
struct Analytics: View { @ObservedObject var model: AppModel; var body: some View { VStack(alignment: .leading, spacing: 20) { Header(title: "Analytics", subtitle: "Nur Kennzahlen, aus denen Blackstock eine nächste Entscheidung ableitet."); Text("CTR, Retention, Watchtime und Kanal-Lernen werden nach OAuth-Verbindung hier zusammengeführt.").foregroundStyle(.secondary); Spacer() } } }
struct Channel: View { @ObservedObject var model: AppModel; var body: some View { VStack(alignment: .leading, spacing: 20) { Header(title: "Kanal", subtitle: "Name, Thema und DNA gehören dauerhaft zum verbundenen YouTube-Kanal."); GroupBox("YouTube-Verbindung") { VStack(alignment: .leading, spacing: 8) { Text(model.channelName).font(.headline); Text("OAuth erhält nur die für Analyse und Upload benötigten Berechtigungen. Das Thema wird danach aus dem Kanal gelernt und nicht pro Video neu gewählt.").foregroundStyle(.secondary) }.frame(maxWidth: .infinity, alignment: .leading) }; Spacer() } } }
