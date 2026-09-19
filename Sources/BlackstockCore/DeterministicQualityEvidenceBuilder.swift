import Foundation

public struct DeterministicQualityEvidenceBuilder: Sendable {
    public init() {}

    public func build(
        projectID: UUID,
        asset: ProductionMediaAsset,
        artifact: RenderArtifact,
        transcript: LocalTranscript? = nil,
        captionURL: URL? = nil,
        audioTechnicalAssessment: AudioTechnicalAssessment? = nil,
        audioSignalAssessment: AudioSignalAssessment? = nil,
        thumbnailAssessment: ThumbnailTechnicalAssessment? = nil,
        reviewedAt: Date = Date()
    ) -> CreatorQualityReview {
        var evidence: [QualityEvidence] = []
        var findings: [QualityFinding] = []

        let rightsEvidence = QualityEvidence(
            source: "Rights Ledger",
            observedFact: asset.mayEnterProduction
                ? "Produktionsmedium besitzt Rechtebestätigung und Nachweis."
                : "Produktionsmedium besitzt keine ausreichende Rechtefreigabe.",
            reference: asset.id.uuidString,
            observedAt: reviewedAt
        )
        evidence.append(rightsEvidence)
        findings.append(
            QualityFinding(
                area: .rightsAndPolicy,
                severity: asset.mayEnterProduction ? .info : .blocker,
                title: asset.mayEnterProduction
                    ? "Rechte-Nachweis vorhanden"
                    : "Rechte-Nachweis unvollständig",
                explanation: rightsEvidence.observedFact,
                recommendedAction: asset.mayEnterProduction
                    ? nil
                    : "Rechte bestätigen oder Medium ersetzen.",
                evidenceIDs: [rightsEvidence.id]
            )
        )

        let renderIsCurrent = artifact.hasCurrentTechnicalValidation
        let renderEvidence = QualityEvidence(
            source: "Blackstock Render Technical Validation",
            observedFact: renderIsCurrent
                ? "Lokaler Render besitzt die aktuelle technische Validierung für Datei, Dauer, Videotrack und erwartete Ausgabegeometrie."
                : "Render-Artefakt besitzt keine aktuelle technische Validierung.",
            reference: artifact.id.uuidString,
            observedAt: reviewedAt
        )
        evidence.append(renderEvidence)
        findings.append(
            QualityFinding(
                area: .renderIntegrity,
                severity: renderIsCurrent ? .info : .blocker,
                title: renderIsCurrent
                    ? "Render technisch validiert"
                    : "Render technisch nicht validiert",
                explanation: renderEvidence.observedFact,
                recommendedAction: renderIsCurrent
                    ? nil
                    : "Video mit der aktuellen Blackstock-Version erneut rendern.",
                evidenceIDs: [renderEvidence.id]
            )
        )

        if let transcript,
           transcript.onDevice,
           !transcript.segments.isEmpty,
           let captionURL,
           FileManager.default.fileExists(atPath: captionURL.path) {
            let averageConfidence = transcript.segments
                .map { Double($0.confidence) }
                .reduce(0, +) / Double(transcript.segments.count)
            let captionEvidence = QualityEvidence(
                source: "Blackstock Local Speech",
                observedFact: "On-Device-Transkript mit \(transcript.segments.count) Segmenten und WebVTT-Datei vorhanden; mittlere Segment-Confidence \(String(format: "%.2f", averageConfidence)).",
                reference: captionURL.lastPathComponent,
                observedAt: reviewedAt
            )
            evidence.append(captionEvidence)
            findings.append(
                QualityFinding(
                    area: .captions,
                    severity: averageConfidence < 0.70 ? .warning : .info,
                    title: "Captions lokal erzeugt",
                    explanation: captionEvidence.observedFact,
                    recommendedAction: averageConfidence < 0.70
                        ? "Caption-Text vor Veröffentlichung manuell gegen das Video prüfen."
                        : "Captions im Review stichprobenartig prüfen.",
                    evidenceIDs: [captionEvidence.id]
                )
            )
        }

        if let audioTechnicalAssessment {
            let snapshot = audioTechnicalAssessment.snapshot
            let channels = snapshot.channelCount.map(String.init) ?? "unbekannt"
            let sampleRate = snapshot.sampleRateHz.map {
                String(Int($0.rounded())) + " Hz"
            } ?? "unbekannt"
            evidence.append(
                QualityEvidence(
                    source: "Blackstock Local Audio Technical Inspector",
                    observedFact: snapshot.hasAudioTrack
                        ? "Audiospur vorhanden; Sample-Rate \(sampleRate); Kanäle \(channels)."
                        : "Keine Audiospur erkannt.",
                    reference: asset.id.uuidString,
                    observedAt: snapshot.inspectedAt
                )
            )
        }

        if let audioSignalAssessment {
            let snapshot = audioSignalAssessment.snapshot
            let peak = snapshot.peakDBFS.map {
                String(format: "%.2f dBFS", $0)
            } ?? "nicht messbar"
            let rms = snapshot.rmsDBFS.map {
                String(format: "%.2f dBFS", $0)
            } ?? "nicht messbar"
            evidence.append(
                QualityEvidence(
                    source: "Blackstock Local PCM Analyzer",
                    observedFact: "Peak \(peak); RMS \(rms); analysierte Samples \(snapshot.analyzedSampleCount); Full-Scale-Samples \(snapshot.fullScaleSampleCount).",
                    reference: asset.id.uuidString,
                    observedAt: snapshot.inspectedAt
                )
            )
        }

        if let thumbnailAssessment {
            let snapshot = thumbnailAssessment.snapshot
            let ratio = snapshot.aspectRatio.map {
                String(format: "%.3f", $0)
            } ?? "unbekannt"
            let blockerText = thumbnailAssessment.uploadBlockers
                .map(\.rawValue)
                .joined(separator: ", ")
            let hintText = thumbnailAssessment.bestPracticeFindings
                .map(\.rawValue)
                .joined(separator: ", ")
            let statement = [
                "Thumbnail \(snapshot.width)×\(snapshot.height)",
                "MIME \(snapshot.mimeType)",
                "Dateigröße \(snapshot.fileSizeBytes) Byte",
                "Seitenverhältnis \(ratio)",
                blockerText.isEmpty ? "keine Upload-Blocker" : "Upload-Blocker: \(blockerText)",
                hintText.isEmpty ? "keine Format-Hinweise" : "Hinweise: \(hintText)"
            ]
            .joined(separator: "; ")

            evidence.append(
                QualityEvidence(
                    source: "Blackstock Thumbnail Technical Inspector",
                    observedFact: statement,
                    reference: nil,
                    observedAt: snapshot.inspectedAt
                )
            )
        }

        return CreatorQualityReview(
            projectID: projectID,
            stage: .review,
            evidence: evidence,
            findings: findings,
            reviewedAt: reviewedAt
        )
    }
}
