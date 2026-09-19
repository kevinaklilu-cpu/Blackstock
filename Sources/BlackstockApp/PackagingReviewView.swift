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
    let audioTechnicalAssessment: AudioTechnicalAssessment?
    let audioSignalAssessment: AudioSignalAssessment?
    let storyboard: StoryboardPlan?

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
    @State private var useStoryboardChapters = false
    @State private var thumbnailAssessment: ThumbnailTechnicalAssessment?
    @State private var packagingVariants: PackagingVariantSet
    @State private var showFinalPublishConfirmation = false

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
        generatedCaptionURL: URL?,
        audioTechnicalAssessment: AudioTechnicalAssessment?,
        audioSignalAssessment: AudioSignalAssessment?,
        storyboard: StoryboardPlan?
    ) {
        self.session = session
        self.project = project
        self.asset = asset
        self.artifact = artifact
        self.transcript = transcript
        self.generatedCaptionURL = generatedCaptionURL
        self.audioTechnicalAssessment = audioTechnicalAssessment
        self.audioSignalAssessment = audioSignalAssessment
        self.storyboard = storyboard
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
        let savedThumbnailURL = saved?.package.thumbnail?.fileURL
        _thumbnailURL = State(initialValue: savedThumbnailURL)
        _thumbnailAssessment = State(
            initialValue: savedThumbnailURL.flatMap {
                try? ThumbnailTechnicalInspector().inspect(url: $0)
            }
        )
        _captionTracks = State(
            initialValue: saved?.package.captions ?? []
        )
        _persistedReview = State(
            initialValue: saved?.qualityReview
        )
        _packagingVariants = State(
            initialValue: saved?.packagingVariants
                ?? PackagingVariantSet()
        )

        if saved == nil, let generatedCaptionURL {
            let language = transcript?.localeIdentifier ?? "de-DE"
            _captionTracks = State(
                initialValue: [
                    PublishCaptionTrack(
                        language: language,
                        name: "Blackstock Untertitel",
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
            captionURL: generatedCaptionURL,
            audioTechnicalAssessment: audioTechnicalAssessment,
            audioSignalAssessment: audioSignalAssessment,
            thumbnailAssessment: thumbnailAssessment
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
                description: effectiveDescription,
                tags: tagsArray,
                categoryID: nil,
                defaultLanguage: session.contentLanguage,
                defaultAudioLanguage: transcript?.localeIdentifier
                    ?? session.contentLanguage,
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
                    chaptersSection
                    packagingAssetsSection
                    packagingVariantsSection
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
            if case .success(let urls) = result,
               let url = urls.first {
                do {
                    let durableURL = try session.importPackagingAsset(
                        from: url,
                        projectID: project.id,
                        kind: .thumbnail
                    )
                    thumbnailURL = durableURL
                    thumbnailAssessment = try ThumbnailTechnicalInspector()
                        .inspect(url: durableURL)
                    session.errorMessage = nil
                } catch {
                    session.errorMessage = "Vorschaubild konnte nicht sicher in den Projekt-Arbeitsbereich übernommen werden: \(error.localizedDescription)"
                }
            }
        }
        .confirmationDialog(
            "Wirklich zu YouTube hochladen?",
            isPresented: $showFinalPublishConfirmation,
            titleVisibility: .visible
        ) {
            Button("Jetzt hochladen", role: .destructive) {
                Task {
                    await session.publishPreparedReview(
                        artifact: artifact,
                        asset: asset,
                        userConfirmed: true
                    )
                }
            }
            Button("Abbrechen", role: .cancel) {}
        } message: {
            Text(
                "Zielkanal: \(project.targetChannelID) · Sichtbarkeit: \(draftPackage.metadata.privacyStatus.rawValue). Diese Aktion erstellt bzw. setzt reale YouTube-Ressourcen."
            )
        }
        .fileImporter(
            isPresented: $showCaptionImporter,
            allowedContentTypes: ["vtt", "srt"].compactMap {
                UTType(filenameExtension: $0)
            },
            allowsMultipleSelection: false
        ) { result in
            if case .success(let urls) = result, let url = urls.first {
                do {
                    let durableURL = try session.importPackagingAsset(
                        from: url,
                        projectID: project.id,
                        kind: .caption
                    )
                    let language = Locale.current.language.languageCode?.identifier ?? "de"
                    captionTracks = [
                        PublishCaptionTrack(
                            language: language,
                            name: "Blackstock Untertitel",
                            fileURL: durableURL,
                            mimeType: Self.captionMIMEType(for: durableURL)
                        )
                    ]
                    session.errorMessage = nil
                } catch {
                    session.errorMessage = "Untertiteldatei konnte nicht sicher in den Projekt-Arbeitsbereich übernommen werden: \(error.localizedDescription)"
                }
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Veröffentlichungspaket & Prüfung")
                        .font(.title2.bold())
                    Text("Alles prüfen, bevor Blackstock eine externe Aktion zulässt.")
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
                    .accessibilityLabel("YouTube-Beschreibung")
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

    private var storyboardChapters: [YouTubeChapter] {
        guard let storyboard else { return [] }
        return StoryboardChapterBuilder().build(from: storyboard)
    }

    private var chapterValidationError: YouTubeChapterValidationError? {
        do {
            try YouTubeChapterValidator().validate(
                storyboardChapters,
                videoDurationSeconds: asset.durationSeconds
            )
            return nil
        } catch let error as YouTubeChapterValidationError {
            return error
        } catch {
            return .fewerThanThreeChapters
        }
    }

    private var effectiveDescription: String {
        guard useStoryboardChapters,
              chapterValidationError == nil else {
            return description
        }
        return YouTubeDescriptionComposer().appendingChapters(
            description: description,
            chapters: storyboardChapters
        )
    }

    private var chaptersSection: some View {
        GroupBox("Kapitel") {
            VStack(alignment: .leading, spacing: 10) {
                Toggle(
                    "Kapitel aus dem Storyboard in die Beschreibung übernehmen",
                    isOn: $useStoryboardChapters
                )
                .disabled(
                    reviewFrozen
                    || storyboardChapters.isEmpty
                    || chapterValidationError != nil
                )

                if storyboardChapters.isEmpty {
                    Text("Noch keine Storyboard-Beats mit Zeitbereichen vorhanden.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if let error = chapterValidationError {
                    Label(
                        chapterValidationMessage(error),
                        systemImage: "exclamationmark.triangle"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                } else {
                    ForEach(storyboardChapters) { chapter in
                        HStack {
                            Text(YouTubeDescriptionComposer.timestamp(chapter.startSeconds))
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                            Text(chapter.title)
                                .font(.caption)
                            Spacer()
                        }
                    }
                    Text("Validiert: 00:00-Start, mindestens drei Kapitel, aufsteigend und jeweils mindestens zehn Sekunden.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 6)
        }
    }

    private func chapterValidationMessage(
        _ error: YouTubeChapterValidationError
    ) -> String {
        switch error {
        case .fewerThanThreeChapters:
            return "YouTube benötigt mindestens drei Kapitel."
        case .firstChapterMustStartAtZero:
            return "Das erste Kapitel muss bei 00:00 beginnen."
        case .nonAscendingTimestamps:
            return "Kapitel müssen zeitlich streng aufsteigend sein."
        case .chapterShorterThanTenSeconds(let index):
            return "Kapitel \(index + 1) ist kürzer als zehn Sekunden."
        case .emptyTitle(let index):
            return "Kapitel \(index + 1) hat keinen Titel."
        }
    }

    private var packagingAssetsSection: some View {
        GroupBox("Vorschaubild & Untertitel") {
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

                if let assessment = thumbnailAssessment {
                    thumbnailTechnicalFacts(assessment)
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

    @ViewBuilder
    private func thumbnailTechnicalFacts(
        _ assessment: ThumbnailTechnicalAssessment
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Technische Thumbnail-Prüfung")
                .font(.caption.weight(.semibold))

            Text(
                "\(assessment.snapshot.width) × \(assessment.snapshot.height) · "
                + ByteCountFormatter.string(
                    fromByteCount: assessment.snapshot.fileSizeBytes,
                    countStyle: .file
                )
                + " · \(assessment.snapshot.mimeType)"
            )
            .font(.caption)
            .foregroundStyle(.secondary)

            ForEach(assessment.uploadBlockers, id: \.self) { blocker in
                Label(
                    thumbnailBlockerText(blocker),
                    systemImage: "xmark.octagon.fill"
                )
                .font(.caption)
                .foregroundStyle(.red)
            }

            ForEach(assessment.bestPracticeFindings, id: \.self) { finding in
                Label(
                    thumbnailBestPracticeText(finding),
                    systemImage: "info.circle"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            if assessment.uploadCompatible
                && assessment.bestPracticeFindings.isEmpty {
                Label(
                    "Technisch upload-kompatibel und ohne aktuelle Format-Hinweise.",
                    systemImage: "checkmark.circle.fill"
                )
                .font(.caption)
                .foregroundStyle(.green)
            }

            Text("Technische Kompatibilität ist keine Bewertung der kreativen Thumbnail-Qualität.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(8)
        .background(
            Color.primary.opacity(0.035),
            in: RoundedRectangle(cornerRadius: 8)
        )
    }

    private func thumbnailBlockerText(
        _ blocker: ThumbnailUploadBlocker
    ) -> String {
        switch blocker {
        case .unsupportedMimeType:
            return "Dieses Dateiformat wird vom YouTube-Thumbnail-Upload nicht unterstützt."
        case .exceedsFiftyMB:
            return "Die Datei überschreitet das aktuelle 50-MB-Uploadlimit."
        case .invalidDimensions:
            return "Die Bildabmessungen konnten nicht gültig bestimmt werden."
        }
    }

    private func thumbnailBestPracticeText(
        _ finding: ThumbnailBestPracticeFinding
    ) -> String {
        switch finding {
        case .belowRecommendedMinimumWidth:
            return "YouTube empfiehlt für Video-Vorschaubilder mindestens 640 px Breite."
        case .notSixteenByNine:
            return "Für normale Videos empfiehlt YouTube 16:9."
        }
    }

    private var packagingVariantsSection: some View {
        GroupBox("Varianten des Veröffentlichungspakets") {
            VStack(alignment: .leading, spacing: 10) {
                Text("Bis zu drei Titel-/Thumbnail-Kombinationen vorbereiten. Blackstock markiert keinen Gewinner ohne echte YouTube-Testdaten.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                ForEach(packagingVariants.variants) { variant in
                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(variant.title)
                                .font(.callout.weight(.semibold))
                                .lineLimit(1)
                            Text(
                                variant.thumbnailURL?.lastPathComponent
                                    ?? "Kein Thumbnail"
                            )
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button(role: .destructive) {
                            try? packagingVariants.remove(id: variant.id)
                        } label: {
                            Image(systemName: "trash")
                        }
                        .accessibilityLabel("Variante des Veröffentlichungspakets löschen")
                        .accessibilityHint(variant.title)
                        .buttonStyle(.borderless)
                        .disabled(reviewFrozen)
                    }
                    .padding(8)
                    .background(
                        Color.primary.opacity(0.035),
                        in: RoundedRectangle(cornerRadius: 8)
                    )
                }

                Button {
                    do {
                        _ = try packagingVariants.add(
                            title: title,
                            thumbnailURL: thumbnailURL,
                            note: "Kandidat für Veröffentlichungspaket",
                            at: Date()
                        )
                    } catch {
                        session.errorMessage = "Variante konnte nicht hinzugefügt werden: \(error.localizedDescription)"
                    }
                } label: {
                    Label(
                        "Aktuellen Titel/Thumbnail als Variante sichern",
                        systemImage: "plus"
                    )
                }
                .buttonStyle(.bordered)
                .disabled(
                    reviewFrozen
                    || packagingVariants.variants.count >= 3
                    || title.trimmingCharacters(
                        in: .whitespacesAndNewlines
                    ).isEmpty
                    || (thumbnailAssessment?.uploadCompatible == false)
                )

                Text("\(packagingVariants.variants.count) von 3 Varianten")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 6)
        }
    }

    private var manualReviewSection: some View {
        GroupBox("Qualitative Prüfung") {
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
                    .accessibilityLabel("\(areaTitle(area)) geprüft")
                    .accessibilityHint(areaQuestion(area))
                    .disabled(reviewFrozen)
                }
            }

            if area == .audio {
                audioFacts
            }

            if !automaticallyCovered && manualChecks.contains(area) {
                TextField(
                    "Kurze Beobachtung festhalten …",
                    text: Binding(
                        get: { manualNotes[area] ?? "" },
                        set: { manualNotes[area] = $0 }
                    )
                )
                .accessibilityLabel("Prüfnotiz: \(areaTitle(area))")
                .accessibilityHint("Konkrete Beobachtung als Prüf-Evidenz festhalten")
                .textFieldStyle(.roundedBorder)

                Text("Nur eine konkrete Notiz zählt als Prüf-Evidenz.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var audioFacts: some View {
        if let technical = audioTechnicalAssessment {
            VStack(alignment: .leading, spacing: 3) {
                Text("Automatische Messwerte")
                    .font(.caption.weight(.semibold))
                if technical.snapshot.hasAudioTrack {
                    if let sampleRate = technical.snapshot.sampleRateHz {
                        Text("Sample-Rate: \(Int(sampleRate.rounded())) Hz")
                    }
                    if let channels = technical.snapshot.channelCount {
                        Text("Kanäle: \(channels)")
                    }
                } else {
                    Text("Keine Audiospur erkannt.")
                }

                if let signal = audioSignalAssessment {
                    if let peak = signal.snapshot.peakDBFS {
                        Text("Peak: \(String(format: "%.2f", peak)) dBFS")
                    }
                    if let rms = signal.snapshot.rmsDBFS {
                        Text("RMS: \(String(format: "%.2f", rms)) dBFS")
                    }
                    Text("Full-Scale-Samples: \(signal.snapshot.fullScaleSampleCount)")
                }

                Text("Diese Messwerte sind Evidenz, ersetzen aber nicht die hörbare Prüfung auf Verständlichkeit und Störgeräusche.")
                    .foregroundStyle(.secondary)
            }
            .font(.caption)
            .padding(8)
            .background(
                Color.primary.opacity(0.035),
                in: RoundedRectangle(cornerRadius: 8)
            )
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
        case .packaging: return "Veröffentlichungspaket"
        case .retentionStructure: return "Zuschauerbindungs-Struktur"
        case .audio: return "Audio"
        case .captions: return "Untertitel"
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
            return "Stimmen die Untertitel bei einer Stichprobe mit dem gesprochenen Inhalt und Timing überein?"
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
                Text("Dieser Zielkanal ist Teil des Projekts und kann bei der Veröffentlichung nicht still überschrieben werden.")
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
                    title: "Veröffentlichungspaket",
                    area: .packaging
                )
                qualityRow(
                    title: "Zuschauerbindungs-Struktur",
                    area: .retentionStructure
                )
                qualityRow(
                    title: "Audio",
                    area: .audio
                )
                qualityRow(
                    title: "Untertitel",
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

                        Text("Blackstock schaltet die Veröffentlichung erst frei, wenn diese Bereiche durch reale Analysewerkzeuge oder eine nachvollziehbare Prüf-Evidenz abgedeckt sind.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if currentStage == .packaging {
                    Button("Prüfung abschließen") {
                        do {
                            let review = qualityReview
                            try session.savePublishPreparation(
                                package: draftPackage,
                                qualityReview: review,
                                packagingVariants: packagingVariants
                            )
                            persistedReview = review
                            _ = session.advanceActiveProject(
                                to: .review
                            )
                        } catch {
                            session.errorMessage = "Prüfung konnte nicht gespeichert werden: \(error.localizedDescription)"
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(
                        !missingAreas.isEmpty
                        || draftPackage.metadata.title.isEmpty
                    )

                    Text("Der Prüfstand wird vor dem Statuswechsel gespeichert. Noch keine externe Aktion.")
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
                "Prüfung gespeichert",
                systemImage: "checkmark.seal.fill"
            )
            .foregroundStyle(.green)

            if session.publishingAuthorizedChannelID
                == project.targetChannelID {
                Label(
                    "Veröffentlichungsberechtigung für diesen Zielkanal verifiziert",
                    systemImage: "person.crop.circle.badge.checkmark"
                )
                .font(.caption)

                Text("Der echte Upload bleibt bis zur finalen Bestätigung der externen Aktion getrennt. Öffentlich/Nicht gelistet ist nur nach extern verifiziertem YouTube-Compliance-Gate verfügbar.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                if currentStage == .review || currentStage == .publishing {
                    Button {
                        showFinalPublishConfirmation = true
                    } label: {
                        HStack {
                            if session.isPublishing {
                                ProgressView().controlSize(.small)
                            }
                            Label(
                                session.isPublishing
                                    ? "Upload läuft …"
                                    : "Final zu YouTube hochladen …",
                                systemImage: "arrow.up.circle.fill"
                            )
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(session.isPublishing)
                }

                if let result = session.lastPublishingResult {
                    VStack(alignment: .leading, spacing: 4) {
                        Label(
                            "YouTube-Upload bestätigt",
                            systemImage: "checkmark.circle.fill"
                        )
                        .foregroundStyle(.green)
                        Text("Video-ID: \(result.videoID)")
                            .font(.caption.monospaced())
                            .textSelection(.enabled)
                        if result.uploadReused {
                            Text("Der bereits protokollierte YouTube-Upload wurde wiederverwendet; kein Doppel-Upload.")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
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
                                : "Veröffentlichungsberechtigung aktivieren",
                            systemImage: "key"
                        )
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(session.isAuthorizingPublishing)

                if let plan = session.publishingScopePlan(),
                   plan.state == .reauthorizationRequired {
                    Text("Blackstock fordert gezielt die fehlenden YouTube-Upload- und Veröffentlichungspaket-Berechtigungen an und prüft danach den Projekt-Zielkanal erneut.")
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
