import Foundation

public enum AnalyticsCSVError: LocalizedError { case empty, missingColumns; public var errorDescription: String? { switch self { case .empty: return "Die CSV-Datei ist leer."; case .missingColumns: return "Blackstock konnte in dieser CSV keine YouTube-Analytics-Spalten erkennen." } } }

public struct AnalyticsCSVParser: Sendable {
    public init() {}
    public func parse(_ text: String) throws -> AnalyticsDataset {
        let lines = text.components(separatedBy: .newlines).filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        guard let first = lines.first else { throw AnalyticsCSVError.empty }
        let delimiter: Character = first.filter { $0 == ";" }.count > first.filter { $0 == "," }.count ? ";" : ","
        let headers = parseLine(first, delimiter: delimiter).map(normalizeHeader)
        func index(_ aliases: [String]) -> Int? { headers.firstIndex { h in aliases.contains(where: { h.contains($0) }) } }
        let titleIndex = index(["video title","video titel","content","video"])
        let viewsIndex = index(["views","aufrufe"])
        let watchIndex = index(["watch time hours","wiedergabezeit stunden","watch time"])
        let impressionsIndex = index(["impressions","impressionen"])
        let ctrIndex = index(["impressions click through rate","klickrate der impressionen","click through rate","ctr"])
        guard viewsIndex != nil || watchIndex != nil || impressionsIndex != nil || ctrIndex != nil else { throw AnalyticsCSVError.missingColumns }
        var rows: [AnalyticsRow] = []
        for (offset, line) in lines.dropFirst().enumerated() {
            let cells = parseLine(line, delimiter: delimiter)
            let title = value(cells, titleIndex) ?? "Zeile \(offset + 1)"
            let views = intValue(value(cells, viewsIndex))
            let watch = doubleValue(value(cells, watchIndex))
            let impressions = intValue(value(cells, impressionsIndex))
            let ctr = percentValue(value(cells, ctrIndex))
            if views != 0 || watch != 0 || impressions != 0 || ctr != nil { rows.append(AnalyticsRow(title: title, views: views, watchTimeHours: watch, impressions: impressions, clickThroughRate: ctr)) }
        }
        return AnalyticsDataset(rows: rows)
    }
    private func normalizeHeader(_ value: String) -> String { value.lowercased().folding(options: [.diacriticInsensitive], locale: .current).replacingOccurrences(of: "_", with: " ").replacingOccurrences(of: "-", with: " ").trimmingCharacters(in: .whitespacesAndNewlines) }
    private func value(_ cells: [String], _ index: Int?) -> String? { guard let index, cells.indices.contains(index) else { return nil }; return cells[index].trimmingCharacters(in: .whitespacesAndNewlines) }
    private func intValue(_ value: String?) -> Int { guard let value else { return 0 }; let clean = value.replacingOccurrences(of: " ", with: "").replacingOccurrences(of: ".", with: "").replacingOccurrences(of: ",", with: ""); return Int(clean.filter { $0.isNumber || $0 == "-" }) ?? 0 }
    private func doubleValue(_ value: String?) -> Double { guard let value else { return 0 }; var clean = value.replacingOccurrences(of: " ", with: ""); if clean.contains(",") && !clean.contains(".") { clean = clean.replacingOccurrences(of: ",", with: ".") } else { clean = clean.replacingOccurrences(of: ",", with: "") }; return Double(clean.filter { $0.isNumber || $0 == "." || $0 == "-" }) ?? 0 }
    private func percentValue(_ value: String?) -> Double? { guard let value, !value.isEmpty else { return nil }; let raw = doubleValue(value); return value.contains("%") || raw > 1 ? raw / 100 : raw }
    private func parseLine(_ line: String, delimiter: Character) -> [String] {
        var result: [String] = [], current = "", quoted = false, iterator = line.makeIterator()
        while let ch = iterator.next() { if ch == "\"" { quoted.toggle() } else if ch == delimiter && !quoted { result.append(current); current = "" } else { current.append(ch) } }
        result.append(current); return result
    }
}
