import Foundation

public enum CaptionFontWeight:
    String,
    Codable,
    Sendable,
    Equatable,
    Hashable {
    case semibold
    case bold
    case heavy
}

public enum CaptionVisualStyle:
    String,
    Codable,
    Sendable,
    CaseIterable,
    Equatable,
    Hashable {
    case clear = "CLEAR"
    case strong = "STRONG"
    case minimal = "MINIMAL"

    public var germanTitle: String {
        switch self {
        case .clear:
            return "Klar"
        case .strong:
            return "Kräftig"
        case .minimal:
            return "Minimal"
        }
    }

    public var germanExplanation: String {
        switch self {
        case .clear:
            return "Gut lesbarer Standard mit ruhigem Hintergrund."
        case .strong:
            return "Größere, kräftigere Schrift für kurze Hochkant-Clips."
        case .minimal:
            return "Zurückhaltende Darstellung mit kleinerer Schrift und leichterem Hintergrund."
        }
    }

    public var fontWeight: CaptionFontWeight {
        switch self {
        case .clear:
            return .bold
        case .strong:
            return .heavy
        case .minimal:
            return .semibold
        }
    }

    public var fontSizeFactor: Double {
        switch self {
        case .clear:
            return 0.037
        case .strong:
            return 0.048
        case .minimal:
            return 0.031
        }
    }

    public var minimumRenderedFontSize: Double {
        switch self {
        case .clear:
            return 34
        case .strong:
            return 42
        case .minimal:
            return 30
        }
    }

    public var widthFactor: Double {
        switch self {
        case .clear:
            return 0.84
        case .strong:
            return 0.90
        case .minimal:
            return 0.78
        }
    }

    public var heightFactor: Double {
        switch self {
        case .clear:
            return 0.12
        case .strong:
            return 0.15
        case .minimal:
            return 0.10
        }
    }

    public var minimumRenderedHeight: Double {
        switch self {
        case .clear:
            return 110
        case .strong:
            return 136
        case .minimal:
            return 92
        }
    }

    public var bottomOffsetFactor: Double {
        switch self {
        case .clear:
            return 0.075
        case .strong:
            return 0.095
        case .minimal:
            return 0.065
        }
    }

    public var backgroundOpacity: Double {
        switch self {
        case .clear:
            return 0.72
        case .strong:
            return 0.84
        case .minimal:
            return 0.46
        }
    }

    public var cornerRadiusFactor: Double {
        switch self {
        case .clear:
            return 0.012
        case .strong:
            return 0.016
        case .minimal:
            return 0.008
        }
    }

    public var shadowOpacity: Float {
        switch self {
        case .clear:
            return 0.35
        case .strong:
            return 0.48
        case .minimal:
            return 0.20
        }
    }
}
