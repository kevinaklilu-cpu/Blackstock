import Foundation

struct ChannelBaseline: Hashable, Codable {
    var medianViews: Double
    var medianCTR: Double?
    var medianAveragePercentageViewed: Double?
    var medianSubscribersPerThousandViews: Double?
}

struct MarketVideoSignal: Identifiable, Hashable, Codable {
    let id: String
    let title: String
    let channelID: String
    let channelMedianViews: Double
    let currentViews: Double
    let ageHours: Double
    let relevanceToChannel: Double
    let saturation: Double

    var outlierMultiple: Double {
        guard channelMedianViews > 0 else { return 1 }
        return max(0, currentViews / channelMedianViews)
    }
}

struct OpportunityAssessment: Identifiable, Hashable {
    let id: String
    let marketVideoID: String
    let score: Double
    let confidence: Double
    let reasons: [String]
    let recommendation: String
}

struct OpportunityEngine {
    func assess(_ signal: MarketVideoSignal) -> OpportunityAssessment {
        let outlier = min(1, log2(max(1, signal.outlierMultiple)) / 5)
        let velocity = min(1, log10(max(10, signal.currentViews / max(1, signal.ageHours))) / 5)
        let relevance = max(0, min(1, signal.relevanceToChannel))
        let saturationPenalty = max(0, min(1, signal.saturation))
        let raw = outlier * 0.34 + velocity * 0.24 + relevance * 0.34 + (1 - saturationPenalty) * 0.08
        let evidence = [signal.channelMedianViews > 0, signal.currentViews > 0, signal.ageHours > 0].filter { $0 }.count
        let confidence = min(1, Double(evidence) / 3 * (0.55 + relevance * 0.45))
        var reasons: [String] = []
        if signal.outlierMultiple >= 3 { reasons.append(String(format: "%.1f× über Kanalbaseline", signal.outlierMultiple)) }
        if relevance >= 0.7 { reasons.append("hoher Channel-Fit") }
        if velocity >= 0.65 { reasons.append("starke aktuelle Geschwindigkeit") }
        if saturationPenalty <= 0.35 { reasons.append("noch nicht stark gesättigt") }
        let score = max(0, min(100, raw * 100))
        let recommendation: String
        if score >= 78 && confidence >= 0.6 { recommendation = "Jetzt priorisieren" }
        else if score >= 58 { recommendation = "Beobachten oder testen" }
        else { recommendation = "Nicht priorisieren" }
        return .init(id: signal.id, marketVideoID: signal.id, score: score, confidence: confidence, reasons: reasons, recommendation: recommendation)
    }
}

enum PackagingAngle: String, CaseIterable, Codable {
    case curiosity = "Curiosity"
    case outcome = "Outcome"
    case conflict = "Conflict"
    case transformation = "Transformation"
    case surprise = "Surprise"
}

struct PackagingConcept: Identifiable, Hashable, Codable {
    let id: UUID
    var angle: PackagingAngle
    var title: String
    var thumbnailPromise: String
    var viewerPromise: String

    init(id: UUID = UUID(), angle: PackagingAngle, title: String, thumbnailPromise: String, viewerPromise: String) {
        self.id = id
        self.angle = angle
        self.title = title
        self.thumbnailPromise = thumbnailPromise
        self.viewerPromise = viewerPromise
    }
}

struct PackagingQuality: Hashable {
    let score: Double
    let issues: [String]
}

struct PackagingQualityEngine {
    func evaluate(_ concept: PackagingConcept) -> PackagingQuality {
        var score = 100.0
        var issues: [String] = []
        let title = concept.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if title.count < 15 { score -= 18; issues.append("Titel ist zu unspezifisch kurz") }
        if title.count > 70 { score -= 12; issues.append("Titel ist auf mobilen Flächen wahrscheinlich zu lang") }
        if concept.thumbnailPromise.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { score -= 25; issues.append("Thumbnail hat kein klares visuelles Versprechen") }
        if concept.viewerPromise.count < 20 { score -= 20; issues.append("Viewer Promise ist nicht konkret genug") }
        if normalized(title) == normalized(concept.thumbnailPromise) { score -= 12; issues.append("Titel und Thumbnail wiederholen sich statt sich zu ergänzen") }
        return .init(score: max(0, score), issues: issues)
    }

    private func normalized(_ value: String) -> String {
        value.lowercased().filter { $0.isLetter || $0.isNumber }
    }
}

struct RetentionPoint: Hashable, Codable {
    let second: Double
    let relativeRetention: Double
}

struct PublishedPerformance: Identifiable, Hashable, Codable {
    let id: String
    let videoID: String
    let publishedAt: Date
    let views: Int
    let impressions: Int
    let ctr: Double?
    let averagePercentageViewed: Double?
    let subscribersGained: Int?
    let estimatedRevenue: Double?
    let retention: [RetentionPoint]
    let topicKeywords: [String]
    let durationSeconds: Double
}

struct LearningInsight: Identifiable, Hashable {
    let id = UUID()
    let title: String
    let detail: String
    let confidence: Double
    let actionableChange: String
}

struct ChannelLearningEngine {
    func learn(from videos: [PublishedPerformance]) -> [LearningInsight] {
        guard videos.count >= 3 else {
            return [.init(title: "Noch zu wenig Daten", detail: "Blackstock lernt erst nach mehreren veröffentlichten Videos zuverlässig kanalbezogene Muster.", confidence: 0.35, actionableChange: "Weiter messen, noch keine aggressiven Automatikänderungen.")]
        }
        var insights: [LearningInsight] = []
        let withCTR = videos.compactMap { v -> (PublishedPerformance, Double)? in v.ctr.map { (v, $0) } }
        if withCTR.count >= 3 {
            let sorted = withCTR.sorted { $0.1 > $1.1 }
            if let best = sorted.first {
                insights.append(.init(title: "Packaging-Signal", detail: "Dein aktuell stärkster gemessener CTR-Wert liegt bei \(String(format: "%.1f", best.1 * 100)) %.", confidence: min(0.9, Double(withCTR.count) / 10), actionableChange: "Erfolgreiche Packaging-Muster bevorzugen, aber Retention gleichzeitig prüfen."))
            }
        }
        let retention30 = videos.compactMap { video -> Double? in
            video.retention.min(by: { abs($0.second - 30) < abs($1.second - 30) })?.relativeRetention
        }
        if retention30.count >= 3 {
            let avg = retention30.reduce(0, +) / Double(retention30.count)
            if avg < 0.65 {
                insights.append(.init(title: "Frühe Retention", detail: "Die gemessene Retention um Sekunde 30 liegt im Mittel unter 65 %.", confidence: min(0.95, Double(retention30.count) / 8), actionableChange: "Hooks kürzen, Kontext später liefern und den ersten Payoff früher platzieren."))
            }
        }
        return insights
    }
}

struct LaunchReadiness: Hashable {
    enum State: String, Hashable { case ready = "Ready", beta = "Beta", blocked = "Blocked" }
    let state: State
    let score: Double
    let blockers: [String]
}

struct MarketReadinessGate {
    func evaluate(
        crashFreeRate: Double,
        exportSuccessRate: Double,
        taskCompletionRate: Double,
        uploadResumeVerified: Bool,
        captionPassRateAfterAutoFix: Double,
        blindEditPreferenceRate: Double
    ) -> LaunchReadiness {
        var blockers: [String] = []
        if crashFreeRate < 0.995 { blockers.append("Crash-free Rate unter 99,5 %") }
        if exportSuccessRate < 0.985 { blockers.append("Export-Erfolgsrate unter 98,5 %") }
        if taskCompletionRate < 0.90 { blockers.append("Zu viele Nutzer schließen den Kernworkflow nicht ab") }
        if !uploadResumeVerified { blockers.append("Resumable Upload nicht end-to-end verifiziert") }
        if captionPassRateAfterAutoFix < 0.95 { blockers.append("Caption Auto-Fix noch nicht zuverlässig genug") }
        if blindEditPreferenceRate < 0.55 { blockers.append("Blackstock-Schnitte gewinnen Blindtests noch nicht häufig genug") }
        let score = max(0, 100 - Double(blockers.count) * 14)
        let state: LaunchReadiness.State = blockers.isEmpty ? .ready : (blockers.count <= 2 ? .beta : .blocked)
        return .init(state: state, score: score, blockers: blockers)
    }
}
