#if os(macOS)
import Foundation
import AVFoundation
import AVKit
import BlackstockCore

@MainActor
final class StudioState: ObservableObject {
    @Published var asset: ProductionMediaAsset?
    @Published var player = AVPlayer()
    @Published var graph = EditGraph(createdAt: Date())
    @Published var ledger = ActivityLedger()
    @Published var trimStart: Double = 0
    @Published var trimEnd: Double = 0
    @Published var lastUndoneRevisionID: UUID?
    @Published var errorMessage: String?
    @Published var isLoading = false

    private var correlationID = UUID()

    func importMovie(
        url: URL,
        authorization: ProductionMediaAuthorization,
        rightsEvidence: String
    ) async {
        let evidence = rightsEvidence.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !evidence.isEmpty else {
            errorMessage = "Hinterlege einen nachvollziehbaren Rechte- oder Eigentumsnachweis."
            return
        }

        isLoading = true
        defer { isLoading = false }

        do {
            let avAsset = AVURLAsset(url: url)
            let duration = try await avAsset.load(.duration)
            let seconds = max(CMTimeGetSeconds(duration), 0)

            let imported = ProductionMediaAsset(
                displayName: url.lastPathComponent,
                sourceURL: url,
                durationSeconds: seconds,
                authorization: authorization,
                rightsEvidence: [evidence],
                importedAt: Date()
            )
            guard imported.mayEnterProduction else {
                errorMessage = "Dieses Medium ist für die Produktion nicht ausreichend autorisiert."
                return
            }

            asset = imported
            graph = EditGraph(createdAt: Date())
            ledger = ActivityLedger()
            correlationID = UUID()
            trimStart = 0
            trimEnd = seconds
            lastUndoneRevisionID = nil

            ledger.append(.init(
                timestamp: Date(),
                actor: .user,
                stage: .production,
                action: "media-imported",
                summary: "„\(imported.displayName)“ wurde als autorisiertes Produktionsmedium hinzugefügt.",
                relatedSourceIDs: [imported.id.uuidString],
                reversible: false,
                correlationID: correlationID
            ))

            try rebuildPreview()
            errorMessage = nil
        } catch {
            errorMessage = "Video konnte nicht geladen werden: \(error.localizedDescription)"
        }
    }

    func applyTrim() {
        guard let asset else { return }
        let start = min(max(trimStart, 0), asset.durationSeconds)
        let end = min(max(trimEnd, start), asset.durationSeconds)
        guard end - start > 0.05 else {
            errorMessage = "Der gewählte Ausschnitt ist zu kurz."
            return
        }

        let before = graph.headID
        let operation = EditOperation(
            type: .trim,
            timeRange: .init(startSeconds: start, durationSeconds: end - start),
            createdAt: Date()
        )
        let revision = graph.apply(operation, actor: .user)
        lastUndoneRevisionID = nil

        ledger.append(.init(
            timestamp: Date(),
            actor: .user,
            stage: .editing,
            action: "trim-applied",
            summary: "Trim angewendet: \(format(start)) bis \(format(end)).",
            beforeRevisionID: before,
            afterRevisionID: revision.id,
            reversible: true,
            correlationID: correlationID
        ))

        do {
            try rebuildPreview()
            errorMessage = nil
        } catch {
            errorMessage = "Vorschau konnte nicht aktualisiert werden: \(error.localizedDescription)"
        }
    }

    func undo() {
        let undone = graph.headID
        guard let restored = graph.undo() else { return }
        lastUndoneRevisionID = undone

        ledger.append(.init(
            timestamp: Date(),
            actor: .user,
            stage: .editing,
            action: "undo",
            summary: "Letzte Änderung wurde rückgängig gemacht.",
            beforeRevisionID: undone,
            afterRevisionID: restored.id,
            reversible: true,
            correlationID: correlationID
        ))

        refreshPreviewAfterHistoryChange()
    }

    func redo() {
        guard let id = lastUndoneRevisionID,
              let restored = graph.redo(to: id) else { return }
        lastUndoneRevisionID = nil

        ledger.append(.init(
            timestamp: Date(),
            actor: .user,
            stage: .editing,
            action: "redo",
            summary: "Rückgängig gemachte Änderung wurde wiederhergestellt.",
            afterRevisionID: restored.id,
            reversible: true,
            correlationID: correlationID
        ))

        refreshPreviewAfterHistoryChange()
    }

    private func refreshPreviewAfterHistoryChange() {
        do {
            try rebuildPreview()
            errorMessage = nil
        } catch {
            errorMessage = "Vorschau konnte nicht aktualisiert werden: \(error.localizedDescription)"
        }
    }

    private func rebuildPreview() throws {
        guard let asset else {
            player.replaceCurrentItem(with: nil)
            return
        }

        let source = AVURLAsset(url: asset.sourceURL)
        let composition = AVMutableComposition()

        let trim = graph.currentOperations.last(where: { $0.type == .trim })?.timeRange
        let range: CMTimeRange
        if let trim {
            range = CMTimeRange(
                start: CMTime(seconds: trim.startSeconds, preferredTimescale: 600),
                duration: CMTime(seconds: trim.durationSeconds, preferredTimescale: 600)
            )
        } else {
            range = CMTimeRange(
                start: .zero,
                duration: CMTime(seconds: asset.durationSeconds, preferredTimescale: 600)
            )
        }

        try composition.insertTimeRange(range, of: source, at: .zero)
        player.replaceCurrentItem(with: AVPlayerItem(asset: composition))
        player.seek(to: .zero)
    }

    private func format(_ seconds: Double) -> String {
        let total = max(Int(seconds.rounded()), 0)
        return String(format: "%02d:%02d", total / 60, total % 60)
    }
}
#endif
