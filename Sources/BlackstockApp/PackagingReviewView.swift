#if os(macOS)
import SwiftUI
import UniformTypeIdentifiers
import BlackstockCore

struct PackagingReviewView: View {
    @ObservedObject var session: BlackstockSession
    let project: BlackstockProject
    let asset: ProductionMediaAsset
    let artifact: RenderArtifact
    let transcript: LocalTranscript?
    let generatedCaptionURL: URL?

    @Environment(\.dismiss) private var dismiss

    @State private var title: String
    @State private var description = ""
    @State private var tags = ""
    @State private var privacyStatus: YouTubePrivacyStatus = .privateVideo
    @State private var madeForKids = false
    @State private var thumbnailURL: URL?
    @State private var captionTracks: [PublishCaptionTrack] = []
    @State private var showThumbnailImporter = false
    @State private var showCaptionImporter = false
    @State private var manualChecks: Set<CreatorQualityArea> = []
    @State private var persistedReview: CreatorQualityReview?
    @State private var manualNotes: [CreatorQualityArea: String] = [:]

    private let requiredQualityAreas: Set<CreatorQualityArea> = [
        .packaging,
        .retentionStructure,
        .audio,
        .captions,
        .visualComposition,
        .rightsAndPolicy,
        .renderIntegrity
    ]

    init(
        session: BlackstockSession,
        project: BlackstockProject,
        asset: ProductionMediaAsset,
        artifact: RenderArtifact,
        transcript: LocalTranscript?,
        generatedCaptionURL: URL?
    ) {
        self.session = session
        self.project = project
        self.asset = asset
        self.artifact = artifact
        self.transcript = transcript
        self.generatedCaptionURL = generatedCaptionURL
        let saved = session.loadPublishPreparation(
            projectID: project.id
        )
        _title = State(
            initialValue: saved?.package.metadata.title
                ?? project.title
        )
        _description = State(
            initialValue: saved?.package.metadata.description
                ?? ""
        )
        _tags = State(
            initialValue: saved?.package.metadata.tags
                .joined(separator: ", ")
                ?? ""
        )
        _privacyStatus = State(
            initialValue: saved?.package.metadata.privacyStatus
                ?? .privateVideo
        )
        _madeForKids = State(
            initialValue: saved?.package.metadata
                .selfDeclaredMadeForKids
                ?? false
        )
        _thumbnailURL = State(
            initialValue: saved?.package.thumbnail?.fileURL
        )
        _captionTracks = State(
            initialValue: saved?.package.captions ?? []
        )
        _persistedReview = State(
            initialValue: saved?.qualityReview
        )

        if saved == nil, let generatedCaptionURL {
            let language = transcript?.localeIdentifier ?? "de-DE"
            _captionTracks = State(
                initialValue: [
                    PublishCaptionTrack(
                        language: language,
                        name: "Blackstock Captions",
                        fileURL: generatedCaptionURL,
                        mimeType: Self.captionMIMEType(for: generatedCaptionURL)
                    )
                ]
            )
        }
    }

    private var automaticQualityReview: CreatorQualityReview {
        DeterministicQualityEvidenceBuilder().build(
            projectID: project.id,
            asset: asset,
            artifact: artifact,
            transcript: transcript,
            captionURL: generatedCaptionURL
        )
    }

    private var manualAttestations: [ManualQualityAttestation] {
        manualChecks.compactMap { area in
            guard let note = manualNotes[area] else { return nil }
            let attestation = ManualQualityAttestation(
                area: area,
                note: note,
                confirmedAt: Date()
            )
            return attestation.isValid ? attestation : nil
        }
    }

    private var qualityReview: CreatorQualityReview {
        if let persistedReview {
            return persistedReview
        }
        return QualityReviewComposer().compose(
            automatic: automaticQualityReview,
            manualAttestations: manualAttestations
        )
    }

    private var currentStage: BlackstockStage {
        session.activeProject?.stage ?? project.stage
    }

    private var reviewFrozen: Bool {
        currentStage == .review
        || currentStage == .publishing
        || currentStage == .published
    }

    private var missingAreas: [CreatorQualityArea] {
        Array(
            qualityReview.missingCoverage(
                requiredAreas: requiredQualityAreas
            )
        )
        .sorted { $0.rawValue < $1.rawValue }
    }

    private var tagsArray: [String] {
        tags
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private var draftPackage: PublishPackage {
        PublishPackage(
            projectID: project.id,
            targetChannelID: project.targetChannelID,
            renderArtifactID: artifact.id,
            metadata: .init(
                title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                description: description,
                tags: tagsArray,
                categoryID: nil,
                privacyStatus: privacyStatus,
                selfDeclaredMadeForKids: madeForKids
            ),
            thumbnail: thumbnailURL.map {
                PublishThumbnail(
                    fileURL: $0,
                    mimeType: Self.imageMIMEType(for: $0)
                )
            },
            captions: captionTracks
        )
    }

    var body: some View {
        HSplitView {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    metadataSection
                    packagingAssetsSection
                    manualReviewSection
                    targetSection
                }
                .padding(22)
            }
            .frame(minWidth: 500)

            reviewPanel
                .frame(minWidth: 320, idealWidth: 360, maxWidth: 410)
        }
        .frame(minWidth: 900, minHeight: 650)
        .fileImporter(
            isPresented: $showThumbnailImporter,
            allowedContentTypes: [.image],
            allowsMultipleSelection: false
        ) { result in
            if case .success(let urls) = result {
                thumbnailURL = urls.first
            }
        }
        .fileImporter(
            isPresented: $showCaptionImporter,
            allowedContentTypes: [UTType(filenameExtension: "vtt") ?? .plainText, .plainText],
            allowsMultipleSelection: false
        ) { result in
            if case .success(let urls) = result, let url = urls.first {
                let language = Locale.current.language.languageCode?.identifier ?? "de"
                captionTracks = [
                    PublishCaptionTrack(
                        language: language,
                        name: "Blackstock Captions",
                        fileURL: url,
                        mimeType: Self.captionMIMEType(for: url)
                    )
                ]
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Packaging & Review")
                        .font(.title2.bold())
                    Text("Alles prüfen, bevor Blackstock eine Remote-Aktion zulässt.")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Schließen") { dismiss() }
            }

            Label(
                "Render: " + String(artifact.sha256.prefix(12)) + "…",
                systemImage: "checkmark.seal"
            )
            .font(.caption.monospaced())
            .foregroundStyle(.secondary)
        }
    }

    private var metadataSection: some View {
        GroupBox("YouTube-Metadaten") {
            VStack(alignment: .leading, spacing: 12) {
                TextField("Titel", text: $title)
                    .textFieldStyle(.roundedBorder)

                TextEditor(text: $description)
                    .font(.body)
                    .frame(minHeight: 120)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(Color.primary.opacity(0.12))
                    )

                TextField("Tags, durch Kommas getrennt", text: $tags)
                    .textFieldStyle(.roundedBorder)

                Picker("Sichtbarkeit", selection: $privacyStatus) {
                    Text("Privat").tag(YouTubePrivacyStatus.privateVideo)
                    if session.publicPublishingAllowed {
                        Text("Nicht gelistet").tag(YouTubePrivacyStatus.unlisted)
                        Text("Öffentlich").tag(YouTubePrivacyStatus.publicVideo)
                    }
                }
                .pickerStyle(.segmented)

                Toggle("Für Kinder erstellt", isOn: $madeForKids)
            }
            .padding(.vertical, 6)
            .disabled(reviewFrozen)
        }
    }

    private var packagingAssetsSection: some View {
        GroupBox("Thumbnail & Captions") {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Thumbnail")
                            .font(.headline)
                        Text(thumbnailURL?.lastPathComponent ?? "Noch kein Thumbnail gewählt")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Auswählen …") {
                        showThumbnailImporter = true
                    }
                }

                Divider()

                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Caption-Datei")
                            .font(.headline)
                        Text(captionTracks.first?.fileURL.lastPathComponent ?? "Noch keine Caption-Datei gewählt")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Auswählen …") {
                        showCaptionImporter = true
                    }
                }
            }
            .padding(.vertical, 6)
            .disabled(reviewFrozen)
        }
    }

    private var manualReviewSection: some View {
        GroupBox("Qualitative Review") {
            VStack(alignment: .leading, spacing: 14) {
                Text("Blackstock misst technische Fakten automatisch. Inhaltliche Qualität wird direkt am Video geprüft und als Nutzer-Evidenz protokolliert.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                ForEach(manualReviewAreas, id: \.self) { area in
                    manualReviewRow(area)
                    if area != manualReviewAreas.last {
                        Divider()
                    }
                }
            }
            .padding(.vertical, 6)
        }
    }

    @ViewBuilder
    private func manualReviewRow(_ area: CreatorQualityArea) -> some View {
        let automaticallyCovered = automaticQualityReview.coveredAreas.contains(area)

        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(areaTitle(area))
                        .font(.headline)
                    Text(areaQuestion(area))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()

                if automaticallyCovered {
                    Label("Automatisch belegt", systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                } else {
                    Toggle(
                        "Geprüft",
                        isOn: Binding(
                            get: { manualChecks.contains(area) },
                            set: { enabled in
                                if enabled {
                                    manualChecks.insert(area)
                                } else {
                                    manualChecks.remove(area)
                                    manualNotes[area] = ""
                                }
                            }
                        )
                    )
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .disabled(reviewFrozen)
                }
            }

            if !automaticallyCovered && manualChecks.contains(area) {
                TextField(
                    "Kurze Beobachtung festhalten …",
                    text: Binding(
                        get: { manualNotes[area] ?? "" },
                        set: { manualNotes[area] = $0 }
                    )
                )
                .textFieldStyle(.roundedBorder)

                Text("Nur eine konkrete Notiz zählt als Review-Evidenz.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var manualReviewAreas: [CreatorQualityArea] {
        [
            .packaging,
            .retentionStructure,
            .audio,
            .captions,
            .visualComposition
        ]
    }

    private func areaTitle(_ area: CreatorQualityArea) -> String {
        switch area {
        case .packaging: return "Packaging"
        case .retentionStructure: return "Retention-Struktur"
        case .audio: return "Audio"
        case .captions: return "Captions"
        case .visualComposition: return "Visuals"
        case .demandFit: return "Demand Fit"
        case .rightsAndPolicy: return "Rechte & Policy"
        case .renderIntegrity: return "Renderintegrität"
        }
    }

    private func areaQuestion(_ area: CreatorQualityArea) -> String {
        switch area {
        case .packaging:
            return "Versprechen Titel und Thumbnail ehrlich, klar und passend, was das Video tatsächlich liefert?"
        case .retentionStructure:
            return "Startet das Video ohne unnötigen Leerlauf und bleibt die Struktur verständlich und fokussiert?"
        case .audio:
            return "Ist Sprache verständlich, ohne hörbares Clipping, störende Pegelsprünge oder dominante Nebengeräusche?"
        case .captions:
            return "Stimmen Captions bei einer Stichprobe mit dem gesprochenen Inhalt und Timing überein?"
        case .visualComposition:
            return "Sind Motiv, Crop, Overlays und Lesbarkeit über die relevanten Abschnitte visuell sauber?"
        case .demandFit:
            return "Passt das Thema zur dokumentierten Nachfrage?"
        case .rightsAndPolicy:
            return "Sind Rechte und Plattformregeln belegt?"
        case .renderIntegrity:
            return "Ist das Render-Artefakt technisch valide?"
        }
    }

    private var targetSection: some View {
        GroupBox("Ziel") {
            VStack(alignment: .leading, spacing: 6) {
                Label(project.targetChannelID, systemImage: "person.crop.rectangle")
                    .font(.callout.monospaced())
                Text("Dieser Zielkanal ist Teil des Projekts und kann beim Publishing nicht still überschrieben werden.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 6)
        }
    }

    private var reviewPanel: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Release-Readiness")
                    .font(.title3.bold())

                qualityRow(
                    title: "Rechte & Policy",
                    area: .rightsAndPolicy
                )
                qualityRow(
                    title: "Renderintegrität",
                    area: .renderIntegrity
                )
                qualityRow(
                    title: "Packaging",
                    area: .packaging
                )
                qualityRow(
                    title: "Retention-Struktur",
                    area: .retentionStructure
                )
                qualityRow(
                    title: "Audio",
                    area: .audio
                )
                qualityRow(
                    title: "Captions",
                    area: .captions
                )
                qualityRow(
                    title: "Visuals",
                    area: .visualComposition
                )

                Divider()

                if missingAreas.isEmpty {
                    Label("Alle geforderten Qualitätsbereiche sind belegt.", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                } else {
                    VStack(alignment: .leading, spacing: 6) {
                        Label(
                            "\(missingAreas.count) Prüfbereiche fehlen",
                            systemImage: "exclamationmark.triangle"
                        )
                        .font(.headline)

                        Text("Blackstock schaltet Publishing erst frei, wenn diese Bereiche durch reale Analyzer oder eine nachvollziehbare Review-Evidenz abgedeckt sind.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if currentStage == .packaging {
                    Button("Review abschließen") {
                        do {
                            let review = qualityReview
                            try session.savePublishPreparation(
                                package: draftPackage,
                                qualityReview: review
                            )
                            persistedReview = review
                            _ = session.advanceActiveProject(
                                to: .review
                            )
                        } catch {
                            session.errorMessage = "Review konnte nicht gespeichert werden: \(error.localizedDescription)"
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(
                        !missingAreas.isEmpty
                        || draftPackage.metadata.title.isEmpty
                    )

                    Text("Der Review-Snapshot wird vor dem Statuswechsel gespeichert. Noch keine Remote-Aktion.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                } else if currentStage == .review
                            || currentStage == .publishing
                            || currentStage == .published {
                    publishingAuthorizationPanel
                }
            }
            .padding(20)
        }
        .background(Color.primary.opacity(0.02))
    }

    @ViewBuilder
    private var publishingAuthorizationPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(
                "Review gespeichert",
                systemImage: "checkmark.seal.fill"
            )
            .foregroundStyle(.green)

            if session.publishingAuthorizedChannelID
                == project.targetChannelID {
                Label(
                    "Publishing-Berechtigung für diesen Zielkanal verifiziert",
                    systemImage: "person.crop.circle.badge.checkmark"
                )
                .font(.caption)

                Text("Der echte Upload bleibt bis zur finalen Remote-Bestätigung getrennt. Public/Unlisted ist nur nach extern verifiziertem YouTube-Compliance-Gate verfügbar.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else {
                Button {
                    Task {
                        await session.authorizePublishing()
                    }
                } label: {
                    HStack {
                        if session.isAuthorizingPublishing {
                            ProgressView().controlSize(.small)
                        }
                        Label(
                            session.isAuthorizingPublishing
                                ? "Google-Autorisierung läuft …"
                                : "Publishing-Berechtigung aktivieren",
                            systemImage: "key"
                        )
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(session.isAuthorizingPublishing)

                if let plan = session.publishingScopePlan(),
                   plan.state == .reauthorizationRequired {
                    Text("Blackstock fordert gezielt die fehlenden YouTube-Upload-/Packaging-Berechtigungen an und prüft danach den Projekt-Zielkanal erneut.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            if let error = session.errorMessage {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }

    private func qualityRow(
        title: String,
        area: CreatorQualityArea
    ) -> some View {
        let covered = qualityReview.coveredAreas.contains(area)
        return HStack(spacing: 10) {
            Image(systemName: covered ? "checkmark.circle.fill" : "circle.dashed")
                .foregroundStyle(covered ? .green : .secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.callout.weight(.semibold))
                Text(covered ? "Belegt" : "Noch nicht geprüft")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    private static func imageMIMEType(for url: URL) -> String {
        switch url.pathExtension.lowercased() {
        case "png": return "image/png"
        case "webp": return "image/webp"
        default: return "image/jpeg"
        }
    }

    private static func captionMIMEType(for url: URL) -> String {
        switch url.pathExtension.lowercased() {
        case "vtt": return "text/vtt"
        case "srt": return "application/x-subrip"
        default: return "text/plain"
        }
    }
}
#endif
