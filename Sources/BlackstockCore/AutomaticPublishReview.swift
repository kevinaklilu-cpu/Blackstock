import Foundation

/// Upload readiness is a technical contract. Editorial opinions are not
/// mandatory attestations, and this builder never claims to have watched a film.
public struct AutomaticPublishReview: Sendable {
    public static let requiredAreas: Set<CreatorQualityArea> = [
        .packaging, .audio, .captions, .rightsAndPolicy, .renderIntegrity
    ]

    public init() {}

    public func build(base: CreatorQualityReview, package: PublishPackage,
                      now: Date = Date()) -> CreatorQualityReview {
        var evidence = base.evidence
        var findings = base.findings.filter { $0.area != .packaging && $0.area != .captions }
        func append(_ area: CreatorQualityArea, _ message: String, blocked: Bool, action: String? = nil) {
            let item = QualityEvidence(source: "Blackstock Automatic Upload Validation",
                observedFact: message, reference: package.renderArtifactID.uuidString, observedAt: now)
            evidence.append(item)
            findings.append(QualityFinding(area: area, severity: blocked ? .blocker : .info,
                title: message, explanation: message, recommendedAction: action, evidenceIDs: [item.id]))
        }
        do {
            try YouTubeMetadataValidator().validate(package.metadata)
            append(.packaging, "Titel und Beschreibung erfüllen die technischen Upload-Vorgaben.", blocked: false)
        } catch {
            append(.packaging, "Titel oder Beschreibung sind für YouTube ungültig.", blocked: true,
                action: "Titel mit 1–100 Zeichen und Beschreibung mit höchstens 5.000 UTF-8-Bytes verwenden.")
        }
        if let thumbnail = package.thumbnail {
            let valid = (try? ThumbnailTechnicalInspector().inspect(url: thumbnail.fileURL).uploadCompatible) == true
            append(.packaging, valid ? "Vorschaubild technisch geprüft." : "Vorschaubild ist nicht hochladbar.",
                blocked: !valid, action: valid ? nil : "Vorschaubild erneut aus dem Video erzeugen oder ersetzen.")
        }
        if package.captions.isEmpty {
            append(.captions, "Keine zusätzliche Untertiteldatei ausgewählt; kein Untertitel-Upload erforderlich.", blocked: false)
        } else {
            for caption in package.captions {
                let valid = !caption.language.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    && (try? CaptionTechnicalInspector().inspect(url: caption.fileURL).uploadCompatible) == true
                append(.captions, valid ? "Untertiteldatei technisch geprüft: \(caption.name)" : "Untertiteldatei ist nicht hochladbar: \(caption.name)",
                    blocked: !valid, action: valid ? nil : "Untertitel neu erzeugen, ersetzen oder aus dem Upload entfernen.")
            }
        }
        return CreatorQualityReview(projectID: base.projectID, stage: base.stage,
            evidence: evidence, findings: findings, reviewedAt: now)
    }
}
