import Foundation

public enum CaptionTechnicalFormat: String, Sendable, Equatable {
    case webVTT = "WEBVTT"
    case subRip = "SRT"
}

public enum CaptionTechnicalBlocker: String, Sendable, Equatable, CaseIterable {
    case emptyFile
    case unsupportedFormat
    case invalidUTF8
    case missingWebVTTHeader
    case noTimedCues
    case invalidCueTiming
    case emptyCueText
    case nonMonotonicCueOrder
    case overlappingCues
}

public struct CaptionTechnicalSnapshot: Sendable, Equatable {
    public let format: CaptionTechnicalFormat?
    public let fileSizeBytes: Int64
    public let cueCount: Int
    public let firstCueStartSeconds: Double?
    public let lastCueEndSeconds: Double?
    public let inspectedAt: Date

    public init(
        format: CaptionTechnicalFormat?,
        fileSizeBytes: Int64,
        cueCount: Int,
        firstCueStartSeconds: Double?,
        lastCueEndSeconds: Double?,
        inspectedAt: Date
    ) {
        self.format = format
        self.fileSizeBytes = fileSizeBytes
        self.cueCount = cueCount
        self.firstCueStartSeconds = firstCueStartSeconds
        self.lastCueEndSeconds = lastCueEndSeconds
        self.inspectedAt = inspectedAt
    }
}

public struct CaptionTechnicalAssessment: Sendable, Equatable {
    public let snapshot: CaptionTechnicalSnapshot
    public let blockers: [CaptionTechnicalBlocker]

    public init(
        snapshot: CaptionTechnicalSnapshot,
        blockers: [CaptionTechnicalBlocker]
    ) {
        self.snapshot = snapshot
        self.blockers = blockers
    }

    public var uploadCompatible: Bool {
        blockers.isEmpty
    }
}

public enum CaptionTechnicalInspectionError: Error, Sendable, Equatable {
    case fileMissing
    case unreadableFile
}

public struct CaptionTechnicalInspector: Sendable {
    public init() {}

    public func inspect(
        url: URL,
        now: Date = Date()
    ) throws -> CaptionTechnicalAssessment {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw CaptionTechnicalInspectionError.fileMissing
        }

        let values = try url.resourceValues(forKeys: [.fileSizeKey])
        guard let rawFileSize = values.fileSize else {
            throw CaptionTechnicalInspectionError.unreadableFile
        }
        let fileSize = Int64(rawFileSize)
        let format = Self.format(for: url)

        var blockers: [CaptionTechnicalBlocker] = []
        if fileSize <= 0 {
            blockers.append(.emptyFile)
        }
        if format == nil {
            blockers.append(.unsupportedFormat)
        }

        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw CaptionTechnicalInspectionError.unreadableFile
        }

        guard var text = String(data: data, encoding: .utf8) else {
            blockers.append(.invalidUTF8)
            return assessment(
                format: format,
                fileSize: fileSize,
                cues: [],
                blockers: blockers,
                now: now
            )
        }

        if text.hasPrefix("\u{feff}") {
            text.removeFirst()
        }
        text = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")

        let lines = text.components(separatedBy: "\n")
        if format == .webVTT {
            let firstLine = lines.first?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                ?? ""
            if !firstLine.hasPrefix("WEBVTT") {
                blockers.append(.missingWebVTTHeader)
            }
        }

        var cues: [(start: Double, end: Double)] = []
        for (index, line) in lines.enumerated()
        where line.contains("-->") {
            guard let cue = Self.parseCueTiming(line) else {
                blockers.append(.invalidCueTiming)
                continue
            }

            guard cue.start >= 0,
                  cue.end > cue.start else {
                blockers.append(.invalidCueTiming)
                continue
            }

            if !Self.hasCueText(
                after: index,
                lines: lines
            ) {
                blockers.append(.emptyCueText)
                continue
            }

            cues.append(cue)
        }

        if cues.isEmpty {
            blockers.append(.noTimedCues)
        } else {
            for index in cues.indices.dropFirst() {
                let previous = cues[index - 1]
                let current = cues[index]
                if current.start < previous.start {
                    blockers.append(.nonMonotonicCueOrder)
                }
                if current.start < previous.end {
                    blockers.append(.overlappingCues)
                }
            }
        }

        return assessment(
            format: format,
            fileSize: fileSize,
            cues: cues,
            blockers: Self.uniqued(blockers),
            now: now
        )
    }

    public static func format(
        for url: URL
    ) -> CaptionTechnicalFormat? {
        switch url.pathExtension.lowercased() {
        case "vtt":
            return .webVTT
        case "srt":
            return .subRip
        default:
            return nil
        }
    }

    static func parseCueTiming(
        _ line: String
    ) -> (start: Double, end: Double)? {
        let parts = line.components(separatedBy: "-->")
        guard parts.count == 2 else {
            return nil
        }

        let startText = parts[0]
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let endText = parts[1]
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(whereSeparator: { $0.isWhitespace })
            .first
            .map(String.init)
            ?? ""

        guard let start = parseTimestamp(startText),
              let end = parseTimestamp(endText) else {
            return nil
        }
        return (start, end)
    }

    static func parseTimestamp(
        _ value: String
    ) -> Double? {
        let normalized = value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: ".")
        let components = normalized.split(separator: ":")
        guard components.count == 2
                || components.count == 3 else {
            return nil
        }

        let hours: Double
        let minutes: Double
        let seconds: Double

        if components.count == 3 {
            guard let h = Double(components[0]),
                  let m = Double(components[1]),
                  let s = Double(components[2]) else {
                return nil
            }
            hours = h
            minutes = m
            seconds = s
        } else {
            guard let m = Double(components[0]),
                  let s = Double(components[1]) else {
                return nil
            }
            hours = 0
            minutes = m
            seconds = s
        }

        guard hours >= 0,
              minutes >= 0,
              minutes < 60,
              seconds >= 0,
              seconds < 60 else {
            return nil
        }

        return hours * 3_600
            + minutes * 60
            + seconds
    }

    private static func hasCueText(
        after timingIndex: Int,
        lines: [String]
    ) -> Bool {
        guard timingIndex + 1 < lines.count else {
            return false
        }

        let index = timingIndex + 1
        while index < lines.count {
            let value = lines[index]
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if value.isEmpty {
                return false
            }
            if value.contains("-->") {
                return false
            }
            return true
        }
        return false
    }

    private func assessment(
        format: CaptionTechnicalFormat?,
        fileSize: Int64,
        cues: [(start: Double, end: Double)],
        blockers: [CaptionTechnicalBlocker],
        now: Date
    ) -> CaptionTechnicalAssessment {
        CaptionTechnicalAssessment(
            snapshot: CaptionTechnicalSnapshot(
                format: format,
                fileSizeBytes: fileSize,
                cueCount: cues.count,
                firstCueStartSeconds: cues.first?.start,
                lastCueEndSeconds: cues.map(\.end).max(),
                inspectedAt: now
            ),
            blockers: Self.uniqued(blockers)
        )
    }

    private static func uniqued(
        _ blockers: [CaptionTechnicalBlocker]
    ) -> [CaptionTechnicalBlocker] {
        var seen = Set<String>()
        return blockers.filter {
            seen.insert($0.rawValue).inserted
        }
    }
}
