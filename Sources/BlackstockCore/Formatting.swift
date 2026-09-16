import Foundation
public enum BlackstockFormat {
    public static func compact(_ number: Int) -> String {
        let value = Double(number)
        if value >= 1_000_000 { return String(format: "%.1f Mio.", value / 1_000_000) }
        if value >= 1_000 { return String(format: "%.1f Tsd.", value / 1_000) }
        return String(number)
    }
    public static func duration(_ seconds: Int) -> String {
        let h = seconds / 3600, m = (seconds % 3600) / 60, s = seconds % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }
}
