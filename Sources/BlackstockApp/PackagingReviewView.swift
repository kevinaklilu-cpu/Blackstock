#if os(macOS)
import SwiftUI
import UniformTypeIdentifiers
import BlackstockCore

struct PackagingReviewView: View {
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
        project: BlackstockProject,
        asset: ProductionMediaAsset,
        artifact: RenderArtifact,
        transcript: LocalTranscript?,
        generatedCaptionURL: URL?
    ) {
        self.project = project
        self.asset = asset
        self.artifact = artifact
        self.transcript = transcript
        self.generatedCaptionURL = generatedCaptionURL
        _title = State(initialValue: project.title)

        if let generatedCaptionURL {
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

    private var qualityReview: CreatorQualityReview {
        DeterministicQualityEvidenceBuilder().build(
            projectID: project.id,
            asset: asset,
            artifact: artifact,
            transcript: transcript,
            captionURL: generatedCaptionURL
        )
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
                    Text("Nicht gelistet").tag(YouTubePrivacyStatus.unlisted)
                    Text("Öffentlich").tag(YouTubePrivacyStatus.publicVideo)
                }
                .pickerStyle(.segmented)

                Toggle("Für Kinder erstellt", isOn: $madeForKids)
            }
            .padding(.vertical, 6)
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

                Button("Publishing vorbereiten") {
                    _ = draftPackage
                }
                .buttonStyle(.borderedProminent)
                .disabled(
                    !missingAreas.isEmpty
                    || draftPackage.metadata.title.isEmpty
                )

                Text("Noch keine Remote-Aktion. Der Button bleibt gesperrt, solange Release-Gates fehlen.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(20)
        }
        .background(Color.primary.opacity(0.02))
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
