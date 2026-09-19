import Foundation

#if canImport(FoundationModels)
import FoundationModels
#endif

public enum LocalRetentionAdvisorAvailability: String, Codable, Sendable {
    case available = "AVAILABLE"
    case unsupportedOS = "UNSUPPORTED_OS"
    case frameworkUnavailable = "FRAMEWORK_UNAVAILABLE"
    case modelUnavailable = "MODEL_UNAVAILABLE"
    case unsupportedLanguage = "UNSUPPORTED_LANGUAGE"
}

public struct RetentionAnalysisInput: Codable, Sendable, Equatable {
    public let localeIdentifier: String
    public let transcriptExcerpt: String
    public let segmentIDs: [UUID]
    public let structureFacts: [String]

    public init(
        localeIdentifier: String,
        transcriptExcerpt: String,
        segmentIDs: [UUID],
        structureFacts: [String]
    ) {
        self.localeIdentifier = localeIdentifier
        self.transcriptExcerpt = transcriptExcerpt
        self.segmentIDs = segmentIDs
        self.structureFacts = structureFacts
    }

    public static func make(
        transcript: LocalTranscript,
        structure: TranscriptStructureSnapshot,
        maxSeconds: Double = 90
    ) -> RetentionAnalysisInput {
        let segments = transcript.segments
            .filter { $0.startSeconds < maxSeconds }
            .sorted { $0.startSeconds < $1.startSeconds }

        let excerpt = segments.map { segment in
            let timestamp = String(format: "%.1f", segment.startSeconds)
            return "[\(timestamp)s] \(segment.text)"
        }
        .joined(separator: "\n")

        return .init(
            localeIdentifier: transcript.localeIdentifier,
            transcriptExcerpt: excerpt,
            segmentIDs: segments.map(\.id),
            structureFacts: structure.factualSummary
        )
    }
}

public struct LocalRetentionAdvisory: Codable, Sendable, Equatable, Identifiable {
    public let id: UUID
    public let text: String
    public let source: String
    public let segmentIDs: [UUID]
    public let createdAt: Date
    public let isReleaseEvidence: Bool

    public init(
        id: UUID = UUID(),
        text: String,
        source: String,
        segmentIDs: [UUID],
        createdAt: Date,
        isReleaseEvidence: Bool = false
    ) {
        self.id = id
        self.text = text
        self.source = source
        self.segmentIDs = segmentIDs
        self.createdAt = createdAt
        self.isReleaseEvidence = isReleaseEvidence
    }
}

public enum LocalRetentionAdvisorError: Error, Sendable, Equatable {
    case unavailable(LocalRetentionAdvisorAvailability)
    case emptyTranscript
    case generationFailed(String)
}

public struct LocalRetentionAdvisor: Sendable {
    public init() {}

    public func availability(
        localeIdentifier: String
    ) -> LocalRetentionAdvisorAvailability {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            let model = SystemLanguageModel.default
            guard model.isAvailable else {
                return .modelUnavailable
            }
            guard model.supportsLocale(
                Locale(identifier: localeIdentifier)
            ) else {
                return .unsupportedLanguage
            }
            return .available
        }
        return .unsupportedOS
        #else
        return .frameworkUnavailable
        #endif
    }

    public func analyze(
        transcript: LocalTranscript,
        structure: TranscriptStructureSnapshot,
        now: Date = Date()
    ) async throws -> LocalRetentionAdvisory {
        let input = RetentionAnalysisInput.make(
            transcript: transcript,
            structure: structure
        )
        guard !input.transcriptExcerpt
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .isEmpty else {
            throw LocalRetentionAdvisorError.emptyTranscript
        }

        let state = availability(
            localeIdentifier: input.localeIdentifier
        )
        guard state == .available else {
            throw LocalRetentionAdvisorError.unavailable(state)
        }

        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            do {
                let session = LanguageModelSession(
                    instructions: """
                    Du unterstützt die Video-Review in Blackstock.
                    Analysiere ausschließlich den bereitgestellten Transkript-Ausschnitt und die gemessenen Struktur-Fakten.
                    Formuliere höchstens fünf kurze, konkrete Hinweise zu Verständlichkeit, Einstieg, Wiederholungen oder strukturellen Leerlauf-Risiken.
                    Behaupte keine Views, Retention-Prozentwerte, Viralität oder Zuschauerreaktionen.
                    Erfinde keine visuellen oder akustischen Beobachtungen.
                    Wenn die Daten eine Aussage nicht tragen, sage das ausdrücklich.
                    """
                )

                let facts = input.structureFacts
                    .map { "- \($0)" }
                    .joined(separator: "\n")
                let prompt = """
                Content-Sprache: \(input.localeIdentifier)

                Gemessene Struktur-Fakten:
                \(facts)

                Transkript-Ausschnitt:
                \(input.transcriptExcerpt)
                """

                let response = try await session.respond(to: prompt)
                let text = response.content
                    .trimmingCharacters(in: .whitespacesAndNewlines)

                guard !text.isEmpty else {
                    throw LocalRetentionAdvisorError.generationFailed(
                        "Das lokale Modell lieferte keine Hinweise."
                    )
                }

                return .init(
                    text: text,
                    source: "Apple Foundation Models · On-Device",
                    segmentIDs: input.segmentIDs,
                    createdAt: now,
                    isReleaseEvidence: false
                )
            } catch let error as LocalRetentionAdvisorError {
                throw error
            } catch {
                throw LocalRetentionAdvisorError.generationFailed(
                    error.localizedDescription
                )
            }
        }
        #endif

        throw LocalRetentionAdvisorError.unavailable(.frameworkUnavailable)
    }
}
