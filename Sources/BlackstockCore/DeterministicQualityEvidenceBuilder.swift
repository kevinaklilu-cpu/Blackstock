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
        let renderObservedFact: String
        if renderIsCurrent, let snapshot = artifact.technicalSnapshot {
            let requested = switch artifact.requestedQuality {
            case .upTo1080p?: "bis 1080p"
            case .upTo4K?: "bis 4K"
            case nil: "nicht historisiert"
            }
            let uhdState = snapshot.meetsUHD4KOrGreater
                ? "UHD-4K-Geometrie erreicht"
                : "UHD-4K-Geometrie nicht erreicht"
            renderObservedFact = "Lokaler Render technisch validiert; tatsächliche Ausgabe \(snapshot.width)×\(snapshot.height) px; Dauer \(String(format: "%.2f", snapshot.durationSeconds)) s; angeforderte Qualitätsobergrenze \(requested); \(uhdState)."
        } else if renderIsCurrent {
            renderObservedFact = "Lokaler Render besitzt die aktuelle technische Validierung; für dieses ältere Artefakt ist noch kein persistierter Geometrie-Snapshot vorhanden."
        } else {
            renderObservedFact = "Render-Artefakt besitzt keine aktuelle technische Validierung."
        }

        let renderEvidence = QualityEvidence(
            source: "Blackstock Render Technical Validation",
            observedFact: renderObservedFact,
            reference: artifact.id.uuidString,
            observedAt: artifact.technicalSnapshot?.inspectedAt ?? reviewedAt
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

            let technicalAssessment = try? CaptionTechnicalInspector()
                .inspect(url: captionURL, now: reviewedAt)
            let blockers = technicalAssessment?.blockers ?? [.unsupportedFormat]
            let isTechnicallyValid = technicalAssessment?.uploadCompatible == true
            let blockerText = blockers.map(\.rawValue).joined(separator: ", ")
            let technicalText = isTechnicallyValid
                ? "Caption-Datei technisch valide; Cue-Reihenfolge und Timing ohne technische Blocker."
                : "Caption-Datei technisch nicht valide; Blocker: \(blockerText)."

            let captionEvidence = QualityEvidence(
                source: "Blackstock Caption Technical Validation",
                observedFact: "On-Device-Transkript mit \(transcript.segments.count) Segmenten; mittlere Segment-Confidence \(String(format: "%.2f", averageConfidence)). \(technicalText)",
                reference: captionURL.lastPathComponent,
                observedAt: reviewedAt
            )
            evidence.append(captionEvidence)
            findings.append(
                QualityFinding(
                    area: .captions,
                    severity: isTechnicallyValid
                        ? (averageConfidence < 0.70 ? .warning : .info)
                        : .blocker,
                    title: isTechnicallyValid
                        ? "Captions lokal erzeugt und technisch validiert"
                        : "Caption-Datei technisch blockiert",
                    explanation: captionEvidence.observedFact,
                    recommendedAction: !isTechnicallyValid
                        ? "Caption-Datei neu erzeugen oder Cue-Timing korrigieren."
                        : (averageConfidence < 0.70
                            ? "Caption-Text vor Veröffentlichung manuell gegen das Video prüfen."
                            : "Captions im Review stichprobenartig prüfen."),
                    evidenceIDs: [captionEvidence.id]
                )
            )
        }

        var audioTechnicalEvidence: QualityEvidence?
        if let audioTechnicalAssessment {
            let snapshot = audioTechnicalAssessment.snapshot
            let channels = snapshot.channelCount.map(String.init) ?? "unbekannt"
            let sampleRate = snapshot.sampleRateHz.map {
                String(Int($0.rounded())) + " Hz"
            } ?? "unbekannt"
            let item = QualityEvidence(
                source: "Blackstock Local Audio Technical Inspector",
                observedFact: snapshot.hasAudioTrack
                    ? "Audiospur im aktuellen Render vorhanden; Sample-Rate \(sampleRate); Kanäle \(channels)."
                    : "Im aktuellen Render wurde keine Audiospur erkannt.",
                reference: artifact.id.uuidString,
                observedAt: snapshot.inspectedAt
            )
            evidence.append(item)
            audioTechnicalEvidence = item

            if !snapshot.hasAudioTrack {
                findings.append(
                    QualityFinding(
                        area: .audio,
                        severity: .blocker,
                        title: "Keine Audiospur im Render",
                        explanation: item.observedFact,
                        recommendedAction: "Render und Quellmedium prüfen, bevor veröffentlicht wird.",
                        evidenceIDs: [item.id]
                    )
                )
            }
        }

        var audioSignalEvidence: QualityEvidence?
        if let audioSignalAssessment {
            let snapshot = audioSignalAssessment.snapshot
            let peak = snapshot.peakDBFS.map {
                String(format: "%.2f dBFS", $0)
            } ?? "nicht messbar"
            let rms = snapshot.rmsDBFS.map {
                String(format: "%.2f dBFS", $0)
            } ?? "nicht messbar"
            let item = QualityEvidence(
                source: "Blackstock Local PCM Analyzer",
                observedFact: "Aktueller Render: Peak \(peak); RMS \(rms); analysierte Samples \(snapshot.analyzedSampleCount); Full-Scale-Samples \(snapshot.fullScaleSampleCount).",
                reference: artifact.id.uuidString,
                observedAt: snapshot.inspectedAt
            )
            evidence.append(item)
            audioSignalEvidence = item
        }

        if let technical = audioTechnicalAssessment,
           technical.snapshot.hasAudioTrack,
           let signal = audioSignalAssessment,
           let technicalEvidence = audioTechnicalEvidence,
           let signalEvidence = audioSignalEvidence {
            if signal.snapshot.analyzedSampleCount == 0 {
                findings.append(
                    QualityFinding(
                        area: .audio,
                        severity: .blocker,
                        title: "Audioanalyse ohne Samples",
                        explanation: "Die Audiospur ist vorhanden, aber der lokale PCM-Analyzer konnte keine Samples aus dem aktuellen Render auswerten.",
                        recommendedAction: "Render erneut erzeugen oder das Audioformat prüfen.",
                        evidenceIDs: [technicalEvidence.id, signalEvidence.id]
                    )
                )
            } else {
                findings.append(
                    QualityFinding(
                        area: .audio,
                        severity: .info,
                        title: "Audio des finalen Renders technisch analysiert",
                        explanation: "Audiospur vorhanden und \(signal.snapshot.analyzedSampleCount) PCM-Samples des aktuellen Renders wurden lokal ausgewertet.",
                        recommendedAction: nil,
                        evidenceIDs: [technicalEvidence.id, signalEvidence.id]
                    )
                )

                if technical.findings.contains(.lowSampleRate) {
                    findings.append(
                        QualityFinding(
                            area: .audio,
                            severity: .warning,
                            title: "Niedrige Sample-Rate erkannt",
                            explanation: "Die gemessene Sample-Rate liegt unter 44.100 Hz.",
                            recommendedAction: "Quelle und Export-Einstellungen prüfen, wenn höhere Audioqualität erwartet wird.",
                            evidenceIDs: [technicalEvidence.id]
                        )
                    )
                }

                if signal.findings.contains(.fullScaleSamplesDetected) {
                    findings.append(
                        QualityFinding(
                            area: .audio,
                            severity: .warning,
                            title: "Full-Scale-Samples erkannt",
                            explanation: "Der lokale PCM-Analyzer hat Samples am digitalen Vollpegel erkannt.",
                            recommendedAction: "Im finalen Review gezielt auf hörbares Clipping oder Verzerrungen prüfen.",
                            evidenceIDs: [signalEvidence.id]
                        )
                    )
                }
            }
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
