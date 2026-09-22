#if os(macOS)
import AppKit
import Foundation
import SwiftUI
import BlackstockCore

private enum PublishingSessionError: Error, LocalizedError {
    case missingScopes
    case missingToken
    case browserOpenFailed
    case providerRejected(String)
    case oauthClientChanged

    var errorDescription: String? {
        switch self {
        case .missingScopes:
            return "Die benötigten Google-Berechtigungen fehlen."
        case .missingToken:
            return "Kein gültiges Google-Zugriffstoken ist gespeichert."
        case .browserOpenFailed:
            return "Der Systembrowser konnte nicht geöffnet werden."
        case .providerRejected(let message):
            return "Google hat die Autorisierung abgelehnt: \(message)"
        case .oauthClientChanged:
            return "Die aktive Google-OAuth-Konfiguration hat sich seit der Kanal-Autorisierung geändert. Autorisiere den Kanal erneut."
        }
    }
}

struct LocalPrivacyDeletionSummary {
    let keychainEntriesRemoved: Int
    let userDefaultsKeysRemoved: Int
    let localFilesRemoved: Int
    let localDirectoriesRemoved: Int
    let failures: [String]

    var isComplete: Bool {
        failures.isEmpty
    }
}

@MainActor
final class BlackstockSession: ObservableObject {
    enum FirstRunStep: Int, CaseIterable {
        case welcome
        case channel
        case topic
        case language
        case preparing
        case opportunities
    }

    @Published var step: FirstRunStep = .welcome
    @Published var channels: [YouTubeChannelIdentity] = []
    @Published var selectedChannelID: String?
    @Published var primaryTopic = ""
    @Published var strategyContentPromise = ""
    @Published var strategyAudienceHypothesis = ""
    @Published var strategyPillarsText = ""
    @Published var strategyAdjacentTopicsText = ""
    @Published var strategyExcludedTopicsText = ""
    @Published var strategyObjective: StrategicObjective = .balanced
    @Published var contentLanguage = "de"
    @Published var youtubeLanguages: [YouTubeI18nLanguage] = []
    @Published var youtubeRegions: [YouTubeI18nRegion] = []
    @Published var youtubeVideoCategories: [YouTubeVideoCategory] = []
    @Published var channelRegionCode = ""
    @Published var channelCategoryID = ""
    @Published var opportunityTimeWindow:
        OpportunityTimeWindow = .allTime
    @Published var opportunityContentFilter: OpportunityContentFilter = .all
    @Published var channelAudienceSetting:
        YouTubeChannelAudienceSetting = .perVideo
    @Published var isLoadingYouTubeSetupOptions = false
    @Published private(set) var officialChannelSettingsVerified = false
    @Published private(set) var channelAudienceAppliedToYouTube: Bool?
    @Published var opportunities: [YouTubeOpportunityCandidate] = []
    @Published var isWorking = false
    @Published var errorMessage: String?
    @Published private(set) var onboardingComplete: Bool
    @Published private(set) var activeProject: BlackstockProject?
    @Published private(set) var activeOpportunitySource: MediaSourceReference?
    @Published private(set) var publishingAuthorizedChannelID: String?
    @Published var isAuthorizingPublishing = false
    @Published var isPublishing = false
    @Published private(set) var lastPublishingResult: YouTubePublishingResult?
    @Published private(set) var analyticsAuthorizedChannelID: String?
    @Published var isAuthorizingAnalytics = false
    @Published var isCollectingAnalytics = false
    @Published private(set) var latestGrowthLearning: GrowthLearningRecord?
    @Published private(set) var latestChannelAnalytics:
        YouTubeAnalyticsSnapshot?
    @Published var isLoadingComments = false
    @Published private(set) var latestCommentPage: YouTubeCommentThreadPage?
    @Published private(set) var latestCommentsVideoID: String?
    @Published private(set) var importedOAuthClientID: String
    @Published private(set) var workspaceRightsResponsibilityAccepted: Bool
    @Published private(set) var originalMediaLibraryPath: String

    private var tokenSet: GoogleOAuthTokenSet?
    private var tokenExpiresAt: Date?
    private var cachedPublishingJournal: ExternalActionJournal?

    private var connectedOAuthScopes: Set<GoogleOAuthScope> {
        [
            .youtubeReadOnly,
            .youtubeUpload,
            .youtubeForceSSL,
            .analyticsReadOnly
        ]
    }

    private var connectedOAuthScopeString: String {
        connectedOAuthScopes
            .map(\.rawValue)
            .sorted()
            .joined(separator: " ")
    }

    private func cacheRuntimeToken(
        _ tokens: GoogleOAuthTokenSet,
        fallbackScopeString: String? = nil,
        now: Date = Date()
    ) {
        let returnedScope = tokens.scope?
            .trimmingCharacters(
                in: .whitespacesAndNewlines
            ) ?? ""
        let fallbackScope = fallbackScopeString?
            .trimmingCharacters(
                in: .whitespacesAndNewlines
            ) ?? ""
        let effectiveScope =
            returnedScope.isEmpty
            ? fallbackScope
            : returnedScope

        tokenSet = GoogleOAuthTokenSet(
            accessToken: tokens.accessToken,
            refreshToken: tokens.refreshToken,
            expiresIn: tokens.expiresIn,
            tokenType: tokens.tokenType,
            scope: effectiveScope.isEmpty
                ? nil
                : effectiveScope
        )
        tokenExpiresAt = now.addingTimeInterval(
            TimeInterval(
                max(tokens.expiresIn - 120, 60)
            )
        )
    }

    private func validRuntimeAccessToken(
        requiredScopes: Set<GoogleOAuthScope>,
        now: Date = Date()
    ) -> String? {
        guard let tokenSet,
              !tokenSet.accessToken.isEmpty,
              let tokenExpiresAt,
              tokenExpiresAt > now.addingTimeInterval(30) else {
            return nil
        }

        let granted =
            GoogleOAuthScopePlanner.parseGrantedScopes(
                tokenSet.scope
            )
        guard requiredScopes.isSubset(of: granted) else {
            return nil
        }
        return tokenSet.accessToken
    }

    init() {
        BlackstockUpdateAudit.reconcilePostUpdateLaunch()
        BlackstockCaptureHardwareAudit.reconcilePostRestart()
        _ = try? PrivacyRetentionEnforcer().purgeExpiredUpdatePackages(
            in: FileManager.default.temporaryDirectory
        )
        importedOAuthClientID = BlackstockKeychain.read("google.oauth.importedClientID")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        originalMediaLibraryPath = UserDefaults.standard.string(
            forKey: "blackstock.originalMediaLibraryPath"
        ) ?? ""
        onboardingComplete = UserDefaults.standard.bool(forKey: "blackstock.firstRun.complete")
        workspaceRightsResponsibilityAccepted = false
        activeProject = Self.loadStoredProject()
        activeOpportunitySource = Self.loadStoredSource()
        if let activeProject {
            try? Self.upsertStoredProject(activeProject)
            if let activeOpportunitySource {
                try? Self.store(
                    source: activeOpportunitySource,
                    projectID: activeProject.id
                )
            }
        }
        primaryTopic = UserDefaults.standard.string(
            forKey: "blackstock.workspace.primaryTopic"
        ) ?? ""
        contentLanguage = UserDefaults.standard.string(
            forKey: "blackstock.workspace.contentLanguage"
        ) ?? "de"
        channelRegionCode = UserDefaults.standard.string(
            forKey: "blackstock.workspace.regionCode"
        ) ?? ""
        channelCategoryID =
            UserDefaults.standard.string(
                forKey: "blackstock.workspace.channelCategoryID"
            )
            ?? UserDefaults.standard.string(
                forKey: "blackstock.workspace.videoCategoryID"
            )
            ?? ""
        if let rawTimeWindow =
            UserDefaults.standard.string(
                forKey: "blackstock.workspace.opportunityTimeWindow"
            ),
           let savedTimeWindow = OpportunityTimeWindow(
                rawValue: rawTimeWindow
           ) {
            opportunityTimeWindow = savedTimeWindow
        }
        if let rawContentFilter =
            UserDefaults.standard.string(
                forKey: "blackstock.workspace.opportunityContentFilter"
            ),
           let savedContentFilter = OpportunityContentFilter(
                rawValue: rawContentFilter
           ) {
            opportunityContentFilter = savedContentFilter
        }
        if let rawAudience = UserDefaults.standard.string(
            forKey: "blackstock.workspace.channelAudience"
        ),
           let audience = YouTubeChannelAudienceSetting(
                rawValue: rawAudience
           ) {
            channelAudienceSetting = audience
        }
        let storedRightsChannelID =
            activeProject?.targetChannelID
            ?? UserDefaults.standard.string(
                forKey: "blackstock.workspace.channelID"
            )
        workspaceRightsResponsibilityAccepted =
            storedRightsChannelID.flatMap {
                Self.loadStoredWorkspaceRightsAttestation(
                    channelID: $0
                )
            }?.permitsUserDirectedProduction == true
    }

    var selectedChannel: YouTubeChannelIdentity? {
        guard let selectedChannelID else { return nil }
        return channels.first { $0.id == selectedChannelID }
    }

    var oauthConfigurationSource: String {
        if !importedClientID.isEmpty { return "Eigene OAuth-JSON" }
        if !bundledClientID.isEmpty { return "Blackstock-Konfiguration" }
        return "Nicht konfiguriert"
    }

    var hasImportedOAuthConfiguration: Bool {
        !importedClientID.isEmpty
    }

    var originalMediaLibraryURL: URL? {
        let value = originalMediaLibraryPath.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard !value.isEmpty else { return nil }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(
            atPath: value,
            isDirectory: &isDirectory
        ),
        isDirectory.boolValue else {
            return nil
        }
        return URL(fileURLWithPath: value, isDirectory: true)
    }

    var approvedSourceProviderAuthorization:
        RemoteIngestProviderAuthorization? {
        guard let providerID =
                Bundle.main.object(
                    forInfoDictionaryKey:
                        "BlackstockApprovedSourceProviderID"
                ) as? String,
              !providerID.trimmingCharacters(
                    in: .whitespacesAndNewlines
              ).isEmpty,
              let approvalReference =
                Bundle.main.object(
                    forInfoDictionaryKey:
                        "BlackstockApprovedSourceProviderYouTubeApprovalReference"
                ) as? String,
              !approvalReference.trimmingCharacters(
                    in: .whitespacesAndNewlines
              ).isEmpty,
              let verifiedAtRaw =
                Bundle.main.object(
                    forInfoDictionaryKey:
                        "BlackstockApprovedSourceProviderVerifiedAt"
                ) as? String,
              let verifiedAt =
                ISO8601DateFormatter().date(
                    from: verifiedAtRaw
                ) else {
            return nil
        }

        return RemoteIngestProviderAuthorization(
            providerID: providerID,
            supportsYouTubeLinks: true,
            youtubeWrittenApprovalReference:
                approvalReference,
            verifiedAt: verifiedAt
        )
    }

    var approvedSourceProviderEndpointURL: URL? {
        guard let raw =
                Bundle.main.object(
                    forInfoDictionaryKey:
                        "BlackstockApprovedSourceProviderEndpoint"
                ) as? String,
              let url = URL(string: raw),
              url.scheme?.lowercased() == "https" else {
            return nil
        }
        return url
    }

    var canAutomaticallyAcquireYouTubeSource: Bool {
        approvedSourceProviderAuthorization?
            .mayIngestYouTubeLinks == true
        && approvedSourceProviderEndpointURL != nil
    }

    func resolveApprovedSourceMediaURL(
        for source: MediaSourceReference
    ) async throws -> URL? {
        guard source.provider == .youtube,
              let authorization =
                approvedSourceProviderAuthorization,
              authorization.mayIngestYouTubeLinks,
              let endpoint =
                approvedSourceProviderEndpointURL else {
            return nil
        }

        let token = BlackstockKeychain.read(
            "sourceProvider."
            + authorization.providerID
            + ".bearerToken"
        )

        return try await ApprovedSourceProviderClient()
            .resolve(
                source: source,
                endpointURL: endpoint,
                bearerToken:
                    token.isEmpty ? nil : token
            )
            .mediaURL
    }

    var automaticIngestDirectoryURL: URL? {
        guard let downloads = FileManager.default.urls(
            for: .downloadsDirectory,
            in: .userDomainMask
        ).first else {
            return nil
        }

        let directory = downloads.appendingPathComponent(
            "Blackstock Ingest",
            isDirectory: true
        )
        do {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
            return directory
        } catch {
            return nil
        }
    }

    @discardableResult
    func setOriginalMediaLibrary(
        _ url: URL?
    ) -> Bool {
        guard let url else {
            originalMediaLibraryPath = ""
            UserDefaults.standard.removeObject(
                forKey: "blackstock.originalMediaLibraryPath"
            )
            return true
        }

        let resolved = url
            .resolvingSymlinksInPath()
            .standardizedFileURL
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(
            atPath: resolved.path,
            isDirectory: &isDirectory
        ),
        isDirectory.boolValue else {
            errorMessage =
                "Der ausgewählte Originalvideo-Ordner ist nicht verfügbar."
            return false
        }

        originalMediaLibraryPath = resolved.path
        UserDefaults.standard.set(
            resolved.path,
            forKey: "blackstock.originalMediaLibraryPath"
        )
        errorMessage = nil
        return true
    }

    func resolveOriginalMedia(
        for project: BlackstockProject,
        source: MediaSourceReference?
    ) async -> URL? {
        var roots: [URL] = []
        if let automaticIngestDirectoryURL {
            roots.append(automaticIngestDirectoryURL)
        }
        if let originalMediaLibraryURL,
           !roots.contains(originalMediaLibraryURL) {
            roots.append(originalMediaLibraryURL)
        }
        guard !roots.isEmpty else {
            return nil
        }

        let title = project.title
        let videoID = source?.externalID

        return await Task.detached(priority: .utility) {
            let fileManager = FileManager.default
            let keys: [URLResourceKey] = [
                .isRegularFileKey,
                .fileSizeKey,
                .contentModificationDateKey
            ]

            var candidates: [URL] = []
            for root in roots {
                guard let enumerator = fileManager.enumerator(
                    at: root,
                    includingPropertiesForKeys: keys,
                    options: [
                        .skipsHiddenFiles,
                        .skipsPackageDescendants
                    ]
                ) else {
                    continue
                }

                while let candidate =
                        enumerator.nextObject() as? URL {
                    if candidates.count >= 5_000 {
                        break
                    }
                    guard LocalOriginalMediaMatcher
                        .supportedExtensions
                        .contains(
                            candidate
                                .pathExtension
                                .lowercased()
                        ) else {
                        continue
                    }
                    guard let values =
                            try? candidate.resourceValues(
                                forKeys: Set(keys)
                            ),
                          values.isRegularFile == true,
                          (values.fileSize ?? 0) > 0 else {
                        continue
                    }
                    candidates.append(candidate)
                }

                if candidates.count >= 5_000 {
                    break
                }
            }

            return LocalOriginalMediaMatcher().bestMatch(
                videoID: videoID,
                title: title,
                fileURLs: candidates
            )
        }.value
    }


    var projects: [BlackstockProject] {
        Self.loadStoredProjects()
            .sorted { lhs, rhs in
                if lhs.updatedAt == rhs.updatedAt {
                    return lhs.createdAt > rhs.createdAt
                }
                return lhs.updatedAt > rhs.updatedAt
            }
    }

    @discardableResult
    func importOAuthJSON(from url: URL) -> Bool {
        let hasSecurityScopedAccess = url.startAccessingSecurityScopedResource()
        defer {
            if hasSecurityScopedAccess {
                url.stopAccessingSecurityScopedResource()
            }
        }

        do {
            let data = try Data(contentsOf: url, options: .mappedIfSafe)
            let config = try OAuthClientConfiguration
                .parseGoogleDesktopJSON(data)
            let previousClientID = effectiveClientID
            let nextClientID =
                OAuthClientConfiguration.preferredClientID(
                    bundled: bundledClientID,
                    imported: config.clientID
                )
            let clientChanged = OAuthClientBindingPolicy()
                .requiresCredentialInvalidation(
                    previousClientID: previousClientID,
                    nextClientID: nextClientID
                )

            if clientChanged {
                _ = try BlackstockKeychain.deleteAccounts(
                    withPrefix: "youtube."
                )
            }

            try BlackstockKeychain.write(
                config.clientID,
                account: "google.oauth.importedClientID"
            )
            if let clientSecret = config.clientSecret,
               !clientSecret.isEmpty {
                try BlackstockKeychain.write(
                    clientSecret,
                    account: "google.oauth.importedClientSecret"
                )
            } else {
                try? BlackstockKeychain.delete(
                    "google.oauth.importedClientSecret"
                )
            }
            importedOAuthClientID = config.clientID
            clearOAuthRuntimeAuthorizationState(
                clearChannelSelection: clientChanged
            )
            errorMessage = nil
            return true
        } catch {
            errorMessage = "OAuth-JSON konnte nicht übernommen werden: \(describe(error))"
            return false
        }
    }

    @discardableResult
    func removeLocalGoogleCredentials() throws -> Int {
        let removed = try BlackstockKeychain.deleteAccounts(
            withPrefix: "youtube."
        )
        tokenSet = nil
        tokenExpiresAt = nil
        publishingAuthorizedChannelID = nil
        analyticsAuthorizedChannelID = nil
        lastPublishingResult = nil
        latestCommentPage = nil
        latestCommentsVideoID = nil
        channels = []
        selectedChannelID = nil
        return removed
    }

    @discardableResult
    func revokeGoogleAuthorization() async throws -> Int {
        let channelID = workspaceChannelID ?? selectedChannelID
        if let channelID {
            let refreshToken = BlackstockKeychain.read(
                "youtube.\(channelID).refreshToken"
            )
            let accessToken = BlackstockKeychain.read(
                "youtube.\(channelID).accessToken"
            )
            let token = refreshToken.isEmpty ? accessToken : refreshToken
            if !token.isEmpty {
                try await GoogleOAuthRevoker().revoke(token: token)
            }
        }
        return try removeLocalGoogleCredentials()
    }

    func exportLocalPrivacyData(
        to destinationDirectory: URL
    ) throws -> PrivacyDataExportReport {
        let base = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let root = base.appendingPathComponent(
            "Blackstock",
            isDirectory: true
        )
        let defaults = UserDefaults.standard.dictionaryRepresentation()
            .filter { $0.key.hasPrefix("blackstock.") }
        let plist = try PropertyListSerialization.data(
            fromPropertyList: defaults,
            format: .xml,
            options: 0
        )
        return try PrivacyDataExporter().export(
            applicationSupportRoot: root,
            userDefaultsPlist: plist,
            destinationDirectory: destinationDirectory
        )
    }

    @discardableResult
    func removeAllLocalBlackstockData() -> LocalPrivacyDeletionSummary {
        var keychainEntriesRemoved = 0
        var userDefaultsKeysRemoved = 0
        var localFilesRemoved = 0
        var localDirectoriesRemoved = 0
        var failures: [String] = []

        do {
            keychainEntriesRemoved = try BlackstockKeychain
                .deleteAccounts(withPrefix: "")
        } catch {
            failures.append(
                "Keychain-Daten konnten nicht vollständig entfernt werden: \(describe(error))"
            )
        }

        let defaults = UserDefaults.standard
        let blackstockKeys = defaults.dictionaryRepresentation().keys
            .filter { $0.hasPrefix("blackstock.") }
        for key in blackstockKeys {
            defaults.removeObject(forKey: key)
            userDefaultsKeysRemoved += 1
        }

        do {
            let base = try FileManager.default.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            let root = base.appendingPathComponent(
                "Blackstock",
                isDirectory: true
            )
            let report = try LocalDataCleaner()
                .deleteDirectoryIfPresent(root)
            localFilesRemoved = report.fileCount
            localDirectoriesRemoved = report.directoryCount
        } catch {
            failures.append(
                "Lokale Projekt-/Wachstumsdaten konnten nicht vollständig entfernt werden: \(describe(error))"
            )
        }

        tokenSet = nil
        cachedPublishingJournal = nil
        importedOAuthClientID = ""
        originalMediaLibraryPath = ""
        onboardingComplete = !failures.isEmpty
        activeProject = nil
        activeOpportunitySource = nil
        publishingAuthorizedChannelID = nil
        analyticsAuthorizedChannelID = nil
        lastPublishingResult = nil
        latestGrowthLearning = nil
        latestChannelAnalytics = nil
        latestCommentPage = nil
        latestCommentsVideoID = nil
        isLoadingComments = false
        step = .welcome
        channels = []
        selectedChannelID = nil
        primaryTopic = ""
        strategyContentPromise = ""
        strategyAudienceHypothesis = ""
        strategyPillarsText = ""
        strategyAdjacentTopicsText = ""
        strategyExcludedTopicsText = ""
        strategyObjective = .balanced
        contentLanguage = "de"
        opportunities = []
        isWorking = false
        isAuthorizingPublishing = false
        isPublishing = false
        isAuthorizingAnalytics = false
        isCollectingAnalytics = false
        errorMessage = nil

        return LocalPrivacyDeletionSummary(
            keychainEntriesRemoved: keychainEntriesRemoved,
            userDefaultsKeysRemoved: userDefaultsKeysRemoved,
            localFilesRemoved: localFilesRemoved,
            localDirectoriesRemoved: localDirectoriesRemoved,
            failures: failures
        )
    }

    @discardableResult
    func removeImportedOAuthConfiguration() -> Bool {
        do {
            let previousClientID = effectiveClientID
            let nextClientID = bundledClientID
            let clientChanged = OAuthClientBindingPolicy()
                .requiresCredentialInvalidation(
                    previousClientID: previousClientID,
                    nextClientID: nextClientID
                )

            if clientChanged {
                _ = try BlackstockKeychain.deleteAccounts(
                    withPrefix: "youtube."
                )
            }

            try BlackstockKeychain.delete(
                "google.oauth.importedClientID"
            )
            try? BlackstockKeychain.delete(
                "google.oauth.importedClientSecret"
            )
            importedOAuthClientID = ""
            clearOAuthRuntimeAuthorizationState(
                clearChannelSelection: clientChanged
            )
            errorMessage = nil
            return true
        } catch {
            errorMessage = "OAuth-Konfiguration konnte nicht entfernt werden: \(describe(error))"
            return false
        }
    }

    func importPackagingAsset(
        from url: URL,
        projectID: UUID,
        kind: ProjectPackagingAssetKind
    ) throws -> URL {
        let hasSecurityScopedAccess = url.startAccessingSecurityScopedResource()
        defer {
            if hasSecurityScopedAccess {
                url.stopAccessingSecurityScopedResource()
            }
        }

        return try projectWorkspaceStore()
            .importPackagingAsset(
                sourceURL: url,
                projectID: projectID,
                assetID: UUID(),
                kind: kind
            )
    }

    func connectGoogle() async {
        errorMessage = nil
        guard !effectiveClientID.isEmpty else {
            errorMessage = "Keine Google-OAuth-Konfiguration verfügbar. Verwende die integrierte Blackstock-Konfiguration oder importiere eine Desktop-OAuth-JSON."
            return
        }

        isWorking = true
        defer { isWorking = false }

        do {
            let server = try LoopbackOAuthServer()
            let redirectURI = try await server.start()
            let pkce = try PKCEPair.generate()
            let state = try PKCEPair.generate().verifier
            let request = GoogleOAuthAuthorizationRequest(
                clientID: effectiveClientID,
                redirectURI: redirectURI,
                scopes: connectedOAuthScopes,
                state: state,
                pkce: pkce
            )

            guard NSWorkspace.shared.open(request.authorizationURL) else {
                server.cancel()
                errorMessage = "Der Systembrowser konnte nicht geöffnet werden."
                return
            }

            let callbackURL = try await server.waitForCallback()
            guard let components = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false) else {
                throw GoogleOAuthError.invalidAuthorizationResponse
            }
            let items = components.queryItems ?? []
            if let providerError = items.first(where: { $0.name == "error" })?.value {
                errorMessage = "Google-Autorisierung abgebrochen oder abgelehnt: \(providerError)"
                return
            }
            guard items.first(where: { $0.name == "state" })?.value == state else {
                throw GoogleOAuthError.stateMismatch
            }
            guard let code = items.first(where: { $0.name == "code" })?.value, !code.isEmpty else {
                throw GoogleOAuthError.invalidAuthorizationResponse
            }

            let tokens = try await GoogleOAuthTokenExchange().exchange(
                code: code,
                clientID: effectiveClientID,
                clientSecret: effectiveClientSecret,
                redirectURI: redirectURI,
                verifier: pkce.verifier
            )
            let identities = try await YouTubeAuthorizedClient(accessToken: tokens.accessToken).myChannels()
            guard !identities.isEmpty else {
                errorMessage = "Für dieses Google-Konto wurde kein autorisierter YouTube-Kanal gefunden."
                return
            }

            cacheRuntimeToken(
                tokens,
                fallbackScopeString: connectedOAuthScopeString
            )
            channels = identities
            selectedChannelID = nil
            step = .channel
        } catch {
            errorMessage = "Google-Verbindung fehlgeschlagen: \(describe(error))"
        }
    }

    func chooseChannel(_ id: String) async {
        guard channels.contains(where: { $0.id == id }) else {
            return
        }

        selectedChannelID = id
        isWorking = true
        officialChannelSettingsVerified = false
        defer { isWorking = false }

        do {
            if let tokenSet {
                try BlackstockKeychain.write(
                    tokenSet.accessToken,
                    account: "youtube.\(id).accessToken"
                )
                if let refresh = tokenSet.refreshToken,
                   !refresh.isEmpty {
                    try BlackstockKeychain.write(
                        refresh,
                        account: "youtube.\(id).refreshToken"
                    )
                }
                let returnedScope = tokenSet.scope?
                    .trimmingCharacters(
                        in: .whitespacesAndNewlines
                    ) ?? ""
                let persistedScope =
                    returnedScope.isEmpty
                    ? connectedOAuthScopeString
                    : returnedScope
                try BlackstockKeychain.write(
                    persistedScope,
                    account: "youtube.\(id).scopes"
                )
                try BlackstockKeychain.write(
                    effectiveClientID,
                    account: "youtube.\(id).oauthClientID"
                )
            }

            let accessToken =
                tokenSet?.accessToken
                ?? BlackstockKeychain.read(
                    "youtube.\(id).accessToken"
                )
            guard !accessToken.isEmpty else {
                throw PublishingSessionError.missingToken
            }

            try await loadYouTubeChannelSetupOptions(
                channelID: id,
                accessToken: accessToken
            )

            if let scopeString = tokenSet?.scope {
                let granted =
                    GoogleOAuthScopePlanner.parseGrantedScopes(
                        scopeString
                    )
                let publishingScopes: Set<GoogleOAuthScope> = [
                    .youtubeReadOnly,
                    .youtubeUpload,
                    .youtubeForceSSL
                ]
                if publishingScopes.isSubset(of: granted) {
                    publishingAuthorizedChannelID = id
                }
                if granted.contains(.analyticsReadOnly) {
                    analyticsAuthorizedChannelID = id
                }
            }

            workspaceRightsResponsibilityAccepted =
                Self.loadStoredWorkspaceRightsAttestation(
                    channelID: id
                )?.permitsUserDirectedProduction == true
            step = .topic
            errorMessage = nil
        } catch {
            errorMessage =
                "Die YouTube-Kanaleinstellungen konnten nicht geladen werden: \(describe(error))"
        }
    }

    var workspaceChannelID: String? {
        activeProject?.targetChannelID
            ?? UserDefaults.standard.string(
                forKey: "blackstock.workspace.channelID"
            )
    }

    var workspaceChannel: YouTubeChannelIdentity? {
        guard let channelID = workspaceChannelID else {
            return nil
        }
        return channels.first {
            $0.id == channelID
        }
    }

    var workspaceRightsAttestation:
        WorkspaceRightsAttestation? {
        guard let channelID =
            selectedChannelID ?? workspaceChannelID else {
            return nil
        }
        return Self.loadStoredWorkspaceRightsAttestation(
            channelID: channelID
        )
    }

    @discardableResult
    func setWorkspaceRightsResponsibilityAccepted(
        _ accepted: Bool
    ) -> Bool {
        guard let channelID =
            selectedChannelID ?? workspaceChannelID else {
            errorMessage =
                "Wähle zuerst deinen YouTube-Kanal."
            return false
        }

        let key =
            "blackstock.workspace.rightsAttestation.\(channelID)"

        guard accepted else {
            UserDefaults.standard.removeObject(forKey: key)
            workspaceRightsResponsibilityAccepted = false
            errorMessage = nil
            return true
        }

        do {
            let attestation = WorkspaceRightsAttestation(
                channelID: channelID,
                confirmedByUser: true,
                attestedAt: Date()
            )
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            UserDefaults.standard.set(
                try encoder.encode(attestation),
                forKey: key
            )
            workspaceRightsResponsibilityAccepted = true
            errorMessage = nil
            return true
        } catch {
            workspaceRightsResponsibilityAccepted = false
            errorMessage =
                "Die Nutzungsverantwortung konnte nicht gespeichert werden: "
                + describe(error)
            return false
        }
    }

    var publicPublishingAllowed: Bool {
        Bundle.main.object(
            forInfoDictionaryKey: "BlackstockYouTubePublicPublishingApproved"
        ) as? Bool ?? false
    }

    func publishingScopePlan() -> GoogleOAuthScopePlan? {
        guard let channelID = workspaceChannelID else { return nil }
        let storedScopes = BlackstockKeychain.read(
            "youtube.\(channelID).scopes"
        )
        return GoogleOAuthScopePlanner().plan(
            capabilities: [.discoveryReadOnly, .upload, .packaging],
            tokenScopeString: storedScopes
        )
    }

    func authorizePublishing() async {
        guard let project = activeProject else {
            errorMessage = "Kein aktives Projekt für die Veröffentlichung vorhanden."
            return
        }
        guard !effectiveClientID.isEmpty else {
            errorMessage = "Keine Google-OAuth-Konfiguration verfügbar."
            return
        }

        isAuthorizingPublishing = true
        defer { isAuthorizingPublishing = false }
        errorMessage = nil

        do {
            let currentPlan = publishingScopePlan()
            if currentPlan?.state == .alreadyAuthorized {
                let accessToken = try await validatedPublishingAccessToken(
                    targetChannelID: project.targetChannelID
                )
                let identities = try await YouTubeAuthorizedClient(
                    accessToken: accessToken
                ).myChannels()
                do {
                    try PublishingChannelIdentityGuard().validate(
                        targetChannelID: project.targetChannelID,
                        identities: identities
                    )
                } catch {
                    publishingAuthorizedChannelID = nil
                    errorMessage = "Veröffentlichung bleibt gesperrt: \(error.localizedDescription)"
                    return
                }
                publishingAuthorizedChannelID = project.targetChannelID
                return
            }

            let requestedScopes = currentPlan?.scopesForAuthorization
                ?? Set([
                    GoogleOAuthScope.youtubeReadOnly,
                    .youtubeUpload,
                    .youtubeForceSSL
                ])

            let tokens = try await performOAuthAuthorization(
                scopes: requestedScopes
            )

            guard let grantedScopeString = tokens.scope else {
                publishingAuthorizedChannelID = nil
                errorMessage = "Google hat keine verifizierbare Scope-Liste zurückgegeben. Blackstock aktiviert die Veröffentlichung nicht."
                return
            }

            let granted = GoogleOAuthScopePlanner.parseGrantedScopes(
                grantedScopeString
            )
            guard requestedScopes.isSubset(of: granted) else {
                publishingAuthorizedChannelID = nil
                errorMessage = "Nicht alle für die Veröffentlichung benötigten Google-Berechtigungen wurden gewährt."
                return
            }

            let identities = try await YouTubeAuthorizedClient(
                accessToken: tokens.accessToken
            ).myChannels()
            do {
                try PublishingChannelIdentityGuard().validate(
                    targetChannelID: project.targetChannelID,
                    identities: identities
                )
            } catch {
                publishingAuthorizedChannelID = nil
                errorMessage = "Veröffentlichung bleibt gesperrt: \(error.localizedDescription)"
                return
            }

            try BlackstockKeychain.write(
                tokens.accessToken,
                account: "youtube.\(project.targetChannelID).accessToken"
            )
            if let refresh = tokens.refreshToken, !refresh.isEmpty {
                try BlackstockKeychain.write(
                    refresh,
                    account: "youtube.\(project.targetChannelID).refreshToken"
                )
            }
            try BlackstockKeychain.write(
                grantedScopeString,
                account: "youtube.\(project.targetChannelID).scopes"
            )
            try BlackstockKeychain.write(
                effectiveClientID,
                account: "youtube.\(project.targetChannelID).oauthClientID"
            )

            cacheRuntimeToken(
                tokens,
                fallbackScopeString: connectedOAuthScopeString
            )
            publishingAuthorizedChannelID = project.targetChannelID
        } catch {
            publishingAuthorizedChannelID = nil
            errorMessage = "Autorisierung für die Veröffentlichung fehlgeschlagen: \(describe(error))"
        }
    }

    func publishPreparedReview(
        artifact: RenderArtifact,
        asset: ProductionMediaAsset,
        userConfirmed: Bool
    ) async {
        guard userConfirmed else {
            errorMessage = "Bestätige den finalen externen Upload ausdrücklich."
            return
        }
        guard var project = activeProject else {
            errorMessage = "Kein aktives Projekt vorhanden."
            return
        }
        guard !project.isPaused else {
            errorMessage =
                "Das Projekt ist pausiert. Setze es vor dem Upload fort."
            return
        }
        guard let authorizedChannelID = publishingAuthorizedChannelID,
              authorizedChannelID == project.targetChannelID else {
            errorMessage = "Die Veröffentlichung ist für den Projekt-Zielkanal noch nicht verifiziert."
            return
        }
        guard let workspaceChannelID,
              workspaceChannelID == project.targetChannelID else {
            errorMessage = "Der ausgewählte YouTube-Kanal passt nicht zu diesem Projekt."
            return
        }
        guard let preparation = loadPublishPreparation(
            projectID: project.id
        ) else {
            errorMessage = "Keine eingefrorene Veröffentlichungsprüfung vorhanden."
            return
        }

        isPublishing = true
        defer { isPublishing = false }
        errorMessage = nil

        do {
            guard project.stage == .review
                    || project.stage == .publishing else {
                errorMessage = "Projekt ist nicht im Prüf-/Veröffentlichungsstatus."
                return
            }

            let deterministicReview = PublishReviewContext(
                project: project,
                artifact: artifact,
                package: preparation.package,
                qualityReview: preparation.qualityReview,
                rightsValidated: asset.mayEnterProduction,
                publicPublishingAllowed: publicPublishingAllowed,
                userConfirmed: true
            )
            try deterministicReview.validate()

            let accessToken = try await validatedPublishingAccessToken(
                targetChannelID: project.targetChannelID
            )
            let finalIdentities = try await YouTubeAuthorizedClient(
                accessToken: accessToken
            ).myChannels()
            let finalAuthorizedIdentity: YouTubeChannelIdentity
            do {
                finalAuthorizedIdentity = try PublishingChannelIdentityGuard()
                    .validate(
                        targetChannelID: project.targetChannelID,
                        identities: finalIdentities
                    )
                publishingAuthorizedChannelID = finalAuthorizedIdentity.id
            } catch {
                publishingAuthorizedChannelID = nil
                errorMessage = "Upload gestoppt: \(error.localizedDescription)"
                return
            }

            let networkAvailable = await LocalNetworkAvailabilityProbe()
                .currentState() == .available
            guard networkAvailable else {
                errorMessage = project.stage == .review
                    ? "Upload gestoppt: Keine Netzwerkverbindung. Das Projekt bleibt im Prüfstatus."
                    : "Upload pausiert: Keine Netzwerkverbindung. Der bestehende Veröffentlichungs-/Fortsetzungszustand bleibt erhalten."
                return
            }

            if project.stage == .review {
                guard project.advance(
                    to: .publishing,
                    at: Date()
                ) else {
                    errorMessage = "Projekt konnte nach bestandener Vorprüfung nicht in den Veröffentlichungsstatus wechseln."
                    return
                }
                try Self.store(project: project)
                activeProject = project
            }

            guard project.stage == .publishing else {
                errorMessage = "Projekt ist nicht im Veröffentlichungsstatus."
                return
            }

            let review = PublishReviewContext(
                project: project,
                artifact: artifact,
                package: preparation.package,
                qualityReview: preparation.qualityReview,
                rightsValidated: asset.mayEnterProduction,
                publicPublishingAllowed: publicPublishingAllowed,
                userConfirmed: true
            )

            let result = try await YouTubePublishingCoordinator(
                uploadClient: .init(
                    accessToken: accessToken
                ),
                packagingClient: .init(
                    accessToken: accessToken
                )
            )
            .publish(
                review: review,
                workspaceChannelID: workspaceChannelID,
                authorizedUploadChannelID: finalAuthorizedIdentity.id,
                quotaState: .unknown,
                networkAvailable: networkAvailable,
                experimentID: nil,
                journal: try publishingJournal()
            )

            try persistPublishedRecord(
                result.publishedRecord
            )

            guard project.advance(
                to: .published,
                at: Date()
            ) else {
                errorMessage = "Upload war erfolgreich, aber der lokale Projektstatus konnte nicht auf PUBLISHED gesetzt werden."
                lastPublishingResult = result
                return
            }

            try Self.store(project: project)
            activeProject = project
            lastPublishingResult = result
            errorMessage = nil
        } catch {
            errorMessage = "Veröffentlichung fehlgeschlagen oder wurde unterbrochen: \(describe(error)). Der Protokoll-/Fortsetzungszustand bleibt erhalten."
        }
    }

    func refreshWorkspaceChannelIdentity() async {
        guard let channelID = workspaceChannelID else {
            return
        }

        do {
            let accessToken =
                try await validatedReadOnlyAccessToken(
                    targetChannelID: channelID
                )
            let identities =
                try await YouTubeAuthorizedClient(
                    accessToken: accessToken
                ).myChannels()
            guard identities.contains(where: {
                $0.id == channelID
            }) else {
                errorMessage =
                    "Der verbundene YouTube-Kanal ist in der aktuellen Google-Sitzung nicht verfügbar."
                return
            }
            channels = identities
            if selectedChannelID == nil {
                selectedChannelID = channelID
            }
        } catch {
            errorMessage =
                "Kanaldaten konnten nicht aktualisiert werden: "
                + describe(error)
        }
    }

    func analyticsScopePlan() -> GoogleOAuthScopePlan? {
        guard let channelID = workspaceChannelID else { return nil }
        let storedScopes = BlackstockKeychain.read(
            "youtube.\(channelID).scopes"
        )
        return GoogleOAuthScopePlanner().plan(
            capabilities: [.discoveryReadOnly, .analytics],
            tokenScopeString: storedScopes
        )
    }

    func authorizeAnalytics() async {
        guard let channelID = workspaceChannelID else {
            errorMessage =
                "Kein YouTube-Kanal für Analytics verbunden."
            return
        }
        guard !effectiveClientID.isEmpty else {
            errorMessage =
                "Keine Google-OAuth-Konfiguration verfügbar."
            return
        }

        isAuthorizingAnalytics = true
        defer { isAuthorizingAnalytics = false }
        errorMessage = nil

        do {
            let currentPlan = analyticsScopePlan()
            if currentPlan?.state == .alreadyAuthorized {
                let accessToken =
                    try await validatedAnalyticsAccessToken(
                        targetChannelID: channelID
                    )
                let identities =
                    try await YouTubeAuthorizedClient(
                        accessToken: accessToken
                    ).myChannels()
                guard identities.contains(where: {
                    $0.id == channelID
                }) else {
                    analyticsAuthorizedChannelID = nil
                    errorMessage =
                        "Die Analytics-Autorisierung gehört nicht zum verbundenen Kanal."
                    return
                }
                channels = identities
                analyticsAuthorizedChannelID = channelID
                return
            }

            let requestedScopes =
                currentPlan?.scopesForAuthorization
                ?? Set([
                    GoogleOAuthScope.youtubeReadOnly,
                    .analyticsReadOnly
                ])

            let tokens = try await performOAuthAuthorization(
                scopes: requestedScopes
            )

            guard let grantedScopeString = tokens.scope else {
                analyticsAuthorizedChannelID = nil
                errorMessage =
                    "Google hat keine verifizierbare Scope-Liste zurückgegeben. Analytics bleibt gesperrt."
                return
            }

            let granted =
                GoogleOAuthScopePlanner.parseGrantedScopes(
                    grantedScopeString
                )
            guard requestedScopes.isSubset(of: granted) else {
                analyticsAuthorizedChannelID = nil
                errorMessage =
                    "Nicht alle für Analytics benötigten Google-Berechtigungen wurden gewährt."
                return
            }

            let identities =
                try await YouTubeAuthorizedClient(
                    accessToken: tokens.accessToken
                ).myChannels()
            guard identities.contains(where: {
                $0.id == channelID
            }) else {
                analyticsAuthorizedChannelID = nil
                errorMessage =
                    "Die Analytics-Sitzung enthält nicht den verbundenen Kanal."
                return
            }

            try BlackstockKeychain.write(
                tokens.accessToken,
                account:
                    "youtube.\(channelID).accessToken"
            )
            if let refresh = tokens.refreshToken,
               !refresh.isEmpty {
                try BlackstockKeychain.write(
                    refresh,
                    account:
                        "youtube.\(channelID).refreshToken"
                )
            }
            try BlackstockKeychain.write(
                grantedScopeString,
                account:
                    "youtube.\(channelID).scopes"
            )
            try BlackstockKeychain.write(
                effectiveClientID,
                account:
                    "youtube.\(channelID).oauthClientID"
            )

            cacheRuntimeToken(
                tokens,
                fallbackScopeString:
                    connectedOAuthScopeString
            )
            channels = identities
            analyticsAuthorizedChannelID = channelID
        } catch {
            analyticsAuthorizedChannelID = nil
            errorMessage =
                "Analytics-Autorisierung fehlgeschlagen: "
                + describe(error)
        }
    }

    func collectDueGrowthObservations(
        now: Date = Date()
    ) async {
        guard let project = activeProject,
              project.stage == .published else {
            errorMessage = "Lernen aus Analytics-Daten ist erst nach erfolgreicher Veröffentlichung verfügbar."
            return
        }
        guard var record = loadPublishedRecord(
            projectID: project.id
        ) else {
            errorMessage = "Kein Datensatz des veröffentlichten Videos für dieses Projekt vorhanden."
            return
        }

        do {
            try GrowthAnalyticsContextGuard().validate(
                project: project,
                record: record
            )
        } catch {
            errorMessage = "Analytics-Abruf gestoppt: Der veröffentlichte Video-Datensatz stimmt nicht eindeutig mit Projekt, Zielkanal und Video-ID überein."
            return
        }

        isCollectingAnalytics = true
        defer { isCollectingAnalytics = false }
        errorMessage = nil

        do {
            let accessToken = try await validatedAnalyticsAccessToken(
                targetChannelID: project.targetChannelID
            )
            let identities = try await YouTubeAuthorizedClient(
                accessToken: accessToken
            ).myChannels()
            _ = try PublishingChannelIdentityGuard().validate(
                targetChannelID: project.targetChannelID,
                identities: identities
            )

            let due = GrowthObservationPlanner().duePlans(
                for: record,
                now: now
            )

            if due.isEmpty {
                latestGrowthLearning = GrowthLearningEngine()
                    .summarize(record)
                return
            }

            var delayedWindows: [GrowthObservationWindow] = []

            for plan in due {
                do {
                    let snapshot = try await YouTubeAnalyticsClient(
                        accessToken: accessToken,
                        channelID: project.targetChannelID
                    )
                    .snapshot(
                        startDate: plan.requestedStartDate,
                        endDate: plan.requestedEndDate,
                        videoID: record.youtubeVideoID,
                        now: now
                    )

                    record.observations.append(
                        GrowthObservation(
                            window: plan.window,
                            analytics: snapshot,
                            collectedAt: now
                        )
                    )
                } catch YouTubeAnalyticsAPIError.missingRow {
                    delayedWindows.append(plan.window)
                }
            }

            try persistPublishedRecord(record)
            latestGrowthLearning = GrowthLearningEngine()
                .summarize(record)
            if let latestGrowthLearning {
                try persistGrowthLearning(
                    latestGrowthLearning,
                    projectID: record.projectID
                )
            }

            if !delayedWindows.isEmpty {
                errorMessage = "YouTube Analytics hat für \(delayedWindows.map(\.rawValue).joined(separator: ", ")) noch keine vollständigen Daten geliefert. Blackstock speichert dafür keine Nullwerte und versucht es später erneut."
            }
        } catch {
            errorMessage = "Analytics konnten nicht aktualisiert werden: \(describe(error))"
        }
    }

    func collectChannelAnalytics(
        days: Int = 28,
        now: Date = Date()
    ) async {
        guard let channelID = workspaceChannelID else {
            errorMessage =
                "Kein YouTube-Kanal für die Analyse ausgewählt."
            return
        }

        isCollectingAnalytics = true
        defer { isCollectingAnalytics = false }
        errorMessage = nil

        do {
            let accessToken =
                try await validatedAnalyticsAccessToken(
                    targetChannelID: channelID
                )
            let identities =
                try await YouTubeAuthorizedClient(
                    accessToken: accessToken
                ).myChannels()
            guard identities.contains(where: {
                $0.id == channelID
            }) else {
                errorMessage =
                    "Analytics-Abruf gestoppt: Der verbundene Kanal stimmt nicht mit der Google-Sitzung überein."
                return
            }
            channels = identities
            if selectedChannelID == nil {
                selectedChannelID = channelID
            }

            let calendar = Calendar(
                identifier: .gregorian
            )
            let start = calendar.date(
                byAdding: .day,
                value: -max(days - 1, 0),
                to: now
            ) ?? now

            let formatter = DateFormatter()
            formatter.calendar = calendar
            formatter.locale = Locale(
                identifier: "en_US_POSIX"
            )
            formatter.timeZone = TimeZone(
                secondsFromGMT: 0
            )
            formatter.dateFormat = "yyyy-MM-dd"

            latestChannelAnalytics =
                try await YouTubeAnalyticsClient(
                    accessToken: accessToken,
                    channelID: channelID
                ).snapshot(
                    startDate: formatter.string(
                        from: start
                    ),
                    endDate: formatter.string(
                        from: now
                    ),
                    videoID: nil,
                    now: now
                )
        } catch YouTubeAnalyticsAPIError.missingRow {
            latestChannelAnalytics = nil
            errorMessage =
                "YouTube Analytics hat für den Kanal in diesem Zeitraum noch keine Daten geliefert."
        } catch {
            latestChannelAnalytics = nil
            errorMessage =
                "Kanalanalyse konnte nicht aktualisiert werden: "
                + describe(error)
        }
    }

    func validatedReadOnlyAccessToken(
        targetChannelID: String
    ) async throws -> String {
        let storedScopes = BlackstockKeychain.read(
            "youtube.\(targetChannelID).scopes"
        )
        let requiredScopes: Set<GoogleOAuthScope> = [
            .youtubeReadOnly
        ]
        let plan = GoogleOAuthScopePlanner().plan(
            capabilities: [.discoveryReadOnly],
            tokenScopeString: storedScopes
        )
        guard plan.state == .alreadyAuthorized else {
            throw PublishingSessionError.missingScopes
        }
        try validateStoredOAuthClient(
            for: targetChannelID
        )

        if let cached = validRuntimeAccessToken(
            requiredScopes: requiredScopes
        ) {
            return cached
        }

        let refreshToken = BlackstockKeychain.read(
            "youtube.\(targetChannelID).refreshToken"
        )
        if !refreshToken.isEmpty {
            let refreshed =
                try await GoogleOAuthTokenRefresher()
                    .refresh(
                        refreshToken: refreshToken,
                        clientID: effectiveClientID,
                        clientSecret: effectiveClientSecret
                    )
            cacheRuntimeToken(
                refreshed,
                fallbackScopeString: storedScopes
            )
            try BlackstockKeychain.write(
                refreshed.accessToken,
                account:
                    "youtube.\(targetChannelID).accessToken"
            )
            return refreshed.accessToken
        }

        let accessToken = BlackstockKeychain.read(
            "youtube.\(targetChannelID).accessToken"
        )
        guard !accessToken.isEmpty else {
            throw PublishingSessionError.missingToken
        }
        return accessToken
    }

    func loadPublishedComments(
        project: BlackstockProject,
        record: PublishedVideoRecord
    ) async {
        guard project.stage == .published,
              record.projectID == project.id,
              record.targetChannelID == project.targetChannelID else {
            errorMessage = "Kommentare können nur für das eindeutig veröffentlichte Projekt geladen werden."
            return
        }

        isLoadingComments = true
        defer { isLoadingComments = false }

        do {
            let accessToken = try await validatedReadOnlyAccessToken(
                targetChannelID: project.targetChannelID
            )
            let identities = try await YouTubeAuthorizedClient(
                accessToken: accessToken
            ).myChannels()
            _ = try PublishingChannelIdentityGuard().validate(
                targetChannelID: project.targetChannelID,
                identities: identities
            )

            let page = try await YouTubeCommentsClient(
                accessToken: accessToken
            ).listThreads(
                videoID: record.youtubeVideoID,
                maxResults: 20,
                order: .time
            )

            do {
                try YouTubeCommentContextGuard().validate(
                    page: page,
                    expectedVideoID: record.youtubeVideoID,
                    expectedChannelID: project.targetChannelID
                )
            } catch {
                latestCommentPage = nil
                latestCommentsVideoID = nil
                errorMessage = "Kommentarabruf gestoppt: YouTube lieferte Daten für einen unerwarteten Video- oder Kanalkontext."
                return
            }

            latestCommentPage = page
            latestCommentsVideoID = record.youtubeVideoID
            errorMessage = nil
        } catch YouTubeCommentsError.commentsDisabled {
            latestCommentPage = nil
            latestCommentsVideoID = record.youtubeVideoID
            errorMessage = "Kommentare sind für dieses YouTube-Video deaktiviert."
        } catch YouTubeCommentsError.videoNotFound {
            latestCommentPage = nil
            latestCommentsVideoID = nil
            errorMessage = "Das veröffentlichte YouTube-Video wurde beim Kommentarabruf nicht gefunden."
        } catch {
            latestCommentPage = nil
            latestCommentsVideoID = nil
            errorMessage = "Kommentare konnten nicht geladen werden: \(describe(error))"
        }
    }

    func validatedAnalyticsAccessToken(
        targetChannelID: String
    ) async throws -> String {
        let storedScopes = BlackstockKeychain.read(
            "youtube.\(targetChannelID).scopes"
        )
        let requiredScopes: Set<GoogleOAuthScope> = [
            .youtubeReadOnly,
            .analyticsReadOnly
        ]
        let plan = GoogleOAuthScopePlanner().plan(
            capabilities: [
                .discoveryReadOnly,
                .analytics
            ],
            tokenScopeString: storedScopes
        )
        guard plan.state == .alreadyAuthorized else {
            throw PublishingSessionError.missingScopes
        }
        try validateStoredOAuthClient(
            for: targetChannelID
        )

        if let cached = validRuntimeAccessToken(
            requiredScopes: requiredScopes
        ) {
            return cached
        }

        let refreshToken = BlackstockKeychain.read(
            "youtube.\(targetChannelID).refreshToken"
        )
        if !refreshToken.isEmpty {
            let refreshed =
                try await GoogleOAuthTokenRefresher()
                    .refresh(
                        refreshToken: refreshToken,
                        clientID: effectiveClientID,
                        clientSecret: effectiveClientSecret
                    )
            cacheRuntimeToken(
                refreshed,
                fallbackScopeString: storedScopes
            )
            try BlackstockKeychain.write(
                refreshed.accessToken,
                account:
                    "youtube.\(targetChannelID).accessToken"
            )
            return refreshed.accessToken
        }

        let accessToken = BlackstockKeychain.read(
            "youtube.\(targetChannelID).accessToken"
        )
        guard !accessToken.isEmpty else {
            throw PublishingSessionError.missingToken
        }
        return accessToken
    }

    func validatedPublishingAccessToken(
        targetChannelID: String
    ) async throws -> String {
        let storedScopes = BlackstockKeychain.read(
            "youtube.\(targetChannelID).scopes"
        )
        let requiredScopes: Set<GoogleOAuthScope> = [
            .youtubeReadOnly,
            .youtubeUpload,
            .youtubeForceSSL
        ]
        let plan = GoogleOAuthScopePlanner().plan(
            capabilities: [
                .discoveryReadOnly,
                .upload,
                .packaging
            ],
            tokenScopeString: storedScopes
        )
        guard plan.state == .alreadyAuthorized else {
            throw PublishingSessionError.missingScopes
        }
        try validateStoredOAuthClient(
            for: targetChannelID
        )

        if let cached = validRuntimeAccessToken(
            requiredScopes: requiredScopes
        ) {
            return cached
        }

        let refreshToken = BlackstockKeychain.read(
            "youtube.\(targetChannelID).refreshToken"
        )
        if !refreshToken.isEmpty {
            let refreshed =
                try await GoogleOAuthTokenRefresher()
                    .refresh(
                        refreshToken: refreshToken,
                        clientID: effectiveClientID,
                        clientSecret: effectiveClientSecret
                    )
            cacheRuntimeToken(
                refreshed,
                fallbackScopeString: storedScopes
            )
            try BlackstockKeychain.write(
                refreshed.accessToken,
                account:
                    "youtube.\(targetChannelID).accessToken"
            )
            return refreshed.accessToken
        }

        let accessToken = BlackstockKeychain.read(
            "youtube.\(targetChannelID).accessToken"
        )
        guard !accessToken.isEmpty else {
            throw PublishingSessionError.missingToken
        }
        return accessToken
    }

    func savePublishPreparation(
        package: PublishPackage,
        qualityReview: CreatorQualityReview,
        packagingVariants: PackagingVariantSet? = nil
    ) throws {
        let snapshot = PublishPreparationSnapshot(
            package: package,
            qualityReview: qualityReview,
            packagingVariants: packagingVariants,
            savedAt: Date()
        )
        try projectWorkspaceStore()
            .savePublishPreparation(snapshot)
        UserDefaults.standard.removeObject(
            forKey: "blackstock.publish-preparation.\(package.projectID.uuidString)"
        )
    }

    func loadPublishPreparation(
        projectID: UUID
    ) -> PublishPreparationSnapshot? {
        do {
            let store = try projectWorkspaceStore()
            let loadResult = try store
                .loadPublishPreparationWithRecovery(
                    projectID: projectID
                )
            if let snapshot = loadResult.snapshot {
                if loadResult.recoveredFromBackup {
                    errorMessage = "Die gespeicherte Veröffentlichungsprüfung war beschädigt. Blackstock hat den letzten validierten lokalen Backup-Stand wiederhergestellt."
                }
                return snapshot
            }

            // One-time migration from the earlier UserDefaults storage.
            let key = "blackstock.publish-preparation.\(projectID.uuidString)"
            guard let data = UserDefaults.standard.data(
                forKey: key
            ) else {
                return nil
            }
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let snapshot = try decoder.decode(
                PublishPreparationSnapshot.self,
                from: data
            )
            guard snapshot.package.projectID == projectID else {
                return nil
            }
            try store.savePublishPreparation(snapshot)
            UserDefaults.standard.removeObject(forKey: key)
            return snapshot
        } catch {
            errorMessage = "Die gespeicherte Veröffentlichungsprüfung konnte nicht sicher geladen oder wiederhergestellt werden: \(describe(error))"
            return nil
        }
    }

    func publishingJournal() throws -> ExternalActionJournal {
        if let cachedPublishingJournal {
            return cachedPublishingJournal
        }

        let base = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let url = base
            .appendingPathComponent("Blackstock", isDirectory: true)
            .appendingPathComponent(
                "external-action-journal.json"
            )
        let journal = try ExternalActionJournal.persistent(at: url)
        cachedPublishingJournal = journal
        return journal
    }

    private func persistGrowthLearning(
        _ learning: GrowthLearningRecord,
        projectID: UUID? = nil
    ) throws {
        let resolvedProjectID = projectID
            ?? activeProject?.id
        guard let resolvedProjectID else {
            return
        }
        try growthRecordStore().save(
            learning: learning,
            projectID: resolvedProjectID
        )
    }

    private func persistPublishedRecord(
        _ record: PublishedVideoRecord
    ) throws {
        try growthRecordStore().save(
            record: record
        )
        UserDefaults.standard.removeObject(
            forKey: "blackstock.published-record.\(record.projectID.uuidString)"
        )
    }

    func loadPublishedRecord(
        projectID: UUID
    ) -> PublishedVideoRecord? {
        do {
            let store = try growthRecordStore()
            if let record = try store.loadRecord(
                projectID: projectID
            ) {
                return record
            }

            // One-time migration from the earlier UserDefaults storage.
            let key = "blackstock.published-record.\(projectID.uuidString)"
            guard let data = UserDefaults.standard.data(
                forKey: key
            ) else {
                return nil
            }
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let record = try decoder.decode(
                PublishedVideoRecord.self,
                from: data
            )
            try store.save(record: record)
            UserDefaults.standard.removeObject(
                forKey: key
            )
            return record
        } catch {
            return nil
        }
    }

    func loadGrowthLearning(
        projectID: UUID
    ) -> GrowthLearningRecord? {
        try? growthRecordStore().loadLearning(
            projectID: projectID
        )
    }

    private func researchDecisionStore() throws -> ResearchDecisionStore {
        let base = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let root = base
            .appendingPathComponent("Blackstock", isDirectory: true)
            .appendingPathComponent("Research", isDirectory: true)
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: true
        )
        return ResearchDecisionStore(rootURL: root)
    }

    private func projectWorkspaceStore() throws -> ProjectWorkspaceStore {
        let base = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let root = base
            .appendingPathComponent("Blackstock", isDirectory: true)
            .appendingPathComponent("Projects", isDirectory: true)
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: true
        )
        return ProjectWorkspaceStore(rootURL: root)
    }

    private func growthRecordStore() throws -> GrowthRecordStore {
        let base = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let root = base
            .appendingPathComponent(
                "Blackstock",
                isDirectory: true
            )
            .appendingPathComponent(
                "Growth",
                isDirectory: true
            )
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: true
        )
        return GrowthRecordStore(
            rootURL: root
        )
    }

    private func performOAuthAuthorization(
        scopes: Set<GoogleOAuthScope>
    ) async throws -> GoogleOAuthTokenSet {
        let server = try LoopbackOAuthServer()
        let redirectURI = try await server.start()
        let pkce = try PKCEPair.generate()
        let state = try PKCEPair.generate().verifier
        let request = GoogleOAuthAuthorizationRequest(
            clientID: effectiveClientID,
            redirectURI: redirectURI,
            scopes: scopes,
            state: state,
            pkce: pkce
        )

        guard NSWorkspace.shared.open(request.authorizationURL) else {
            server.cancel()
            throw PublishingSessionError.browserOpenFailed
        }

        let callbackURL = try await server.waitForCallback()
        guard let components = URLComponents(
            url: callbackURL,
            resolvingAgainstBaseURL: false
        ) else {
            throw GoogleOAuthError.invalidAuthorizationResponse
        }
        let items = components.queryItems ?? []
        if let providerError = items.first(where: {
            $0.name == "error"
        })?.value {
            throw PublishingSessionError.providerRejected(
                providerError
            )
        }
        guard items.first(where: {
            $0.name == "state"
        })?.value == state else {
            throw GoogleOAuthError.stateMismatch
        }
        guard let code = items.first(where: {
            $0.name == "code"
        })?.value, !code.isEmpty else {
            throw GoogleOAuthError.invalidAuthorizationResponse
        }

        return try await GoogleOAuthTokenExchange().exchange(
            code: code,
            clientID: effectiveClientID,
            clientSecret: effectiveClientSecret,
            redirectURI: redirectURI,
            verifier: pkce.verifier
        )
    }


    private func channelSetupAccessToken(
        targetChannelID: String
    ) async throws -> String {
        // Setup/discovery must stay on the already granted read-only
        // authorization. Asking for channel-management here caused a second
        // browser login during onboarding even though the user had already
        // connected Google.
        return try await validatedReadOnlyAccessToken(
            targetChannelID: targetChannelID
        )
    }

    private func loadYouTubeChannelSetupOptions(
        channelID: String,
        accessToken: String
    ) async throws {
        isLoadingYouTubeSetupOptions = true
        defer { isLoadingYouTubeSetupOptions = false }

        let client = YouTubeChannelSetupClient(
            accessToken: accessToken
        )

        async let languagesRequest =
            client.supportedLanguages(
                displayLanguage: "de"
            )
        async let regionsRequest =
            client.supportedRegions(
                displayLanguage: "de"
            )
        async let setupRequest =
            client.currentChannelSetup(
                channelID: channelID
            )

        let (languages, regions, setup) = try await (
            languagesRequest,
            regionsRequest,
            setupRequest
        )
        guard !languages.isEmpty, !regions.isEmpty else {
            throw YouTubeChannelSetupError.invalidResponse
        }

        youtubeLanguages = languages
        youtubeRegions = regions

        let storedRegion = UserDefaults.standard.string(
            forKey: "blackstock.workspace.regionCode"
        )
        let localRegion = Locale.current.region?.identifier
        let regionCandidates = [
            setup.countryCode,
            storedRegion,
            localRegion,
            "DE",
            regions.first?.code
        ].compactMap { $0 }
        guard let region = regionCandidates.first(where: {
            candidate in
            regions.contains(where: {
                $0.code == candidate
            })
        }) else {
            throw YouTubeChannelSetupError.invalidResponse
        }
        channelRegionCode = region

        let storedLanguage = UserDefaults.standard.string(
            forKey: "blackstock.workspace.contentLanguage"
        )
        let languageCandidates = [
            setup.defaultLanguage,
            storedLanguage,
            contentLanguage,
            "de",
            languages.first?.code
        ].compactMap { $0 }
        guard let language = languageCandidates.first(where: {
            candidate in
            languages.contains(where: {
                $0.code == candidate
            })
        }) else {
            throw YouTubeChannelSetupError.invalidResponse
        }
        contentLanguage = language

        if setup.selfDeclaredMadeForKids == true {
            channelAudienceSetting = .madeForKids
        } else if setup.selfDeclaredMadeForKids == false {
            channelAudienceSetting = .notMadeForKids
        } else {
            channelAudienceSetting = .perVideo
        }

        youtubeVideoCategories = try await client.videoCategories(
            regionCode: channelRegionCode,
            languageCode: contentLanguage
        )
        guard !youtubeVideoCategories.isEmpty else {
            throw YouTubeChannelSetupError.invalidResponse
        }

        let storedCategory =
            UserDefaults.standard.string(
                forKey: "blackstock.workspace.channelCategoryID"
            )
            ?? UserDefaults.standard.string(
                forKey: "blackstock.workspace.videoCategoryID"
            )
        if let storedCategory,
           youtubeVideoCategories.contains(where: {
                $0.id == storedCategory
           }) {
            channelCategoryID = storedCategory
        } else {
            channelCategoryID =
                youtubeVideoCategories.first?.id ?? ""
        }

        syncStructuredStrategyFields()
    }

    func ensureYouTubeDiscoveryOptionsLoaded() async {
        guard let channelID =
                selectedChannelID ?? workspaceChannelID else {
            return
        }
        guard youtubeLanguages.isEmpty
                || youtubeRegions.isEmpty
                || youtubeVideoCategories.isEmpty else {
            return
        }

        errorMessage = nil
        do {
            let accessToken =
                try await channelSetupAccessToken(
                    targetChannelID: channelID
                )
            try await loadYouTubeChannelSetupOptions(
                channelID: channelID,
                accessToken: accessToken
            )
        } catch {
            errorMessage =
                "YouTube-Suchparameter konnten nicht geladen werden: "
                + describe(error)
        }
    }

    func refreshYouTubeVideoCategories() async {
        guard let channelID =
            selectedChannelID ?? workspaceChannelID,
              !channelRegionCode.isEmpty,
              !contentLanguage.isEmpty else {
            return
        }

        isLoadingYouTubeSetupOptions = true
        defer { isLoadingYouTubeSetupOptions = false }
        errorMessage = nil

        do {
            let accessToken = try await channelSetupAccessToken(
                targetChannelID: channelID
            )
            let categories =
                try await YouTubeChannelSetupClient(
                    accessToken: accessToken
                ).videoCategories(
                    regionCode: channelRegionCode,
                    languageCode: contentLanguage
                )
            guard !categories.isEmpty else {
                throw YouTubeChannelSetupError.invalidResponse
            }
            youtubeVideoCategories = categories
            if !categories.contains(where: {
                $0.id == channelCategoryID
            }) {
                channelCategoryID =
                    categories.first?.id ?? ""
            }
            syncStructuredStrategyFields()
        } catch {
            errorMessage =
                "YouTube-Kategorien konnten nicht aktualisiert werden: \(describe(error))"
        }
    }

    func ensureYouTubePublishingOptionsLoaded() async {
        guard youtubeVideoCategories.isEmpty,
              let channelID = workspaceChannelID,
              !channelRegionCode.isEmpty,
              !contentLanguage.isEmpty else {
            return
        }

        do {
            let accessToken = try await validatedReadOnlyAccessToken(
                targetChannelID: channelID
            )
            youtubeVideoCategories =
                try await YouTubeChannelSetupClient(
                    accessToken: accessToken
                ).videoCategories(
                    regionCode: channelRegionCode,
                    languageCode: contentLanguage
                )
        } catch {
            errorMessage =
                "YouTube-Kategorien konnten nicht geladen werden: \(describe(error))"
        }
    }

    private func syncStructuredStrategyFields() {
        guard let category = youtubeVideoCategories.first(
            where: { $0.id == channelCategoryID }
        ) else {
            return
        }
        primaryTopic = category.title
        strategyAudienceHypothesis =
            channelAudienceSetting.strategyLabel
        strategyContentPromise =
            "\(category.title) · \(channelAudienceSetting.strategyLabel)"
        strategyPillarsText = category.title
        strategyAdjacentTopicsText = ""
        strategyExcludedTopicsText = ""
    }

    func continueFromTopic() async {
        guard selectedChannel != nil else {
            errorMessage = "Wähle zuerst deinen YouTube-Kanal."
            return
        }
        guard !channelRegionCode.isEmpty else {
            errorMessage = "Wähle Land oder Region aus."
            return
        }
        guard !contentLanguage.isEmpty else {
            errorMessage = "Wähle die Content-Sprache aus."
            return
        }
        guard youtubeVideoCategories.contains(where: {
            $0.id == channelCategoryID
        }) else {
            errorMessage = "Wähle eine Video-Kategorie aus."
            return
        }

        syncStructuredStrategyFields()
        isWorking = true
        officialChannelSettingsVerified = false
        errorMessage = nil
        defer { isWorking = false }

        // These values define Blackstock's local discovery/publishing profile.
        // They are intentionally not written back to the YouTube channel here.
        // That keeps first-run read-only and prevents unnecessary reauthorization.
        UserDefaults.standard.set(
            channelRegionCode,
            forKey: "blackstock.workspace.regionCode"
        )
        UserDefaults.standard.set(
            channelCategoryID,
            forKey: "blackstock.workspace.channelCategoryID"
        )
        UserDefaults.standard.set(
            channelAudienceSetting.rawValue,
            forKey: "blackstock.workspace.channelAudience"
        )
        UserDefaults.standard.set(
            primaryTopic,
            forKey: "blackstock.workspace.primaryTopic"
        )
        UserDefaults.standard.set(
            contentLanguage,
            forKey: "blackstock.workspace.contentLanguage"
        )

        channelAudienceAppliedToYouTube = nil
        officialChannelSettingsVerified = true
        step = .language
    }

    func prepareChannelAndLoadOpportunities() async {
        guard let channel = selectedChannel else {
            errorMessage = "Kein Zielkanal ausgewählt."
            return
        }
        guard !channelCategoryID.isEmpty,
              !channelRegionCode.isEmpty,
              !contentLanguage.isEmpty else {
            errorMessage =
                "Die YouTube-Kanaleinstellungen sind noch nicht vollständig."
            return
        }

        syncStructuredStrategyFields()
        guard !primaryTopic.isEmpty else {
            errorMessage = "Keine YouTube-Kategorie ausgewählt."
            return
        }

        step = .preparing
        isWorking = true
        errorMessage = nil
        opportunities = []
        defer { isWorking = false }

        do {
            let accessToken =
                try await validatedReadOnlyAccessToken(
                    targetChannelID: channel.id
                )

            let strategy = try ChannelStrategyDraft(
                primaryTopic: primaryTopic,
                contentPromise: strategyContentPromise,
                audienceHypothesis:
                    strategyAudienceHypothesis,
                pillarsText: strategyPillarsText,
                adjacentTopicsText:
                    strategyAdjacentTopicsText,
                excludedTopicsText:
                    strategyExcludedTopicsText,
                objective: strategyObjective
            ).makeStrategy(
                channelID: channel.id,
                contentLanguage: contentLanguage,
                version: nextStrategyVersion(
                    for: channel.id
                )
            )
            try persist(strategy: strategy)

            let candidates =
                try await YouTubeAuthorizedClient(
                    accessToken: accessToken
                ).categoryOpportunityCandidates(
                    categoryID: channelCategoryID,
                    categoryTitle: primaryTopic,
                    regionCode: channelRegionCode,
                    relevanceLanguage: contentLanguage,
                    timeWindow: opportunityTimeWindow,
                    maxResults: 12,
                    order: .views
                )
            opportunities = candidates
            step = .opportunities

            if candidates.isEmpty {
                errorMessage =
                    "Für diese Auswahl sind gerade keine Videos verfügbar. Ändere Kategorie, Region oder Zeitraum."
            }
        } catch {
            step = .opportunities
            errorMessage =
                "Videos konnten nicht geladen werden: \(describe(error))"
        }
    }

    func reloadOpportunities(order: OpportunitySortMode) async {
        if !channelCategoryID.isEmpty,
           !channelRegionCode.isEmpty,
           !contentLanguage.isEmpty,
           let channelID =
                selectedChannelID ?? workspaceChannelID {
            isWorking = true
            defer { isWorking = false }
            do {
                let accessToken =
                    try await validatedReadOnlyAccessToken(
                        targetChannelID: channelID
                    )
                opportunities =
                    try await YouTubeAuthorizedClient(
                        accessToken: accessToken
                    ).categoryOpportunityCandidates(
                        categoryID: channelCategoryID,
                        categoryTitle: primaryTopic,
                        regionCode: channelRegionCode,
                        relevanceLanguage: contentLanguage,
                        timeWindow: opportunityTimeWindow,
                        maxResults: 12,
                        order: order
                    )
                errorMessage = nil
            } catch {
                errorMessage =
                    "Videos konnten nicht geladen werden: \(describe(error))"
            }
            return
        }

        await loadWorkspaceOpportunities(
            query: primaryTopic,
            order: order
        )
    }

    func loadWorkspaceOpportunities(
        query: String,
        order: OpportunitySortMode,
        timeWindow: OpportunityTimeWindow? = nil,
        contentFilter: OpportunityContentFilter? = nil
    ) async {
        let resolvedQuery = query.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        let resolvedTimeWindow =
            timeWindow ?? opportunityTimeWindow
        let resolvedContentFilter =
            contentFilter ?? opportunityContentFilter
        opportunityContentFilter = resolvedContentFilter
        let defaults = UserDefaults.standard
        defaults.set(
            resolvedContentFilter.rawValue,
            forKey: "blackstock.workspace.opportunityContentFilter"
        )
        defaults.set(
            resolvedTimeWindow.rawValue,
            forKey: "blackstock.workspace.opportunityTimeWindow"
        )
        defaults.set(
            channelCategoryID,
            forKey: "blackstock.workspace.channelCategoryID"
        )
        defaults.set(
            channelRegionCode,
            forKey: "blackstock.workspace.regionCode"
        )
        defaults.set(
            contentLanguage,
            forKey: "blackstock.workspace.contentLanguage"
        )
        defaults.set(
            primaryTopic,
            forKey: "blackstock.workspace.primaryTopic"
        )

        guard let channelID = workspaceChannelID else {
            errorMessage = "Kein YouTube-Kanal ist verbunden."
            return
        }

        isWorking = true
        errorMessage = nil
        defer { isWorking = false }

        do {
            let accessToken =
                try await validatedReadOnlyAccessToken(
                    targetChannelID: channelID
                )
            let client = YouTubeAuthorizedClient(
                accessToken: accessToken
            )
            let candidates: [YouTubeOpportunityCandidate]

            if resolvedQuery.isEmpty,
               !channelCategoryID.isEmpty,
               !channelRegionCode.isEmpty {
                candidates = try await client
                    .categoryOpportunityCandidates(
                        categoryID: channelCategoryID,
                        categoryTitle: primaryTopic,
                        regionCode: channelRegionCode,
                        relevanceLanguage: contentLanguage,
                        timeWindow: resolvedTimeWindow,
                        maxResults: 20,
                        order: order,
                        contentFilter: resolvedContentFilter
                    )
            } else {
                guard !resolvedQuery.isEmpty else {
                    errorMessage =
                        "Wähle eine Kanal-Kategorie oder gib einen Suchbegriff ein."
                    return
                }
                candidates = try await client
                    .firstOpportunityCandidates(
                        query: resolvedQuery,
                        categoryID: channelCategoryID.isEmpty
                            ? nil
                            : channelCategoryID,
                        regionCode: channelRegionCode.isEmpty
                            ? nil
                            : channelRegionCode,
                        relevanceLanguage:
                            contentLanguage.isEmpty
                            ? nil
                            : contentLanguage,
                        publishedAfter:
                            resolvedTimeWindow
                                .publishedAfter(now: Date()),
                        maxResults: 20,
                        order: order,
                        contentFilter: resolvedContentFilter
                    )
            }

            opportunities = candidates
            if candidates.isEmpty {
                errorMessage =
                    "YouTube hat für diese Kategorie, Region und diesen Zeitraum aktuell keine passenden Videos geliefert."
            }
        } catch {
            errorMessage =
                "Videos konnten nicht geladen werden: \(describe(error))"
        }
    }

    func useOpportunity(_ opportunity: YouTubeOpportunityCandidate) {
        useOpportunity(
            opportunity,
            productionIntentKind: .standardProject
        )
    }

    func useOpportunityAsClip(
        _ opportunity: YouTubeOpportunityCandidate
    ) {
        guard workspaceRightsAttestation?
            .permitsUserDirectedProduction == true else {
            errorMessage =
                "Bestätige einmalig die Nutzungsrechte, bevor du einen Clip erstellst."
            return
        }
        useOpportunity(
            opportunity,
            productionIntentKind: .clipFromOpportunity
        )
    }

    func productionIntent(
        for projectID: UUID
    ) -> ProjectProductionIntent? {
        Self.loadStoredProductionIntent(projectID: projectID)
    }

    func projectChannelCategoryID(
        for projectID: UUID
    ) -> String? {
        productionIntent(for: projectID)?
            .channelCategoryID
            ?? (channelCategoryID.isEmpty
                ? nil
                : channelCategoryID)
    }

    func projectChannelCategoryTitle(
        for projectID: UUID
    ) -> String? {
        productionIntent(for: projectID)?
            .channelCategoryTitle
            ?? (primaryTopic.isEmpty
                ? nil
                : primaryTopic)
    }

    private func useOpportunity(
        _ opportunity: YouTubeOpportunityCandidate,
        productionIntentKind: ProjectProductionIntentKind
    ) {
        guard let channelID = selectedChannelID ?? workspaceChannelID else {
            errorMessage = "Kein Zielkanal ausgewählt."
            return
        }

        do {
            let seed = try OpportunityProjectFactory().make(
                opportunity: opportunity,
                targetChannelID: channelID,
                strategyVersion: storedStrategyVersion(for: channelID),
                initialStage:
                    productionIntentKind == .clipFromOpportunity
                    ? .production
                    : .research
            )
            try Self.store(project: seed.project)
            try Self.store(
                source: seed.source,
                projectID: seed.project.id
            )
            try Self.store(
                productionIntent: ProjectProductionIntent(
                    projectID: seed.project.id,
                    sourceID: seed.source.id,
                    kind: productionIntentKind,
                    channelCategoryID: channelCategoryID,
                    channelCategoryTitle: primaryTopic,
                    regionCode: channelRegionCode,
                    contentLanguage: contentLanguage,
                    createdAt: Date()
                )
            )
            if productionIntentKind == .standardProject {
                let providerFacts = Self.providerFacts(
                    for: opportunity
                )
                try researchDecisionStore().saveResearch(
                    ResearchEvidenceRecord(
                        projectID: seed.project.id,
                        opportunityID: opportunity.id,
                        source: seed.source,
                        researchQuestion: "",
                        providerFacts: providerFacts,
                        creatorNotes: "",
                        createdAt: Date()
                    )
                )
            }
            activeProject = seed.project
            activeOpportunitySource = seed.source
            lastPublishingResult = nil
            latestGrowthLearning = nil
            latestCommentPage = nil
            latestCommentsVideoID = nil
            UserDefaults.standard.set(channelID, forKey: "blackstock.workspace.channelID")
            UserDefaults.standard.set(primaryTopic, forKey: "blackstock.workspace.primaryTopic")
            UserDefaults.standard.set(contentLanguage, forKey: "blackstock.workspace.contentLanguage")
        UserDefaults.standard.set(
            channelRegionCode,
            forKey: "blackstock.workspace.regionCode"
        )
        UserDefaults.standard.set(
            channelCategoryID,
            forKey: "blackstock.workspace.channelCategoryID"
        )
        UserDefaults.standard.set(
            opportunityTimeWindow.rawValue,
            forKey: "blackstock.workspace.opportunityTimeWindow"
        )
        UserDefaults.standard.set(
            opportunityContentFilter.rawValue,
            forKey: "blackstock.workspace.opportunityContentFilter"
        )
        UserDefaults.standard.set(
            channelAudienceSetting.rawValue,
            forKey: "blackstock.workspace.channelAudience"
        )
            UserDefaults.standard.set(true, forKey: "blackstock.firstRun.complete")
            onboardingComplete = true
            errorMessage = nil
        } catch {
            errorMessage = "Das Blackstock-Projekt konnte nicht gespeichert werden: \(describe(error))"
        }
    }

    func finishFirstRun() {
        guard selectedChannel != nil, !opportunities.isEmpty else { return }
        UserDefaults.standard.set(selectedChannelID, forKey: "blackstock.workspace.channelID")
        UserDefaults.standard.set(primaryTopic, forKey: "blackstock.workspace.primaryTopic")
        UserDefaults.standard.set(contentLanguage, forKey: "blackstock.workspace.contentLanguage")
        UserDefaults.standard.set(
            channelRegionCode,
            forKey: "blackstock.workspace.regionCode"
        )
        UserDefaults.standard.set(
            channelCategoryID,
            forKey: "blackstock.workspace.channelCategoryID"
        )
        UserDefaults.standard.set(
            opportunityTimeWindow.rawValue,
            forKey: "blackstock.workspace.opportunityTimeWindow"
        )
        UserDefaults.standard.set(
            opportunityContentFilter.rawValue,
            forKey: "blackstock.workspace.opportunityContentFilter"
        )
        UserDefaults.standard.set(
            channelAudienceSetting.rawValue,
            forKey: "blackstock.workspace.channelAudience"
        )
        UserDefaults.standard.set(true, forKey: "blackstock.firstRun.complete")
        onboardingComplete = true
    }

    func loadResearchEvidence(
        projectID: UUID
    ) -> ResearchEvidenceRecord? {
        try? researchDecisionStore().loadResearch(
            projectID: projectID
        )
    }

    func loadAnalysisDecision(
        projectID: UUID
    ) -> AnalysisDecisionRecord? {
        try? researchDecisionStore().loadAnalysis(
            projectID: projectID
        )
    }

    @discardableResult
    func completeResearch(
        question: String,
        creatorNotes: String
    ) -> Bool {
        guard let project = activeProject,
              project.stage == .research,
              let existing = loadResearchEvidence(
                projectID: project.id
              ) else {
            errorMessage = "Für dieses Projekt liegen keine gebundenen Recherchebelege vor."
            return false
        }

        let completed = ResearchEvidenceRecord(
            projectID: project.id,
            opportunityID: existing.opportunityID,
            source: existing.source,
            researchQuestion: question,
            providerFacts: existing.providerFacts,
            creatorNotes: creatorNotes,
            createdAt: Date()
        )
        guard completed.isComplete else {
            errorMessage = "Für die Recherche fehlen noch Frage und Notizen."
            return false
        }

        do {
            try researchDecisionStore().saveResearch(completed)
        } catch {
            errorMessage = "Recherchebelege konnten nicht gespeichert werden: \(describe(error))"
            return false
        }
        return advanceActiveProject(to: .analysis)
    }

    @discardableResult
    func completeAnalysis(
        decision: ProductionDecision,
        rationale: String,
        riskOrUnknown: String
    ) -> Bool {
        guard let project = activeProject,
              project.stage == .analysis,
              let research = loadResearchEvidence(
                projectID: project.id
              ),
              research.isComplete else {
            errorMessage = "Analyse bleibt gesperrt, bis vollständige Recherchebelege vorliegen."
            return false
        }

        let record = AnalysisDecisionRecord(
            projectID: project.id,
            decision: decision,
            rationale: rationale,
            riskOrUnknown: riskOrUnknown,
            createdAt: Date()
        )
        guard record.isComplete else {
            errorMessage = "Analyse benötigt eine Begründung und mindestens ein offenes Risiko oder eine Unsicherheit."
            return false
        }

        do {
            try researchDecisionStore().saveAnalysis(record)
        } catch {
            errorMessage = "Analyse-Entscheidung konnte nicht gespeichert werden: \(describe(error))"
            return false
        }

        guard decision == .pursue else {
            errorMessage = "Das Video wurde für dieses Projekt verworfen."
            return false
        }
        return advanceActiveProject(to: .production)
    }

    @discardableResult
    func advanceActiveProject(
        to destination: BlackstockStage
    ) -> Bool {
        guard var project = activeProject else {
            errorMessage = "Kein aktives Projekt vorhanden."
            return false
        }
        guard !project.isPaused else {
            errorMessage =
                "Das Projekt ist pausiert. Setze es zuerst fort."
            return false
        }
        guard project.advance(to: destination, at: Date()) else {
            errorMessage = "Projekt kann nicht direkt von \(project.stage.rawValue) nach \(destination.rawValue) wechseln."
            return false
        }

        do {
            try Self.store(project: project)
            activeProject = project
            errorMessage = nil
            return true
        } catch {
            errorMessage = "Projektstatus konnte nicht gespeichert werden: \(describe(error))"
            return false
        }
    }

    @discardableResult
    func setProjectPaused(
        _ projectID: UUID,
        paused: Bool
    ) -> Bool {
        guard var project = projects.first(
            where: { $0.id == projectID }
        ) else {
            errorMessage = "Projekt nicht gefunden."
            return false
        }

        project.setPaused(paused, at: Date())
        do {
            try Self.store(project: project)
            if activeProject?.id == projectID {
                activeProject = project
            }
            errorMessage = nil
            return true
        } catch {
            errorMessage =
                "Projektstatus konnte nicht gespeichert werden: "
                + describe(error)
            return false
        }
    }

    @discardableResult
    func deleteProject(_ projectID: UUID) -> Bool {
        let project = projects.first {
            $0.id == projectID
        }
        guard project != nil else {
            errorMessage = "Projekt nicht gefunden."
            return false
        }

        do {
            try projectWorkspaceStore()
                .deleteProject(projectID: projectID)
            try researchDecisionStore()
                .deleteProject(projectID: projectID)
            try growthRecordStore()
                .deleteProject(projectID: projectID)

            let projectKey = projectID.uuidString
            let defaults = UserDefaults.standard
            for key in defaults.dictionaryRepresentation().keys
            where key.contains(projectKey) {
                defaults.removeObject(forKey: key)
            }

            var catalog = Self.loadStoredProjects()
            catalog.removeAll { $0.id == projectID }
            try Self.storeProjects(catalog)

            if activeProject?.id == projectID {
                activeProject = nil
                activeOpportunitySource = nil
                publishingAuthorizedChannelID = nil
                analyticsAuthorizedChannelID = nil
                lastPublishingResult = nil
                latestGrowthLearning = nil
                latestCommentPage = nil
                latestCommentsVideoID = nil
                defaults.removeObject(
                    forKey: "blackstock.activeProject"
                )
                defaults.removeObject(
                    forKey: "blackstock.activeOpportunitySource"
                )
            }

            errorMessage = nil
            return true
        } catch {
            errorMessage =
                "Projekt konnte nicht vollständig gelöscht werden: "
                + describe(error)
            return false
        }
    }

    @discardableResult
    func selectProject(_ projectID: UUID) -> Bool {
        guard let project = projects.first(
            where: { $0.id == projectID }
        ) else {
            errorMessage = "Das ausgewählte Projekt ist nicht mehr im Projektverlauf vorhanden."
            return false
        }

        do {
            try Self.store(project: project)
            activeProject = project
            if let source = Self.loadStoredSource(
                projectID: project.id
            ) ?? loadResearchEvidence(
                projectID: project.id
            )?.source {
                try Self.store(
                    source: source,
                    projectID: project.id
                )
                activeOpportunitySource = source
            } else {
                activeOpportunitySource = nil
                UserDefaults.standard.removeObject(
                    forKey: "blackstock.activeOpportunitySource"
                )
            }
            UserDefaults.standard.set(
                project.targetChannelID,
                forKey: "blackstock.workspace.channelID"
            )
            workspaceRightsResponsibilityAccepted =
                Self.loadStoredWorkspaceRightsAttestation(
                    channelID: project.targetChannelID
                )?.permitsUserDirectedProduction == true
            latestGrowthLearning = loadGrowthLearning(
                projectID: project.id
            )
            latestCommentPage = nil
            latestCommentsVideoID = nil
            lastPublishingResult = nil
            errorMessage = nil
            return true
        } catch {
            errorMessage = "Das Projekt konnte nicht als aktives Projekt geöffnet werden: \(describe(error))"
            return false
        }
    }

    func resetFirstRun() {
        UserDefaults.standard.set(false, forKey: "blackstock.firstRun.complete")
        onboardingComplete = false
        activeProject = nil
        activeOpportunitySource = nil
        UserDefaults.standard.removeObject(forKey: "blackstock.activeProject")
        UserDefaults.standard.removeObject(forKey: "blackstock.activeOpportunitySource")
        UserDefaults.standard.removeObject(forKey: "blackstock.workspace.channelID")
        UserDefaults.standard.removeObject(forKey: "blackstock.workspace.primaryTopic")
        UserDefaults.standard.removeObject(forKey: "blackstock.workspace.contentLanguage")
        UserDefaults.standard.removeObject(
            forKey: "blackstock.workspace.regionCode"
        )
        UserDefaults.standard.removeObject(
            forKey: "blackstock.workspace.channelCategoryID"
        )
        UserDefaults.standard.removeObject(
            forKey: "blackstock.workspace.videoCategoryID"
        )
        UserDefaults.standard.removeObject(
            forKey: "blackstock.workspace.channelAudience"
        )
        UserDefaults.standard.removeObject(
            forKey: "blackstock.workspace.opportunityTimeWindow"
        )
        primaryTopic = ""
        contentLanguage = "de"
        channelRegionCode = ""
        channelCategoryID = ""
        opportunityTimeWindow = .allTime
        channelAudienceSetting = .perVideo
        channelAudienceAppliedToYouTube = nil
        youtubeLanguages = []
        youtubeRegions = []
        youtubeVideoCategories = []
        officialChannelSettingsVerified = false
        step = .welcome
        channels = []
        selectedChannelID = nil
        opportunities = []
        latestCommentPage = nil
        latestCommentsVideoID = nil
        isLoadingComments = false
        errorMessage = nil
    }

    private func storedStrategyVersion(for channelID: String) -> Int {
        guard let data = UserDefaults.standard.data(forKey: "blackstock.strategy.\(channelID)") else { return 1 }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode(ChannelStrategy.self, from: data).version) ?? 1
    }

    private static func loadStoredWorkspaceRightsAttestation(
        channelID: String
    ) -> WorkspaceRightsAttestation? {
        guard let data = UserDefaults.standard.data(
            forKey:
                "blackstock.workspace.rightsAttestation.\(channelID)"
        ) else {
            return nil
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(
            WorkspaceRightsAttestation.self,
            from: data
        )
    }

    private static func store(project: BlackstockProject) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        UserDefaults.standard.set(
            try encoder.encode(project),
            forKey: "blackstock.activeProject"
        )
        try upsertStoredProject(project)
    }

    private static func upsertStoredProject(
        _ project: BlackstockProject
    ) throws {
        var catalog = loadStoredProjects()
        if let index = catalog.firstIndex(
            where: { $0.id == project.id }
        ) {
            catalog[index] = project
        } else {
            catalog.append(project)
        }

        try storeProjects(catalog)
    }

    private static func storeProjects(
        _ projects: [BlackstockProject]
    ) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        UserDefaults.standard.set(
            try encoder.encode(projects),
            forKey: "blackstock.projects"
        )
    }

    private static func loadStoredProjects() -> [BlackstockProject] {
        guard let data = UserDefaults.standard.data(
            forKey: "blackstock.projects"
        ) else {
            return []
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode(
            [BlackstockProject].self,
            from: data
        )) ?? []
    }

    private static func store(
        source: MediaSourceReference,
        projectID: UUID
    ) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(source)
        UserDefaults.standard.set(
            data,
            forKey: "blackstock.activeOpportunitySource"
        )
        UserDefaults.standard.set(
            data,
            forKey: "blackstock.projectSource.\(projectID.uuidString)"
        )
    }

    private static func loadStoredProject() -> BlackstockProject? {
        guard let data = UserDefaults.standard.data(forKey: "blackstock.activeProject") else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(BlackstockProject.self, from: data)
    }

    private static func loadStoredSource() -> MediaSourceReference? {
        guard let data = UserDefaults.standard.data(forKey: "blackstock.activeOpportunitySource") else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(MediaSourceReference.self, from: data)
    }

    private static func loadStoredSource(
        projectID: UUID
    ) -> MediaSourceReference? {
        guard let data = UserDefaults.standard.data(
            forKey: "blackstock.projectSource.\(projectID.uuidString)"
        ) else {
            return nil
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(
            MediaSourceReference.self,
            from: data
        )
    }

    private static func store(
        productionIntent: ProjectProductionIntent
    ) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(productionIntent)
        UserDefaults.standard.set(
            data,
            forKey: "blackstock.projectProductionIntent.\(productionIntent.projectID.uuidString)"
        )
    }

    private static func loadStoredProductionIntent(
        projectID: UUID
    ) -> ProjectProductionIntent? {
        guard let data = UserDefaults.standard.data(
            forKey: "blackstock.projectProductionIntent.\(projectID.uuidString)"
        ) else {
            return nil
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(
            ProjectProductionIntent.self,
            from: data
        )
    }

    private var bundledClientID: String {
        (Bundle.main.object(forInfoDictionaryKey: "BlackstockGoogleOAuthClientID") as? String ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var importedClientID: String {
        importedOAuthClientID
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var importedClientSecret: String {
        BlackstockKeychain.read("google.oauth.importedClientSecret")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var effectiveClientSecret: String? {
        guard !importedClientID.isEmpty else { return nil }
        return importedClientSecret.isEmpty
            ? nil
            : importedClientSecret
    }

    private var effectiveClientID: String {
        OAuthClientConfiguration.preferredClientID(
            bundled: bundledClientID,
            imported: importedClientID
        )
    }

    private func clearOAuthRuntimeAuthorizationState(
        clearChannelSelection: Bool
    ) {
        tokenSet = nil
        tokenExpiresAt = nil
        publishingAuthorizedChannelID = nil
        analyticsAuthorizedChannelID = nil
        lastPublishingResult = nil
        latestCommentPage = nil
        latestCommentsVideoID = nil

        if clearChannelSelection {
            channels = []
            selectedChannelID = nil
        }
    }

    private func validateStoredOAuthClient(for channelID: String) throws {
        let storedClientID = BlackstockKeychain.read(
            "youtube.\(channelID).oauthClientID"
        )
        .trimmingCharacters(in: .whitespacesAndNewlines)

        guard storedClientID.isEmpty || storedClientID == effectiveClientID else {
            throw PublishingSessionError.oauthClientChanged
        }
    }

    private func persist(strategy: ChannelStrategy) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(strategy)
        UserDefaults.standard.set(data, forKey: "blackstock.strategy.\(strategy.channelID)")
    }

    private func nextStrategyVersion(for channelID: String) -> Int {
        guard let data = UserDefaults.standard.data(forKey: "blackstock.strategy.\(channelID)") else { return 1 }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let previous = try? decoder.decode(ChannelStrategy.self, from: data) else { return 1 }
        return previous.version + 1
    }

    private static func providerFacts(
        for opportunity: YouTubeOpportunityCandidate
    ) -> [String] {
        var facts: [String] = [
            "YouTube-Video-ID: \(opportunity.videoID)",
            "Quellkanal: \(opportunity.channelTitle) (\(opportunity.channelID))",
            "Suchraum: \(opportunity.query)",
            "Datenabruf: \(opportunity.retrievedAt.formatted(date: .abbreviated, time: .shortened))"
        ]
        if let publishedAt = opportunity.publishedAt {
            facts.append(
                "Veröffentlicht: \(publishedAt.formatted(date: .abbreviated, time: .shortened))"
            )
        }
        if let value = opportunity.metrics.viewCount {
            facts.append("Views: \(value)")
        }
        if let value = opportunity.metrics.likeCount {
            facts.append("Likes: \(value)")
        }
        if let value = opportunity.metrics.commentCount {
            facts.append("Kommentare: \(value)")
        }
        return facts
    }

    private func describe(_ error: Error) -> String {
        if let localized = error as? LocalizedError, let description = localized.errorDescription {
            return description
        }
        return String(describing: error)
    }
}
#endif
