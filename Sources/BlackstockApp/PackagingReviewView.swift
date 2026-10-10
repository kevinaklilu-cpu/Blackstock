#if os(macOS)
import SwiftUI
import AVKit
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
    let audioLoudnessAssessment: AudioLoudnessAssessment?
    let storyboard: StoryboardPlan?
    let storyDraft: StoryPublicationDraft?

    @Environment(\.dismiss) private var dismiss

    @State private var hasRestoredEditorDraft = false
    @State private var editorialStatus: String?
    @State private var isDraftingEditorial = false
    @State private var title: String
    @State private var description = ""
    @State private var tags = ""
    @State private var privacyStatus: YouTubePrivacyStatus = .privateVideo
    @State private var madeForKids = false
    @State private var categoryID = ""
    @State private var containsSyntheticMedia = false
    @State private var thumbnailURL: URL?
    @State private var thumbnailOptions: [URL] = []
    @State private var captionTracks: [PublishCaptionTrack] = []
    @State private var showThumbnailImporter = false
    @State private var thumbnailFramePosition = 0.25
    @State private var isGeneratingThumbnail = false
    @State private var isGeneratingThumbnailChoices = false
    @State private var showCaptionImporter = false
    @State private var persistedReview: CreatorQualityReview?
    @State private var useStoryboardChapters = false
    @State private var thumbnailAssessment: ThumbnailTechnicalAssessment?
    @State private var packagingVariants: PackagingVariantSet
    @State private var showFinalPublishConfirmation = false
    @State private var isCheckingQuality = false
    @State private var isPreparingUpload = false
    @State private var uploadPreparationStatus: String?
    @State private var checkedAudioTechnical: AudioTechnicalAssessment?
    @State private var checkedAudioSignal: AudioSignalAssessment?
    @State private var checkedAudioLoudness: AudioLoudnessAssessment?
    @State private var previewPlayer = AVPlayer()

    private func improveEditorialDraft() async {
        guard !isDraftingEditorial, let transcript else { return }
        isDraftingEditorial = true
        defer { isDraftingEditorial = false }
        let previousTitle = title, previousDescription = description, previousTags = tags
        guard let draft = await LocalClipEditorialAdvisor().publication(transcript: transcript) else {
            editorialStatus = "Lokale KI nicht verfügbar. Ausschnittbezogene Textvorschläge bleiben bearbeitbar."
            return
        }
        guard title == previousTitle, description == previousDescription, tags == previousTags else {
            editorialStatus = "Deine laufenden Textänderungen wurden beibehalten."
            return
        }
        title = draft.title
        description = draft.description
        tags = draft.tags.joined(separator: ", ")
        editorialStatus = "Lokal aus diesem Ausschnitt formuliert · bitte vor dem Upload prüfen."
    }

    private let requiredQualityAreas = AutomaticPublishReview.requiredAreas

    init(
        session: BlackstockSession,
        project: BlackstockProject,
        asset: ProductionMediaAsset,
        artifact: RenderArtifact,
        transcript: LocalTranscript?,
        generatedCaptionURL: URL?,
        audioTechnicalAssessment: AudioTechnicalAssessment?,
        audioSignalAssessment: AudioSignalAssessment?,
        audioLoudnessAssessment: AudioLoudnessAssessment?,
        storyboard: StoryboardPlan?,
        suggestedTitle: String? = nil,
        storyDraft: StoryPublicationDraft? = nil
    ) {
        self.session = session
        self.project = project
        self.asset = asset
        self.artifact = artifact
        self.transcript = transcript
        self.generatedCaptionURL = generatedCaptionURL
        self.audioTechnicalAssessment = audioTechnicalAssessment
        self.audioSignalAssessment = audioSignalAssessment
        self.audioLoudnessAssessment = audioLoudnessAssessment
        self.storyboard = storyboard
        self.storyDraft = storyDraft
        let loaded = session.loadPublishPreparation(
            projectID: project.id
        )
        let saved = loaded?.package.renderArtifactID == artifact.id ? loaded : nil
        let editorKey = "blackstock.publication.editor." + project.id.uuidString + "." + artifact.id.uuidString
        let editorDraft = UserDefaults.standard.data(forKey: editorKey)
            .flatMap { try? JSONDecoder().decode(PublicationEditorDraft.self, from: $0) }

        _hasRestoredEditorDraft = State(initialValue: editorDraft != nil)
        let normalizedSuggestedTitle =
            suggestedTitle?
            .trimmingCharacters(
                in: .whitespacesAndNewlines
            )
        _title = State(
            initialValue:
                editorDraft?.title ?? saved?.package.metadata.title
                ?? (
                    normalizedSuggestedTitle?.isEmpty == false
                    ? String(normalizedSuggestedTitle!.prefix(100))
                    : (storyDraft?.title ?? "Titel für diesen Ausschnitt ergänzen")
                )
        )
        _description = State(
            initialValue: editorDraft?.description ?? PublicationEditorDraft.removingGeneratedSourceFooter(
                saved?.package.metadata.description
                ?? storyDraft?.description
                ?? Self.suggestedDescription(title: project.title, transcript: transcript)
            )
        )
        _tags = State(
            initialValue: editorDraft?.tags ?? saved?.package.metadata.tags
                .joined(separator: ", ")
                ?? storyDraft?.tags.joined(separator: ", ")
                ?? StoryTopicMatcher().searchQuery(for: project.title).split(separator: " ").joined(separator: ", ")
        )
        _privacyStatus = State(
            initialValue: saved?.package.metadata.privacyStatus
                ?? .privateVideo
        )
        _madeForKids = State(
            initialValue: saved?.package.metadata
                .selfDeclaredMadeForKids
                ?? (session.channelAudienceSetting == .madeForKids)
        )
        _categoryID = State(
            initialValue:
                saved?.package.metadata.categoryID
                ?? session.projectChannelCategoryID(
                    for: project.id
                )
                ?? session.channelCategoryID
        )
        _containsSyntheticMedia = State(
            initialValue:
                saved?.package.metadata.containsSyntheticMedia
                ?? false
        )
        let availableOptions = (editorDraft?.thumbnailOptions ?? []).filter {
            FileManager.default.fileExists(atPath: $0.path)
        }
        let preferredThumbnail = editorDraft?.thumbnailURL ?? saved?.package.thumbnail?.fileURL
        let savedThumbnailURL = preferredThumbnail.flatMap {
            FileManager.default.fileExists(atPath: $0.path) ? $0 : nil
        } ?? availableOptions.first
        _thumbnailURL = State(initialValue: savedThumbnailURL)
        _thumbnailOptions = State(initialValue: availableOptions.isEmpty ? (savedThumbnailURL.map { [$0] } ?? []) : availableOptions)
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
            audioTechnicalAssessment: checkedAudioTechnical ?? audioTechnicalAssessment,
            audioSignalAssessment: checkedAudioSignal ?? audioSignalAssessment,
            audioLoudnessAssessment: checkedAudioLoudness ?? audioLoudnessAssessment,
            thumbnailAssessment: thumbnailAssessment
        )
    }

    private var qualityReview: CreatorQualityReview {
        if reviewFrozen, let persistedReview {
            return persistedReview
        }
        return AutomaticPublishReview().build(base: automaticQualityReview, package: draftPackage)
    }

    private var currentStage: BlackstockStage {
        session.activeProject?.stage ?? project.stage
    }

    private var reviewFrozen: Bool {
        currentStage == .publishing
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

    private var targetChannelName: String {
        session.channels.first(where: { $0.id == project.targetChannelID })?.title ?? project.targetChannelID
    }

    private var visibilityLabel: String {
        switch privacyStatus {
        case .privateVideo: return "Privat"
        case .unlisted: return "Nicht gelistet"
        case .publicVideo: return "Öffentlich"
        }
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
                categoryID: categoryID.isEmpty
                    ? nil
                    : categoryID,
                defaultLanguage: session.contentLanguage,
                defaultAudioLanguage: transcript?.localeIdentifier
                    ?? session.contentLanguage,
                privacyStatus: privacyStatus,
                selfDeclaredMadeForKids: madeForKids,
                containsSyntheticMedia:
                    containsSyntheticMedia
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
                    BlackstockVideoPlayer(player: previewPlayer)
                        .aspectRatio(16.0 / 9.0, contentMode: .fit)
                    if let thumbnailURL, let image = NSImage(contentsOf: thumbnailURL) {
                        VStack(alignment: .leading, spacing: 8) {
                            Label("Dieses Vorschaubild wird hochgeladen", systemImage: "photo.fill")
                                .font(.headline)
                            Image(nsImage: image).resizable().scaledToFit()
                                .frame(maxWidth: .infinity, maxHeight: 240)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                                .accessibilityLabel("Ausgewähltes YouTube-Vorschaubild")
                        }.padding(14).blackstockSurface(raised: true)
                    } else if isGeneratingThumbnail {
                        ProgressView("Vorschaubild wird aus dem fertigen Video erstellt …")
                    }
                    metadataSection
                    DisclosureGroup("Vorschaubild anpassen und Untertiteldateien") {
                        packagingAssetsSection
                    }
                    DisclosureGroup("Kapitel und alternative Titel") {
                        chaptersSection
                        packagingVariantsSection
                    }
                    Text("Technische Prüfungen laufen automatisch. Schnittwirkung, Bildgestaltung und inhaltliche Richtigkeit sind Hinweise zur Vorschau – keine Pflichtnotizen für den Upload.")
                        .font(.caption).foregroundStyle(.secondary)
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
                    if !thumbnailOptions.contains(durableURL) { thumbnailOptions.append(durableURL) }
                    thumbnailURL = durableURL
                    thumbnailAssessment = try ThumbnailTechnicalInspector()
                        .inspect(url: durableURL)
                    session.errorMessage = nil
                } catch {
                    session.errorMessage = "Vorschaubild konnte nicht sicher in den Projekt-Arbeitsbereich übernommen werden: \(error.localizedDescription)"
                }
            }
        }
        .alert(
            "Video zu YouTube hochladen",
            isPresented: $showFinalPublishConfirmation
        ) {
            Button("Jetzt hochladen") {
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
                "\(targetChannelName) · \(visibilityLabel)\n\(title)\nVideo, Vorschaubild und ausgewählte Untertitel werden hochgeladen."
            )
        }
        .task {
            previewPlayer.replaceCurrentItem(with: AVPlayerItem(url: artifact.fileURL))
            await session.ensureYouTubePublishingOptionsLoaded()
            if categoryID.isEmpty {
                categoryID =
                    session.projectChannelCategoryID(
                        for: project.id
                    )
                    ?? session.channelCategoryID
            }
            if thumbnailOptions.count < 3, !reviewFrozen {
                await generateThumbnailChoices()
            }
            await checkAudioAutomatically()
            if persistedReview == nil, title == storyDraft?.title,
               !hasRestoredEditorDraft {
                await improveEditorialDraft()
            }
        }
        .task(id: editorDraftSnapshot) {
            do { try await Task.sleep(for: .milliseconds(350)) } catch { return }
            saveEditorDraft()
        }
        .onDisappear { previewPlayer.pause(); saveEditorDraft() }
        .onChange(of: session.activeProject?.stage) { stage in
            if stage == .published {
                dismiss()
            }
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
                    Text("Bereit für YouTube")
                        .font(.title2.bold())
                    Text("Vorschläge sind vorbereitet. Passe sie bei Bedarf an und starte den Upload.")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Schließen") { dismiss() }
            }

            Label("Fertiges Video ausgewählt", systemImage: "checkmark.seal")
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    private var metadataSection: some View {
        GroupBox("YouTube-Metadaten") {
            VStack(alignment: .leading, spacing: 12) {
                Button(isDraftingEditorial ? "Textvorschläge werden formuliert …" : "Eigene Textvorschläge formulieren") {
                    Task { await improveEditorialDraft() }
                }
                .disabled(isDraftingEditorial || transcript == nil)
                if let editorialStatus { Text(editorialStatus).font(.caption).foregroundStyle(.secondary) }
                TextField("Titel", text: $title)
                    .textFieldStyle(.roundedBorder)

                if let storyDraft {
                    Menu("Weitere Titelvorschläge") {
                        ForEach(storyDraft.alternativeTitles, id: \.self) { suggestion in
                            Button(suggestion) { title = suggestion }
                        }
                    }
                    Text("Vorschlag aus dem gewählten Ausschnitt. Prüfe Titel und Beschreibung vor dem Upload.")
                        .font(.caption).foregroundStyle(.secondary)
                }
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

                Picker(
                    "Kanal-Kategorie / YouTube-Kategorie",
                    selection: $categoryID
                ) {
                    if !categoryID.isEmpty,
                       !session.youtubeVideoCategories.contains(
                            where: { $0.id == categoryID }
                       ) {
                        Text("Kategorie \(categoryID)")
                            .tag(categoryID)
                    }
                    ForEach(
                        session.youtubeVideoCategories
                    ) { category in
                        Text(category.title)
                            .tag(category.id)
                    }
                }
                .pickerStyle(.menu)

                Picker("Sichtbarkeit", selection: $privacyStatus) {
                    Text("Privat").tag(YouTubePrivacyStatus.privateVideo)
                    if session.publicPublishingAllowed {
                        Text("Nicht gelistet").tag(YouTubePrivacyStatus.unlisted)
                        Text("Öffentlich").tag(YouTubePrivacyStatus.publicVideo)
                    }
                }
                .pickerStyle(.segmented)
                if !session.publicPublishingAllowed {
                    Text("Diese Anbindung unterstützt derzeit private Uploads. Nach dem Upload kannst du das Video über den Link in YouTube Studio verwalten.")
                        .font(.caption).foregroundStyle(.secondary)
                }

                Picker(
                    "YouTube-Zielgruppe",
                    selection: $madeForKids
                ) {
                    Text("Nicht speziell für Kinder")
                        .tag(false)
                    Text("Speziell für Kinder")
                        .tag(true)
                }
                .pickerStyle(.segmented)

                Toggle(
                    "Realistisch veränderte oder synthetische Inhalte",
                    isOn: $containsSyntheticMedia
                )
                Text(
                    "Diese Angabe wird beim Upload als YouTube-Kennzeichnung für veränderte oder synthetische Medien übertragen."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
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
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Vorschaubild")
                                .font(.headline)
                            Text(thumbnailURL?.lastPathComponent ?? "Noch kein Vorschaubild gewählt")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Auswählen …") {
                            showThumbnailImporter = true
                        }
                        Button {
                            Task {
                                await generateThumbnailFromRender()
                            }
                        } label: {
                            HStack {
                                if isGeneratingThumbnail {
                                    ProgressView()
                                        .controlSize(.small)
                                }
                                Label(
                                    isGeneratingThumbnail
                                        ? "Erzeugt …"
                                        : "Aus Video erzeugen",
                                    systemImage: "photo.badge.plus"
                                )
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(isGeneratingThumbnail || isGeneratingThumbnailChoices)
                    }

                    if thumbnailOptions.count > 1 {
                        ScrollView(.horizontal) {
                            HStack(spacing: 12) {
                                ForEach(thumbnailOptions, id: \.self) { option in
                                    if let image = NSImage(contentsOf: option) {
                                        Button {
                                            thumbnailURL = option
                                            thumbnailAssessment = try? ThumbnailTechnicalInspector().inspect(url: option)
                                        } label: {
                                            Image(nsImage: image).resizable().scaledToFit()
                                                .frame(width: 160, height: 90)
                                                .overlay(RoundedRectangle(cornerRadius: 8)
                                                    .stroke(thumbnailURL == option ? Color.accentColor : Color.clear, lineWidth: 3))
                                        }
                                        .buttonStyle(.plain)
                                        .accessibilityLabel("Vorschaubild auswählen")
                                        .accessibilityAddTraits(thumbnailURL == option ? .isSelected : [])
                                    }
                                }
                            }.padding(4)
                        }
                    }

                    if let thumbnailURL, let image = NSImage(contentsOf: thumbnailURL) {
                        Image(nsImage: image)
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: .infinity, maxHeight: 260)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                            .accessibilityLabel("Erzeugtes Vorschaubild für YouTube")
                    }

                    HStack(spacing: 10) {
                        Text("Frame")
                            .font(.caption.weight(.semibold))
                        Slider(
                            value: $thumbnailFramePosition,
                            in: 0.05...0.95
                        )
                        .accessibilityLabel("Zeitpunkt für Vorschaubild")
                        .accessibilityValue(
                            String(
                                format: "%.0f Prozent",
                                thumbnailFramePosition * 100
                            )
                        )
                        Text(
                            String(
                                format: "%.0f%%",
                                thumbnailFramePosition * 100
                            )
                        )
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                    }

                    Text("Blackstock nimmt lokal einen Frame aus dem validierten Render und erzeugt daraus ein zentriertes 1280×720-JPEG. Die kreative Auswahl bleibt bei dir.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
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

    private var editorDraftSnapshot: PublicationEditorDraft {
        .init(title: title, description: description, tags: tags,
              thumbnailURL: thumbnailURL, thumbnailOptions: thumbnailOptions)
    }

    private func saveEditorDraft() {
        guard let data = try? JSONEncoder().encode(editorDraftSnapshot) else { return }
        UserDefaults.standard.set(data, forKey:
            "blackstock.publication.editor." + project.id.uuidString + "." + artifact.id.uuidString)
    }

    private func generateThumbnailChoices() async {
        guard !isGeneratingThumbnailChoices, !isGeneratingThumbnail else { return }
        isGeneratingThumbnailChoices = true
        defer { isGeneratingThumbnailChoices = false }
        let originalPosition = thumbnailFramePosition
        for position in [0.18, 0.42, 0.66] {
            guard !Task.isCancelled, thumbnailOptions.count < 3 else { break }
            thumbnailFramePosition = position
            await generateThumbnailFromRender(selectResult: false)
        }
        thumbnailFramePosition = originalPosition
        if thumbnailURL == nil, let first = thumbnailOptions.first {
            thumbnailURL = first
            thumbnailAssessment = try? ThumbnailTechnicalInspector().inspect(url: first)
        }
    }

    private func generateThumbnailFromRender(selectResult: Bool = true) async {
        guard !isGeneratingThumbnail, !Task.isCancelled else { return }
        isGeneratingThumbnail = true
        defer { isGeneratingThumbnail = false }

        let temporaryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "blackstock-thumbnail-\(UUID().uuidString)"
            )
            .appendingPathExtension("jpg")
        defer {
            try? FileManager.default.removeItem(at: temporaryURL)
        }

        do {
            _ = try await LocalThumbnailFrameGenerator().generate(
                videoURL: artifact.fileURL,
                normalizedPosition: thumbnailFramePosition,
                outputURL: temporaryURL
            )
            try Task.checkCancellation()
            let durableURL = try session.importPackagingAsset(
                from: temporaryURL,
                projectID: project.id,
                kind: .thumbnail
            )
            let assessment = try ThumbnailTechnicalInspector()
                .inspect(url: durableURL)
            if !thumbnailOptions.contains(durableURL) { thumbnailOptions.append(durableURL) }
            if selectResult {
                thumbnailURL = durableURL
                thumbnailAssessment = assessment
            }
            session.errorMessage = nil
        } catch is CancellationError {
            return
        } catch {
            session.errorMessage =
                "Vorschaubild konnte nicht lokal aus dem Video erzeugt werden: "
                + error.localizedDescription
        }
    }

    @ViewBuilder
    private func thumbnailTechnicalFacts(
        _ assessment: ThumbnailTechnicalAssessment
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Technische Vorschaubild-Prüfung")
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

            Text("Technische Kompatibilität ist keine Bewertung der kreativen Vorschaubild-Qualität.")
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
            return "Dieses Dateiformat wird vom YouTube-Vorschaubild-Upload nicht unterstützt."
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
                Text("Bis zu drei Titel-/Vorschaubild-Kombinationen vorbereiten. Blackstock markiert keinen Gewinner ohne echte YouTube-Testdaten.")
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
                                    ?? "Kein Vorschaubild"
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
                        "Aktuellen Titel/Vorschaubild als Variante sichern",
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

                if let loudness = audioLoudnessAssessment {
                    Divider()
                    Text("Professionelle Loudness-Messung")
                        .font(.caption.weight(.semibold))
                    if let integrated = loudness.snapshot.integratedLUFS {
                        Text("Integrated: \(String(format: "%.2f", integrated)) LUFS")
                    }
                    if let momentary = loudness.snapshot.maximumMomentaryLUFS {
                        Text("Max. Momentary: \(String(format: "%.2f", momentary)) LUFS")
                    }
                    if let shortTerm = loudness.snapshot.maximumShortTermLUFS {
                        Text("Max. Short-term: \(String(format: "%.2f", shortTerm)) LUFS")
                    }
                    if let truePeak = loudness.snapshot.truePeakDBTP {
                        Text("True Peak: \(String(format: "%.2f", truePeak)) dBTP")
                    }
                    Text("ITU-R BS.1770 · 48-kHz K-Weighting · gated Integrated Loudness")
                        .foregroundStyle(.secondary)
                } else {
                    Text("Professionelle LUFS-/True-Peak-Messung nicht verfügbar.")
                        .foregroundStyle(.secondary)
                }

                Text("Die Messwerte helfen bei der Tonprüfung. Hör das Video zusätzlich kurz auf Verständlichkeit und Störgeräusche ab.")
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

    private var targetSection: some View {
        GroupBox("Ziel") {
            VStack(alignment: .leading, spacing: 6) {
                Label(targetChannelName, systemImage: "person.crop.rectangle")
                    .font(.callout)
                Text("Dein fertiges Video wird auf diesen Kanal hochgeladen.")
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
                if let uploadPreparationStatus {
                    Label(uploadPreparationStatus, systemImage: isPreparingUpload ? "hourglass" : "info.circle")
                        .font(.callout).fixedSize(horizontal: false, vertical: true)
                }
                if session.isPublishing {
                    ProgressView(value: session.publishingProgress)
                    Text(session.publishingProgress >= 1
                         ? "Video übertragen · Vorschaubild und Zusatzdateien abschließen …"
                         : "Video hochladen · \(Int(session.publishingProgress * 100)) %")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Text("Upload-Status")
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
                    title: "Audio",
                    area: .audio
                )
                qualityRow(
                    title: "Untertitel",
                    area: .captions
                )

                Divider()

                if isCheckingQuality || isGeneratingThumbnail {
                    ProgressView("Video und Veröffentlichung werden geprüft …")
                } else if missingAreas.isEmpty && qualityReview.passesReleaseGate {
                    Label("Technisch bereit zum Upload.", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                } else {
                    VStack(alignment: .leading, spacing: 6) {
                        Label(
                            "\(missingAreas.count) Prüfbereiche fehlen",
                            systemImage: "exclamationmark.triangle"
                        )
                        .font(.headline)

                        Text("Die fehlenden technischen Prüfungen werden automatisch ausgeführt. Du brauchst keine Beobachtungsnotizen einzutragen.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                ForEach(qualityReview.blockingFindings) { finding in
                    VStack(alignment: .leading, spacing: 4) {
                        Label(finding.title, systemImage: "exclamationmark.triangle")
                        if let action = finding.recommendedAction { Text(action).font(.caption) }
                    }
                    .foregroundStyle(.red)
                }
                if !missingAreas.isEmpty || !qualityReview.blockingFindings.isEmpty {
                    Button("Automatisch erneut prüfen") {
                        Task {
                            persistedReview = nil
                            if thumbnailURL == nil { await generateThumbnailFromRender() }
                            await checkAudioAutomatically(force: true)
                        }
                    }
                    .disabled(isCheckingQuality || isGeneratingThumbnail || session.isPublishing)
                }

                if currentStage == .review || currentStage == .publishing || currentStage == .published {
                    publishingAuthorizationPanel
                }
                if let error = session.errorMessage {
                    Text(error).font(.caption).foregroundStyle(.red)
                }
            }
            .padding(20)
        }
        .safeAreaInset(edge: .bottom) {
            if currentStage == .packaging || currentStage == .review || currentStage == .publishing {
                Button {
                    Task { await prepareAndConfirmUpload() }
                } label: {
                    Label(session.isPublishing ? "Upload läuft …" :
                          (session.lastPublishingResult?.packagingWarnings?.isEmpty == false
                           ? "Fehlende Extras erneut übertragen" : "Zu YouTube hochladen"),
                          systemImage: "arrow.up.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(isPreparingUpload || session.isPublishing || session.isAuthorizingPublishing || isCheckingQuality || isGeneratingThumbnail || isGeneratingThumbnailChoices)
                .padding(14)
                .background(.regularMaterial)
            }
        }
        .accessibilityLabel("Automatische Uploadprüfung")
        .background(Color.primary.opacity(0.02))
    }

    private func prepareAndConfirmUpload() async {
        guard !isPreparingUpload else { return }
        guard session.activeProject?.id == project.id else {
            session.errorMessage = "Das Projekt wurde gewechselt. Öffne den Upload im gewünschten Projekt erneut."
            return
        }
        isPreparingUpload = true
        defer { isPreparingUpload = false }
        uploadPreparationStatus = "Video und Vorschaubild prüfen …"
        if currentStage == .packaging || currentStage == .review {
            if thumbnailURL == nil { await generateThumbnailFromRender() }
            await checkAudioAutomatically()
            guard missingAreas.isEmpty, qualityReview.passesReleaseGate else {
                session.errorMessage = "Der Upload benötigt noch die oben angezeigten technischen Korrekturen. Untertitel sind optional."
                return
            }
            do {
                let review = qualityReview
                try session.savePublishPreparation(package: draftPackage, qualityReview: review, packagingVariants: packagingVariants)
                if currentStage == .packaging {
                    guard session.advanceActiveProject(to: .review) else { return }
                }
                persistedReview = review
            } catch {
                session.errorMessage = "Upload konnte nicht vorbereitet werden: \(error.localizedDescription)"
                return
            }
        }
        uploadPreparationStatus = "Verbindung zu deinem YouTube-Kanal prüfen …"
        if session.publishingAuthorizedChannelID != project.targetChannelID {
            await session.authorizePublishing()
        }
        guard session.activeProject?.id == project.id,
              session.publishingAuthorizedChannelID == project.targetChannelID else { return }
        uploadPreparationStatus = "Bereit. Bitte Kanal und Sichtbarkeit bestätigen."
        showFinalPublishConfirmation = true
    }

    private func checkAudioAutomatically(force: Bool = false) async {
        guard !isCheckingQuality else { return }
        isCheckingQuality = true
        defer { isCheckingQuality = false }
        do {
            if force || (audioTechnicalAssessment == nil && checkedAudioTechnical == nil) {
                checkedAudioTechnical = try await LocalAudioTechnicalInspector().inspect(url: artifact.fileURL)
            }
            if force || (audioSignalAssessment == nil && checkedAudioSignal == nil) {
                checkedAudioSignal = try await LocalAudioSignalAnalyzer().analyze(url: artifact.fileURL)
            }
            if force || (audioLoudnessAssessment == nil && checkedAudioLoudness == nil) {
                checkedAudioLoudness = try await LocalLoudnessAnalyzer().analyze(url: artifact.fileURL)
            }
        } catch {
            session.errorMessage = "Automatische Tonprüfung fehlgeschlagen: \(error.localizedDescription)"
        }
    }

    private static func suggestedDescription(title: String, transcript: LocalTranscript?) -> String {
        let excerpt = transcript?.text.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return String(excerpt.prefix(1200))
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
                    "Mit deinem Zielkanal verbunden",
                    systemImage: "person.crop.circle.badge.checkmark"
                )
                .font(.caption)

                Text("Ein Klick auf „Zu YouTube hochladen“ bereitet alles vor. Danach bestätigst du Kanal und Sichtbarkeit.")
                    .font(.caption2).foregroundStyle(.secondary)

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
                        Link("Video auf YouTube ansehen", destination: URL(string: "https://www.youtube.com/watch?v=\(result.videoID)")!)
                        Link("In YouTube Studio öffnen", destination: URL(string: "https://studio.youtube.com/video/\(result.videoID)/edit")!)
                        if let warnings = result.packagingWarnings, !warnings.isEmpty {
                            ForEach(warnings, id: \.self) { Text($0).font(.caption).foregroundStyle(.orange) }
                            Button("Video ohne offene Extras abschließen") {
                                session.finishUploadedVideoWithoutExtras()
                            }
                            Text("Das Video bleibt hochgeladen. Nicht übertragene Zusatzdateien werden nicht als erfolgreich markiert.")
                                .font(.caption2).foregroundStyle(.secondary)
                        }
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
            && qualityReview.findings(in: area).allSatisfy { $0.severity != .blocker }
        return HStack(spacing: 10) {
            Image(systemName: covered ? "checkmark.circle.fill" : "circle.dashed")
                .foregroundStyle(covered ? .green : .secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.callout.weight(.semibold))
                Text(covered ? "Geprüft" : "Noch nicht geprüft")
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
