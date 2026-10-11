import Foundation
import CryptoKit

public struct YouTubePublishingResult: Codable, Sendable, Equatable {
    public let videoID: String
    public let publishedRecord: PublishedVideoRecord
    public let uploadReused: Bool
    public let packagingWarnings: [String]?

    public init(
        videoID: String,
        publishedRecord: PublishedVideoRecord,
        uploadReused: Bool,
        packagingWarnings: [String]? = nil
    ) {
        self.videoID = videoID
        self.publishedRecord = publishedRecord
        self.uploadReused = uploadReused
        self.packagingWarnings = packagingWarnings
    }
}

public enum YouTubePublishingCoordinatorError: Error, Sendable, Equatable {
    case journalChannelMismatch
    case missingArtifactFile
}

public struct YouTubePublishingCoordinator: Sendable {
    public let uploadClient: YouTubeResumableUploader
    public let packagingClient: YouTubePackagingClient

    public init(
        uploadClient: YouTubeResumableUploader,
        packagingClient: YouTubePackagingClient
    ) {
        self.uploadClient = uploadClient
        self.packagingClient = packagingClient
    }

    public func publish(
        review: PublishReviewContext,
        workspaceChannelID: String,
        authorizedUploadChannelID: String,
        quotaState: PublicationQuotaState,
        networkAvailable: Bool,
        experimentID: UUID?,
        journal: ExternalActionJournal,
        session: URLSession = .shared,
        now: Date = Date()
    ) async throws -> YouTubePublishingResult {
        try review.validate()

        let upload = try await uploadClient.upload(
            artifact: review.artifact,
            project: review.project,
            workspaceChannelID: workspaceChannelID,
            authorizedUploadChannelID: authorizedUploadChannelID,
            metadata: review.package.metadata,
            rightsValidated: review.rightsValidated,
            quotaState: quotaState,
            networkAvailable: networkAvailable,
            journal: journal,
            session: session,
            now: now
        )

        var packagingWarnings: [String] = []
        if let thumbnail = review.package.thumbnail {
            do {
            try await performJournaledPackagingAction(
                actionType: .youtubeThumbnailSet,
                targetChannelID: review.project.targetChannelID,
                videoID: upload.videoID,
                payloadHash: try fileHash(thumbnail.fileURL),
                journal: journal,
                now: now
            ) {
                try await packagingClient.setThumbnail(
                    videoID: upload.videoID,
                    imageURL: thumbnail.fileURL,
                    mimeType: thumbnail.mimeType,
                    session: session
                )
            }
            } catch let error as YouTubePackagingError {
                packagingWarnings.append("Video hochgeladen; Vorschaubild noch offen: " + error.localizedDescription)
            }
        }

        for caption in review.package.captions {
            do {
            try await performJournaledPackagingAction(
                actionType: .youtubeCaptionUpload,
                targetChannelID: review.project.targetChannelID,
                videoID: upload.videoID,
                payloadHash: try fileHash(caption.fileURL),
                journal: journal,
                now: now
            ) {
                try await packagingClient.uploadCaption(
                    videoID: upload.videoID,
                    language: caption.language,
                    name: caption.name,
                    captionURL: caption.fileURL,
                    mimeType: caption.mimeType,
                    isDraft: caption.isDraft,
                    session: session
                )
            }
            } catch let error as YouTubePackagingError {
                packagingWarnings.append("Video hochgeladen; Untertitel noch offen: " + error.localizedDescription)
            }
        }

        let record = PublishedVideoRecord(
            projectID: review.project.id,
            experimentID: experimentID,
            targetChannelID: review.project.targetChannelID,
            youtubeVideoID: upload.videoID,
            publishedAt: now
        )

        return YouTubePublishingResult(
            videoID: upload.videoID,
            publishedRecord: record,
            uploadReused: upload.reusedCommittedAction,
            packagingWarnings: packagingWarnings.isEmpty ? nil : packagingWarnings
        )
    }

    private func performJournaledPackagingAction(
        actionType: ExternalActionType,
        targetChannelID: String,
        videoID: String,
        payloadHash: String,
        journal: ExternalActionJournal,
        now: Date,
        action: @escaping @Sendable () async throws -> Void
    ) async throws {
        let idempotencyKey = [
            actionType.rawValue,
            targetChannelID,
            videoID,
            payloadHash
        ].joined(separator: ":")

        if let existing = await journal.entry(for: idempotencyKey) {
            guard existing.targetChannelID == targetChannelID else {
                throw YouTubePublishingCoordinatorError.journalChannelMismatch
            }
            if existing.state == .remoteCommitted {
                return
            }
        }

        var entry = await journal.entry(for: idempotencyKey)
            ?? ExternalActionJournalEntry(
                idempotencyKey: idempotencyKey,
                actionType: actionType,
                targetChannelID: targetChannelID,
                createdAt: now,
                updatedAt: now
            )
        try await journal.upsert(entry)

        do {
            try await action()
            entry.state = .remoteCommitted
            entry.remoteResourceID = videoID
            entry.lastError = nil
            entry.updatedAt = Date()
            try await journal.upsert(entry)
        } catch {
            entry.state = .failed
            entry.lastError = String(describing: error)
            entry.updatedAt = Date()
            try await journal.upsert(entry)
            throw error
        }
    }

    private func fileHash(_ url: URL) throws -> String {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw YouTubePublishingCoordinatorError.missingArtifactFile
        }
        let data = try Data(contentsOf: url)
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
