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
                title: "Videos",
                purpose: "Videos finden und direkt ansehen.",
                nextAction: "Ein Video auswählen.",
                recommendedSurface: .none
            )
        case .research:
            return .init(
                stage: self,
                title: "Recherche",
                purpose: "Video und Thema prüfen.",
                nextAction: "Notizen vervollständigen und fortfahren.",
                recommendedSurface: .overview
            )
        case .analysis:
            return .init(
                stage: self,
                title: "Analyse",
                purpose: "Entscheiden, wie das Video weiterverarbeitet wird.",
                nextAction: "Entscheidung festhalten und fortfahren.",
                recommendedSurface: .overview
            )
        case .production:
            return .init(
                stage: self,
                title: "Produktion",
                purpose: "Video für den Schnitt bereitstellen.",
                nextAction: "Video auswählen und Schnitt starten.",
                recommendedSurface: .studio
            )
        case .preview:
            return .init(
                stage: self,
                title: "Vorschau",
                purpose: "Video kurz prüfen.",
                nextAction: "Video prüfen und weiter zum Schnitt.",
                recommendedSurface: .studio
            )
        case .storyboard:
            return .init(
                stage: self,
                title: "Storyboard",
                purpose: "Aufbau des Videos festlegen.",
                nextAction: "Schnitt starten.",
                recommendedSurface: .studio
            )
        case .editing:
            return .init(
                stage: self,
                title: "Bearbeitung",
                purpose: "Highlights, Schnitt, Untertitel, Format und Ton bearbeiten.",
                nextAction: "Video fertigstellen und Veröffentlichung vorbereiten.",
                recommendedSurface: .studio
            )
        case .packaging:
            return .init(
                stage: self,
                title: "Veröffentlichen",
                purpose: "Titel, Beschreibung, Vorschaubild und Untertitel vorbereiten.",
                nextAction: "Angaben prüfen und Upload vorbereiten.",
                recommendedSurface: .studio
            )
        case .review:
            return .init(
                stage: self,
                title: "Prüfung",
                purpose: "Video und Zielkanal vor dem Upload prüfen.",
                nextAction: "Upload bestätigen.",
                recommendedSurface: .studio
            )
        case .publishing:
            return .init(
                stage: self,
                title: "Veröffentlichung",
                purpose: "Video zu YouTube hochladen.",
                nextAction: "Upload abschließen.",
                recommendedSurface: .studio
            )
        case .published:
            return .init(
                stage: self,
                title: "Analyse",
                purpose: "Leistung des veröffentlichten Videos beobachten.",
                nextAction: "Views, Wiedergabezeit, Zuschauerbindung und Kommentare ansehen.",
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
