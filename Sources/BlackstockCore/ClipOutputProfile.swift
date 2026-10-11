import Foundation

/// Editing intent controls selection and framing; upload classification follows the rendered file.
public enum ClipOutputProfile: String, Sendable {
    case short, video
    public var minimumDuration: Double { self == .short ? 12 : 30 }
    public var maximumDuration: Double { self == .short ? 90 : 360 }
    public var leadIn: Double { self == .short ? 2 : 10 }
    public var leadOut: Double { self == .short ? 3 : 12 }
    public var fillsPortraitFrame: Bool { self == .short }
    public static func isYouTubeShort(width: Double, height: Double, duration: Double) -> Bool {
        width.isFinite && height.isFinite && duration.isFinite && width > 0 && height >= width && duration > 0 && duration <= 180
    }
}
