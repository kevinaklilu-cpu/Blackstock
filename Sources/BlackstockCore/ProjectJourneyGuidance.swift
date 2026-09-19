import Foundation

public enum ProjectJourneySurface: String, Codable, Sendable, Equatable {
    case studio
    case overview
    case none
}

public struct ProjectJourneyGuidance: Sendable, Equatable {
    public let stage: BlackstockStage
    public let title: String
    public let purpose: String
    public let nextAction: String
    public let recommendedSurface: ProjectJourneySurface

    public init(
        stage: BlackstockStage,
        title: String,
        purpose: String,
        nextAction: String,
        recommendedSurface: ProjectJourneySurface
    ) {
        self.stage = stage
        self.title = title
        self.purpose = purpose
        self.nextAction = nextAction
        self.recommendedSurface = recommendedSurface
    }
}

public extension BlackstockStage {
    var journeyGuidance: ProjectJourneyGuidance {
        switch self {
        case .discovery:
            return .init(
                stage: self,
                title: "Chancen",
                purpose: "Reale Opportunity-Signale und Quellen prüfen.",
                nextAction: "Eine belegte Opportunity für Research auswählen.",
                recommendedSurface: .none
            )
        case .research:
            return .init(
                stage: self,
                title: "Recherche",
                purpose: "Quellen und relevante Provider-Daten nachvollziehbar prüfen.",
                nextAction: "Research-Evidence vervollständigen.",
                recommendedSurface: .none
            )
        case .analysis:
            return .init(
                stage: self,
                title: "Analyse",
                purpose: "Belegte Erkenntnisse in eine Produktionsentscheidung überführen.",
                nextAction: "Produktionsentscheidung auf reale Evidence stützen.",
                recommendedSurface: .none
            )
        case .production:
            return .init(
                stage: self,
                title: "Produktion",
                purpose: "Ein autorisiertes Produktionsmedium mit Rechte-Nachweis vorbereiten.",
                nextAction: "Medium importieren und Rechte bestätigen.",
                recommendedSurface: .studio
            )
        case .preview:
            return .init(
                stage: self,
                title: "Vorschau",
                purpose: "Das echte Produktionsmedium vor strukturellen Edits prüfen.",
                nextAction: "Vorschau prüfen und Storyboard starten.",
                recommendedSurface: .studio
            )
        case .storyboard:
            return .init(
                stage: self,
                title: "Storyboard",
                purpose: "Struktur, Beats und visuelle Richtung vor dem Schnitt festlegen.",
                nextAction: "Storyboard fertigstellen und Bearbeitung starten.",
                recommendedSurface: .studio
            )
        case .editing:
            return .init(
                stage: self,
                title: "Bearbeitung",
                purpose: "Non-destruktive Edits im EditGraph prüfen und rendern.",
                nextAction: "Schnitt finalisieren und Packaging & Review öffnen.",
                recommendedSurface: .studio
            )
        case .packaging:
            return .init(
                stage: self,
                title: "Veröffentlichungspaket",
                purpose: "Metadaten, Thumbnail, Captions und technische QC vorbereiten.",
                nextAction: "Packaging-Evidence vervollständigen und Review speichern.",
                recommendedSurface: .studio
            )
        case .review:
            return .init(
                stage: self,
                title: "Prüfung",
                purpose: "Finales Artefakt, Rechte, Qualität und Zielkanal vor Remote-Aktion prüfen.",
                nextAction: "Publish-Review prüfen und Upload ausdrücklich bestätigen.",
                recommendedSurface: .studio
            )
        case .publishing:
            return .init(
                stage: self,
                title: "Veröffentlichung",
                purpose: "Den bestätigten YouTube-Upload und Resume-Zustand nachvollziehbar ausführen.",
                nextAction: "Upload- und Resume-Status prüfen.",
                recommendedSurface: .studio
            )
        case .published:
            return .init(
                stage: self,
                title: "Veröffentlicht / Lernen",
                purpose: "Reale YouTube-Ergebnisse beobachten und belegte Lernfakten festhalten.",
                nextAction: "Analytics und veröffentlichte Kommentare beobachten.",
                recommendedSurface: .overview
            )
        }
    }

    var canonicalProgressPosition: Int {
        guard let index = Self.allCases.firstIndex(of: self) else {
            return 0
        }
        return index + 1
    }

    static var canonicalProgressCount: Int {
        allCases.count
    }
}
