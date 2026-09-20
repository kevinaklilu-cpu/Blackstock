import Foundation

public enum CreatorOutputPreset:
    String,
    Codable,
    Sendable,
    CaseIterable,
    Equatable,
    Hashable {
    case youtubeLandscape = "YOUTUBE_LANDSCAPE"
    case shortVertical = "SHORT_VERTICAL"
    case squareSocial = "SQUARE_SOCIAL"

    public var germanTitle: String {
        switch self {
        case .youtubeLandscape:
            return "YouTube 16:9"
        case .shortVertical:
            return "Shorts/Reels 9:16"
        case .squareSocial:
            return "Social 1:1"
        }
    }

    public var germanExplanation: String {
        switch self {
        case .youtubeLandscape:
            return "Querformat für klassische YouTube-Videos mit ruhigem Untertitelstil."
        case .shortVertical:
            return "Hochformat für kurze vertikale Clips mit kräftigerem Untertitelstil."
        case .squareSocial:
            return "Quadratisches Format mit klarer, kompakter Untertiteldarstellung."
        }
    }

    public var aspectRatio: ReframeAspectRatio {
        switch self {
        case .youtubeLandscape:
            return .landscape16x9
        case .shortVertical:
            return .portrait9x16
        case .squareSocial:
            return .square1x1
        }
    }

    public var captionStyle: CaptionVisualStyle {
        switch self {
        case .youtubeLandscape:
            return .clear
        case .shortVertical:
            return .strong
        case .squareSocial:
            return .clear
        }
    }

    public var prefersVisibleCaptions: Bool {
        switch self {
        case .youtubeLandscape:
            return false
        case .shortVertical, .squareSocial:
            return true
        }
    }
}
