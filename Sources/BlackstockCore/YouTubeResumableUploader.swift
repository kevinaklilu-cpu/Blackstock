import Foundation

public enum YouTubePrivacyStatus: String, Codable, Sendable {
    case privateVideo = "private"
    case unlisted = "unlisted"
    case publicVideo = "public"
}

public struct YouTubeMetadataLocalization: Codable, Sendable, Equatable {
    public let title: String
    public let description: String

    public init(title: String, description: String) {
        self.title = title
        self.description = description
    }
}

public struct YouTubeUploadMetadata: Codable, Sendable, Equatable {
    public let title: String
    public let description: String
    public let tags: [String]
    public let categoryID: String?
    public let defaultLanguage: String?
    public let defaultAudioLanguage: String?
    public let localizations: [String: YouTubeMetadataLocalization]
    public let privacyStatus: YouTubePrivacyStatus
    public let selfDeclaredMadeForKids: Bool

    public init(
        title: String,
        description: String,
        tags: [String] = [],
        categoryID: String? = nil,
        defaultLanguage: String? = nil,
        defaultAudioLanguage: String? = nil,
        localizations: [String: YouTubeMetadataLocalization] = [:],
        privacyStatus: YouTubePrivacyStatus = .privateVideo,
        selfDeclaredMadeForKids: Bool
    ) {
        self.title = title
        self.description = description
        self.tags = tags
        self.categoryID = categoryID
        self.defaultLanguage = defaultLanguage
        self.defaultAudioLanguage = defaultAudioLanguage
        self.localizations = localizations
        self.privacyStatus = privacyStatus
        self.selfDeclaredMadeForKids = selfDeclaredMadeForKids
    }
}

public enum YouTubeUploadError: Error, Sendable, Equatable {
    case invalidFile
    case invalidResponse
    case missingUploadLocation
    case uploadFailed(Int)
    case missingVideoID
    case journalChannelMismatch
}

public struct YouTubeUploadResult: Codable, Sendable, Equatable {
    public let videoID: String
    public let idempotencyKey: String
    public let reusedCommittedAction: Bool
}

public struct YouTubeResumableUploader: Sendable {
    public let accessToken: String
    public let chunkSize: Int

    public init(accessToken: String, chunkSize: Int = 8 * 1024 * 1024) {
        self.accessToken = accessToken
        self.chunkSize = max(256 * 1024, chunkSize)
    }

    public func upload(
        artifact: RenderArtifact,
        project: BlackstockProject,
        workspaceChannelID: String,
        authorizedUploadChannelID: String,
        metadata: YouTubeUploadMetadata,
        rightsValidated: Bool,
        quotaState: PublicationQuotaState,
        networkAvailable: Bool,
        journal: ExternalActionJournal,
        session: URLSession = .shared,
        now: Date = Date()
    ) async throws -> YouTubeUploadResult {
        try PublicationPreflightContext(
            projectTargetChannelID: project.targetChannelID,
            workspaceChannelID: workspaceChannelID,
            authorizedUploadChannelID: authorizedUploadChannelID,
            renderValidated: artifact.validated,
            rightsValidated: rightsValidated,
            authorizationAvailable: !accessToken.isEmpty,
            quotaState: quotaState,
            networkAvailable: networkAvailable
        ).validate()

        let fileSize = try Self.fileSize(artifact.fileURL)
        guard fileSize > 0 else { throw YouTubeUploadError.invalidFile }

        let idempotencyKey = [
            "youtube-upload",
            project.id.uuidString,
            project.targetChannelID,
            artifact.sha256
        ].joined(separator: ":")

        if let existing = await journal.entry(for: idempotencyKey) {
            guard existing.targetChannelID == project.targetChannelID else {
                throw YouTubeUploadError.journalChannelMismatch
            }
            if existing.state == .remoteCommitted,
               let videoID = existing.remoteResourceID,
               !videoID.isEmpty {
                return .init(
                    videoID: videoID,
                    idempotencyKey: idempotencyKey,
                    reusedCommittedAction: true
                )
            }
        }

        var entry = await journal.entry(for: idempotencyKey) ?? ExternalActionJournalEntry(
            idempotencyKey: idempotencyKey,
            actionType: .youtubeUpload,
            targetChannelID: project.targetChannelID,
            createdAt: now,
            updatedAt: now
        )
        try await journal.upsert(entry)

        let uploadURL: URL
        if let saved = entry.remoteSessionURL {
            uploadURL = saved
            entry.nextByteOffset = try await queryNextOffset(
                uploadURL: saved,
                totalSize: fileSize,
                session: session
            )
            entry.updatedAt = Date()
            try await journal.upsert(entry)
        } else {
            uploadURL = try await createUploadSession(
                fileSize: fileSize,
                mimeType: artifact.mimeType,
                metadata: metadata,
                session: session
            )
            entry.state = .remoteSessionCreated
            entry.remoteSessionURL = uploadURL
            entry.nextByteOffset = 0
            entry.updatedAt = Date()
            try await journal.upsert(entry)
        }

        do {
            let videoID = try await uploadChunks(
                fileURL: artifact.fileURL,
                uploadURL: uploadURL,
                mimeType: artifact.mimeType,
                totalSize: fileSize,
                startingAt: entry.nextByteOffset ?? 0,
                idempotencyKey: idempotencyKey,
                journal: journal,
                session: session
            )

            entry = await journal.entry(for: idempotencyKey) ?? entry
            entry.state = .remoteCommitted
            entry.remoteResourceID = videoID
            entry.nextByteOffset = fileSize
            entry.lastError = nil
            entry.updatedAt = Date()
            try await journal.upsert(entry)

            return .init(
                videoID: videoID,
                idempotencyKey: idempotencyKey,
                reusedCommittedAction: false
            )
        } catch {
            entry = await journal.entry(for: idempotencyKey) ?? entry
            entry.lastError = String(describing: error)
            entry.updatedAt = Date()
            try await journal.upsert(entry)
            throw error
        }
    }

    private func createUploadSession(
        fileSize: Int64,
        mimeType: String,
        metadata: YouTubeUploadMetadata,
        session: URLSession
    ) async throws -> URL {
        var components = URLComponents(
            string: "https://www.googleapis.com/upload/youtube/v3/videos"
        )!
        components.queryItems = [
            .init(name: "uploadType", value: "resumable"),
            .init(
                name: "part",
                value: metadata.localizations.isEmpty
                    ? "snippet,status"
                    : "snippet,status,localizations"
            )
        ]

        var snippet: [String: Any] = [
            "title": metadata.title,
            "description": metadata.description,
            "tags": metadata.tags
        ]
        if let categoryID = metadata.categoryID, !categoryID.isEmpty {
            snippet["categoryId"] = categoryID
        }
        if let defaultLanguage = metadata.defaultLanguage,
           !defaultLanguage.isEmpty {
            snippet["defaultLanguage"] = defaultLanguage
        }
        if let defaultAudioLanguage = metadata.defaultAudioLanguage,
           !defaultAudioLanguage.isEmpty {
            snippet["defaultAudioLanguage"] = defaultAudioLanguage
        }

        var body: [String: Any] = [
            "snippet": snippet,
            "status": [
                "privacyStatus": metadata.privacyStatus.rawValue,
                "selfDeclaredMadeForKids": metadata.selfDeclaredMadeForKids
            ]
        ]
        if !metadata.localizations.isEmpty {
            body["localizations"] = metadata.localizations.mapValues {
                [
                    "title": $0.title,
                    "description": $0.description
                ]
            }
        }

        var request = URLRequest(url: components.url!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json; charset=UTF-8", forHTTPHeaderField: "Content-Type")
        request.setValue(mimeType, forHTTPHeaderField: "X-Upload-Content-Type")
        request.setValue(String(fileSize), forHTTPHeaderField: "X-Upload-Content-Length")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (_, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw YouTubeUploadError.invalidResponse
        }
        guard 200..<300 ~= http.statusCode else {
            throw YouTubeUploadError.uploadFailed(http.statusCode)
        }
        guard let location = http.value(forHTTPHeaderField: "Location"),
              let uploadURL = URL(string: location) else {
            throw YouTubeUploadError.missingUploadLocation
        }
        return uploadURL
    }

    private func queryNextOffset(
        uploadURL: URL,
        totalSize: Int64,
        session: URLSession
    ) async throws -> Int64 {
        let request = Self.resumableStatusRequest(
            uploadURL: uploadURL,
            totalSize: totalSize,
            accessToken: accessToken
        )

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw YouTubeUploadError.invalidResponse
        }

        if http.statusCode == 308 {
            return Self.nextOffset(fromRangeHeader: http.value(forHTTPHeaderField: "Range"))
        }
        if 200..<300 ~= http.statusCode {
            if Self.videoID(from: data) != nil {
                return totalSize
            }
            throw YouTubeUploadError.missingVideoID
        }
        throw YouTubeUploadError.uploadFailed(http.statusCode)
    }

    private func uploadChunks(
        fileURL: URL,
        uploadURL: URL,
        mimeType: String,
        totalSize: Int64,
        startingAt initialOffset: Int64,
        idempotencyKey: String,
        journal: ExternalActionJournal,
        session: URLSession
    ) async throws -> String {
        let handle = try FileHandle(forReadingFrom: fileURL)
        defer { try? handle.close() }

        var offset = initialOffset
        try handle.seek(toOffset: UInt64(offset))

        while offset < totalSize {
            let remaining = totalSize - offset
            let count = Int(min(Int64(chunkSize), remaining))
            guard let data = try handle.read(upToCount: count), !data.isEmpty else {
                throw YouTubeUploadError.invalidFile
            }

            let request = Self.resumableChunkRequest(
                uploadURL: uploadURL,
                mimeType: mimeType,
                totalSize: totalSize,
                offset: offset,
                data: data,
                accessToken: accessToken
            )

            let (responseData, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw YouTubeUploadError.invalidResponse
            }

            if http.statusCode == 308 {
                offset = Self.nextOffset(
                    fromRangeHeader: http.value(forHTTPHeaderField: "Range")
                )
                try handle.seek(toOffset: UInt64(offset))
                if var entry = await journal.entry(for: idempotencyKey) {
                    entry.nextByteOffset = offset
                    entry.updatedAt = Date()
                    try await journal.upsert(entry)
                }
                continue
            }

            guard 200..<300 ~= http.statusCode else {
                throw YouTubeUploadError.uploadFailed(http.statusCode)
            }
            guard let videoID = Self.videoID(from: responseData) else {
                throw YouTubeUploadError.missingVideoID
            }
            return videoID
        }

        throw YouTubeUploadError.missingVideoID
    }

    static func resumableStatusRequest(
        uploadURL: URL,
        totalSize: Int64,
        accessToken: String
    ) -> URLRequest {
        var request = URLRequest(url: uploadURL)
        request.httpMethod = "PUT"
        request.setValue(
            "Bearer \(accessToken)",
            forHTTPHeaderField: "Authorization"
        )
        request.setValue("0", forHTTPHeaderField: "Content-Length")
        request.setValue(
            "bytes */\(totalSize)",
            forHTTPHeaderField: "Content-Range"
        )
        return request
    }

    static func resumableChunkRequest(
        uploadURL: URL,
        mimeType: String,
        totalSize: Int64,
        offset: Int64,
        data: Data,
        accessToken: String
    ) -> URLRequest {
        let end = offset + Int64(data.count) - 1
        var request = URLRequest(url: uploadURL)
        request.httpMethod = "PUT"
        request.setValue(
            "Bearer \(accessToken)",
            forHTTPHeaderField: "Authorization"
        )
        request.setValue(
            mimeType,
            forHTTPHeaderField: "Content-Type"
        )
        request.setValue(
            String(data.count),
            forHTTPHeaderField: "Content-Length"
        )
        request.setValue(
            "bytes \(offset)-\(end)/\(totalSize)",
            forHTTPHeaderField: "Content-Range"
        )
        request.httpBody = data
        return request
    }

    private static func fileSize(_ url: URL) throws -> Int64 {
        let values = try url.resourceValues(forKeys: [.fileSizeKey])
        guard let size = values.fileSize else {
            throw YouTubeUploadError.invalidFile
        }
        return Int64(size)
    }

    static func nextOffset(fromRangeHeader range: String?) -> Int64 {
        guard let range,
              let dash = range.lastIndex(of: "-"),
              let end = Int64(range[range.index(after: dash)...]) else {
            return 0
        }
        return end + 1
    }

    static func videoID(from data: Data) -> String? {
        guard
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let id = object["id"] as? String,
            !id.isEmpty
        else { return nil }
        return id
    }
}
