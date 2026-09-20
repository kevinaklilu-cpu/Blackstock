import Foundation

public struct YouTubeI18nLanguage: Codable, Sendable, Equatable, Identifiable, Hashable {
    public let id: String
    public let code: String
    public let name: String

    public init(code: String, name: String) {
        self.id = code
        self.code = code
        self.name = name
    }
}

public struct YouTubeI18nRegion: Codable, Sendable, Equatable, Identifiable, Hashable {
    public let id: String
    public let code: String
    public let name: String

    public init(code: String, name: String) {
        self.id = code
        self.code = code
        self.name = name
    }
}

public struct YouTubeVideoCategory: Codable, Sendable, Equatable, Identifiable, Hashable {
    public let id: String
    public let title: String
    public let assignable: Bool

    public init(id: String, title: String, assignable: Bool) {
        self.id = id
        self.title = title
        self.assignable = assignable
    }
}

public enum YouTubeChannelAudienceSetting: String, Codable, Sendable, CaseIterable, Hashable {
    case madeForKids
    case notMadeForKids
    case perVideo

    public var selfDeclaredMadeForKids: Bool? {
        switch self {
        case .madeForKids:
            return true
        case .notMadeForKids:
            return false
        case .perVideo:
            return nil
        }
    }

    public var germanTitle: String {
        switch self {
        case .madeForKids:
            return "Ja, der Kanal ist speziell für Kinder"
        case .notMadeForKids:
            return "Nein, der Kanal ist nicht speziell für Kinder"
        case .perVideo:
            return "Für jedes Video einzeln festlegen"
        }
    }

    public var strategyLabel: String {
        switch self {
        case .madeForKids:
            return "Speziell für Kinder"
        case .notMadeForKids:
            return "Nicht speziell für Kinder"
        case .perVideo:
            return "Zielgruppe pro Video"
        }
    }
}

public struct YouTubeChannelSetupApplyResult: Sendable, Equatable {
    public let snapshot: YouTubeChannelSetupSnapshot
    public let audienceAppliedToChannel: Bool?

    public init(
        snapshot: YouTubeChannelSetupSnapshot,
        audienceAppliedToChannel: Bool?
    ) {
        self.snapshot = snapshot
        self.audienceAppliedToChannel = audienceAppliedToChannel
    }
}

public struct YouTubeChannelSetupSnapshot: Codable, Sendable, Equatable {
    public let channelID: String
    public let description: String?
    public let keywords: String?
    public let defaultLanguage: String?
    public let countryCode: String?
    public let trackingAnalyticsAccountID: String?
    public let unsubscribedTrailerVideoID: String?
    public let madeForKids: Bool?
    public let selfDeclaredMadeForKids: Bool?

    public init(
        channelID: String,
        description: String?,
        keywords: String?,
        defaultLanguage: String?,
        countryCode: String?,
        trackingAnalyticsAccountID: String?,
        unsubscribedTrailerVideoID: String?,
        madeForKids: Bool?,
        selfDeclaredMadeForKids: Bool?
    ) {
        self.channelID = channelID
        self.description = description
        self.keywords = keywords
        self.defaultLanguage = defaultLanguage
        self.countryCode = countryCode
        self.trackingAnalyticsAccountID = trackingAnalyticsAccountID
        self.unsubscribedTrailerVideoID = unsubscribedTrailerVideoID
        self.madeForKids = madeForKids
        self.selfDeclaredMadeForKids = selfDeclaredMadeForKids
    }
}

public enum YouTubeChannelSetupError: Error, Sendable, Equatable, LocalizedError {
    case invalidResponse
    case unauthorized
    case api(Int, String?)
    case channelNotFound
    case verificationFailed(String)

    public var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "YouTube hat keine gültige Antwort geliefert."
        case .unauthorized:
            return "Die YouTube-Autorisierung reicht für diese Kanaleinstellung nicht aus."
        case .api(let status, let message):
            if let message, !message.isEmpty {
                return "YouTube-Kanaleinstellung fehlgeschlagen (HTTP \(status)): \(message)"
            }
            return "YouTube-Kanaleinstellung fehlgeschlagen (HTTP \(status))."
        case .channelNotFound:
            return "Der ausgewählte YouTube-Kanal wurde nicht gefunden."
        case .verificationFailed(let field):
            return "YouTube hat die Kanaleinstellung „\(field)“ nicht bestätigt."
        }
    }
}

public struct YouTubeChannelSetupClient: Sendable {
    public let accessToken: String

    public init(accessToken: String) {
        self.accessToken = accessToken
    }

    public func supportedLanguages(
        displayLanguage: String = "de",
        session: URLSession = .shared
    ) async throws -> [YouTubeI18nLanguage] {
        var components = URLComponents(
            string: "https://www.googleapis.com/youtube/v3/i18nLanguages"
        )!
        components.queryItems = [
            .init(name: "part", value: "snippet"),
            .init(name: "hl", value: displayLanguage)
        ]

        let data = try await perform(
            request: URLRequest(url: components.url!),
            session: session
        )
        let response = try JSONDecoder().decode(
            I18nLanguageListResponse.self,
            from: data
        )
        return response.items
            .map {
                YouTubeI18nLanguage(
                    code: $0.snippet.hl,
                    name: $0.snippet.name
                )
            }
            .sorted {
                $0.name.localizedCaseInsensitiveCompare($1.name)
                    == .orderedAscending
            }
    }

    public func supportedRegions(
        displayLanguage: String = "de",
        session: URLSession = .shared
    ) async throws -> [YouTubeI18nRegion] {
        var components = URLComponents(
            string: "https://www.googleapis.com/youtube/v3/i18nRegions"
        )!
        components.queryItems = [
            .init(name: "part", value: "snippet"),
            .init(name: "hl", value: displayLanguage)
        ]

        let data = try await perform(
            request: URLRequest(url: components.url!),
            session: session
        )
        let response = try JSONDecoder().decode(
            I18nRegionListResponse.self,
            from: data
        )
        return response.items
            .map {
                YouTubeI18nRegion(
                    code: $0.snippet.gl,
                    name: $0.snippet.name
                )
            }
            .sorted {
                $0.name.localizedCaseInsensitiveCompare($1.name)
                    == .orderedAscending
            }
    }

    public func videoCategories(
        regionCode: String,
        languageCode: String,
        session: URLSession = .shared
    ) async throws -> [YouTubeVideoCategory] {
        var components = URLComponents(
            string: "https://www.googleapis.com/youtube/v3/videoCategories"
        )!
        components.queryItems = [
            .init(name: "part", value: "snippet"),
            .init(name: "regionCode", value: regionCode),
            .init(name: "hl", value: languageCode)
        ]

        let data = try await perform(
            request: URLRequest(url: components.url!),
            session: session
        )
        let response = try JSONDecoder().decode(
            VideoCategoryListResponse.self,
            from: data
        )
        return response.items
            .map {
                YouTubeVideoCategory(
                    id: $0.id,
                    title: $0.snippet.title,
                    assignable: $0.snippet.assignable
                )
            }
            .filter(\.assignable)
            .sorted {
                $0.title.localizedCaseInsensitiveCompare($1.title)
                    == .orderedAscending
            }
    }

    public func currentChannelSetup(
        channelID: String,
        session: URLSession = .shared
    ) async throws -> YouTubeChannelSetupSnapshot {
        var components = URLComponents(
            string: "https://www.googleapis.com/youtube/v3/channels"
        )!
        components.queryItems = [
            .init(name: "part", value: "brandingSettings,status"),
            .init(name: "id", value: channelID)
        ]

        let data = try await perform(
            request: URLRequest(url: components.url!),
            session: session
        )
        let response = try JSONDecoder().decode(
            ChannelSetupListResponse.self,
            from: data
        )
        guard let item = response.items.first(where: { $0.id == channelID }) else {
            throw YouTubeChannelSetupError.channelNotFound
        }
        let branding = item.brandingSettings?.channel
        return YouTubeChannelSetupSnapshot(
            channelID: item.id,
            description: branding?.description,
            keywords: branding?.keywords,
            defaultLanguage: branding?.defaultLanguage,
            countryCode: branding?.country,
            trackingAnalyticsAccountID:
                branding?.trackingAnalyticsAccountId,
            unsubscribedTrailerVideoID:
                branding?.unsubscribedTrailer,
            madeForKids: item.status?.madeForKids,
            selfDeclaredMadeForKids:
                item.status?.selfDeclaredMadeForKids
        )
    }

    public func updateBranding(
        snapshot: YouTubeChannelSetupSnapshot,
        countryCode: String,
        defaultLanguage: String,
        session: URLSession = .shared
    ) async throws {
        var channel: [String: Any] = [
            "country": countryCode,
            "defaultLanguage": defaultLanguage
        ]

        if let description = snapshot.description {
            channel["description"] = description
        }
        if let keywords = snapshot.keywords {
            channel["keywords"] = keywords
        }
        if let tracking = snapshot.trackingAnalyticsAccountID {
            channel["trackingAnalyticsAccountId"] = tracking
        }
        if let trailer = snapshot.unsubscribedTrailerVideoID {
            channel["unsubscribedTrailer"] = trailer
        }

        let body: [String: Any] = [
            "id": snapshot.channelID,
            "brandingSettings": [
                "channel": channel
            ]
        ]
        try await updateChannel(
            part: "brandingSettings",
            body: body,
            session: session
        )
    }

    public func updateAudience(
        channelID: String,
        selfDeclaredMadeForKids: Bool,
        session: URLSession = .shared
    ) async throws {
        let body: [String: Any] = [
            "id": channelID,
            "status": [
                "selfDeclaredMadeForKids": selfDeclaredMadeForKids
            ]
        ]
        try await updateChannel(
            part: "status",
            body: body,
            session: session
        )
    }

    public func applyAndVerify(
        channelID: String,
        countryCode: String,
        defaultLanguage: String,
        audience: YouTubeChannelAudienceSetting,
        session: URLSession = .shared
    ) async throws -> YouTubeChannelSetupApplyResult {
        let before = try await currentChannelSetup(
            channelID: channelID,
            session: session
        )
        try await updateBranding(
            snapshot: before,
            countryCode: countryCode,
            defaultLanguage: defaultLanguage,
            session: session
        )

        var audienceUpdateAttempted = false
        if let declared = audience.selfDeclaredMadeForKids {
            audienceUpdateAttempted = true
            do {
                try await updateAudience(
                    channelID: channelID,
                    selfDeclaredMadeForKids: declared,
                    session: session
                )
            } catch {
                // The public channel resource documents
                // selfDeclaredMadeForKids, while channels.update
                // has provider/account-specific behavior for the status
                // part. Do not block onboarding on this optional write.
            }
        }

        let after = try await currentChannelSetup(
            channelID: channelID,
            session: session
        )
        guard after.countryCode == countryCode else {
            throw YouTubeChannelSetupError
                .verificationFailed("Land/Region")
        }
        guard after.defaultLanguage == defaultLanguage else {
            throw YouTubeChannelSetupError
                .verificationFailed("Standardsprache")
        }

        let audienceAppliedToChannel: Bool?
        if let declared = audience.selfDeclaredMadeForKids {
            let confirmed =
                after.selfDeclaredMadeForKids == declared
                || after.madeForKids == declared
            audienceAppliedToChannel =
                audienceUpdateAttempted ? confirmed : false
        } else {
            audienceAppliedToChannel = nil
        }

        return YouTubeChannelSetupApplyResult(
            snapshot: after,
            audienceAppliedToChannel: audienceAppliedToChannel
        )
    }

    private func updateChannel(
        part: String,
        body: [String: Any],
        session: URLSession
    ) async throws {
        var components = URLComponents(
            string: "https://www.googleapis.com/youtube/v3/channels"
        )!
        components.queryItems = [
            .init(name: "part", value: part)
        ]
        var request = URLRequest(url: components.url!)
        request.httpMethod = "PUT"
        request.setValue(
            "Bearer \(accessToken)",
            forHTTPHeaderField: "Authorization"
        )
        request.setValue(
            "application/json; charset=UTF-8",
            forHTTPHeaderField: "Content-Type"
        )
        request.httpBody = try JSONSerialization.data(
            withJSONObject: body
        )
        _ = try await perform(
            request: request,
            session: session
        )
    }

    private func perform(
        request: URLRequest,
        session: URLSession
    ) async throws -> Data {
        var authorized = request
        if authorized.value(
            forHTTPHeaderField: "Authorization"
        ) == nil {
            authorized.setValue(
                "Bearer \(accessToken)",
                forHTTPHeaderField: "Authorization"
            )
        }

        let (data, response) = try await session.data(
            for: authorized
        )
        guard let http = response as? HTTPURLResponse else {
            throw YouTubeChannelSetupError.invalidResponse
        }
        if http.statusCode == 401 {
            throw YouTubeChannelSetupError.unauthorized
        }
        guard 200..<300 ~= http.statusCode else {
            let provider = try? JSONDecoder().decode(
                YouTubeProviderErrorEnvelope.self,
                from: data
            )
            throw YouTubeChannelSetupError.api(
                http.statusCode,
                provider?.error.message
            )
        }
        return data
    }
}

private struct I18nLanguageListResponse: Decodable {
    let items: [I18nLanguageItem]
}

private struct I18nLanguageItem: Decodable {
    let snippet: I18nLanguageSnippet
}

private struct I18nLanguageSnippet: Decodable {
    let hl: String
    let name: String
}

private struct I18nRegionListResponse: Decodable {
    let items: [I18nRegionItem]
}

private struct I18nRegionItem: Decodable {
    let snippet: I18nRegionSnippet
}

private struct I18nRegionSnippet: Decodable {
    let gl: String
    let name: String
}

private struct VideoCategoryListResponse: Decodable {
    let items: [VideoCategoryItem]
}

private struct VideoCategoryItem: Decodable {
    let id: String
    let snippet: VideoCategorySnippet
}

private struct VideoCategorySnippet: Decodable {
    let title: String
    let assignable: Bool
}

private struct ChannelSetupListResponse: Decodable {
    let items: [ChannelSetupItem]
}

private struct ChannelSetupItem: Decodable {
    let id: String
    let brandingSettings: ChannelSetupBrandingSettings?
    let status: ChannelSetupStatus?
}

private struct ChannelSetupBrandingSettings: Decodable {
    let channel: ChannelSetupBrandingChannel?
}

private struct ChannelSetupBrandingChannel: Decodable {
    let description: String?
    let keywords: String?
    let defaultLanguage: String?
    let country: String?
    let trackingAnalyticsAccountId: String?
    let unsubscribedTrailer: String?
}

private struct ChannelSetupStatus: Decodable {
    let madeForKids: Bool?
    let selfDeclaredMadeForKids: Bool?
}

private struct YouTubeProviderErrorEnvelope: Decodable {
    let error: YouTubeProviderError
}

private struct YouTubeProviderError: Decodable {
    let message: String?
}
