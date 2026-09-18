import Foundation

public enum OpusClipProjectStage: String, Codable, Sendable {
    case pending = "PENDING"
    case queued = "QUEUED"
    case importVideo = "IMPORT"
    case curate = "CURATE"
    case refine = "REFINE"
    case render = "RENDER"
    case upload = "UPLOAD"
    case complete = "COMPLETE"
    case stalled = "STALLED"
}

public struct OpusClipProject: Codable, Sendable, Equatable {
    public let id: String
    public let projectId: String
    public let orgId: String?
    public let sourcePlatform: String?
    public let stage: OpusClipProjectStage?
    public let error: String?

    public init(
        id: String,
        projectId: String,
        orgId: String?,
        sourcePlatform: String?,
        stage: OpusClipProjectStage?,
        error: String?
    ) {
        self.id = id
        self.projectId = projectId
        self.orgId = orgId
        self.sourcePlatform = sourcePlatform
        self.stage = stage
        self.error = error
    }
}

public struct OpusClipExportableClip: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let projectId: String
    public let curationId: String
    public let title: String
    public let text: String
    public let durationMs: Int
    public let uriForPreview: URL?
    public let uriForExport: URL?
    public let timeRanges: [[Int]]
    public let createdAt: Date?

    public init(
        id: String,
        projectId: String,
        curationId: String,
        title: String,
        text: String,
        durationMs: Int,
        uriForPreview: URL?,
        uriForExport: URL?,
        timeRanges: [[Int]],
        createdAt: Date?
    ) {
        self.id = id
        self.projectId = projectId
        self.curationId = curationId
        self.title = title
        self.text = text
        self.durationMs = durationMs
        self.uriForPreview = uriForPreview
        self.uriForExport = uriForExport
        self.timeRanges = timeRanges
        self.createdAt = createdAt
    }
}

public enum OpusClipAPIError: Error, Sendable, Equatable {
    case invalidResponse
    case api(status: Int, message: String)
}

public struct OpusClipAPIClient: Sendable {
    public let apiKey: String
    public let organizationID: String?

    public init(apiKey: String, organizationID: String? = nil) {
        self.apiKey = apiKey
        self.organizationID = organizationID
    }

    public func createProject(
        videoURL: URL,
        title: String,
        sourceLanguage: String?,
        customPrompt: String?,
        session: URLSession = .shared
    ) async throws -> OpusClipProject {
        var body: [String: Any] = [
            "videoUrl": videoURL.absoluteString,
            "uploadedVideoAttr": ["title": title],
            "curationPref": [
                "model": "ClipAnything",
                "clipDurations": [[0, 90]],
                "genre": "Auto",
                "customPrompt": customPrompt ?? ""
            ],
            "renderPref": [
                "layoutAspectRatio": "portrait"
            ]
        ]

        if let sourceLanguage, !sourceLanguage.isEmpty {
            body["importPreference"] = ["sourceLang": sourceLanguage]
        }

        var request = URLRequest(url: URL(string: "https://api.opus.pro/api/clip-projects")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let organizationID, !organizationID.isEmpty {
            request.setValue(organizationID, forHTTPHeaderField: "x-opus-org-id")
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)
        try Self.validate(response: response, data: data)
        return try Self.decoder.decode(OpusClipProject.self, from: data)
    }

    public func exportableClips(
        projectID: String,
        session: URLSession = .shared
    ) async throws -> [OpusClipExportableClip] {
        var components = URLComponents(string: "https://api.opus.pro/api/exportable-clips")!
        components.queryItems = [
            .init(name: "q", value: "findByProjectId"),
            .init(name: "projectId", value: projectID),
            .init(name: "pageNum", value: "1"),
            .init(name: "pageSize", value: "50")
        ]

        var request = URLRequest(url: components.url!)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        if let organizationID, !organizationID.isEmpty {
            request.setValue(organizationID, forHTTPHeaderField: "x-opus-org-id")
        }

        let (data, response) = try await session.data(for: request)
        try Self.validate(response: response, data: data)
        return try Self.decoder.decode([OpusClipExportableClip].self, from: data)
    }

    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    private static func validate(response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else {
            throw OpusClipAPIError.invalidResponse
        }
        guard 200..<300 ~= http.statusCode else {
            let message = String(data: data, encoding: .utf8) ?? "Provider request failed"
            throw OpusClipAPIError.api(status: http.statusCode, message: message)
        }
    }
}
