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
    private static let importedOAuthClientIDDefaultsKey =
        "blackstock.google.oauth.importedClientID"
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
        OpportunityTimeWindow = .last7Days
    @Published var opportunityContentFilter: OpportunityContentFilter = .all
    @Published var channelAudienceSetting:
        YouTubeChannelAudienceSetting = .perVideo
    @Published var isLoadingYouTubeSetupOptions = false
    @Published private(set) var officialChannelSettingsVerified = false
    @Published private(set) var channelAudienceAppliedToYouTube: Bool?
    @Published var opportunities: [YouTubeOpportunityCandidate] = []
    @Published var opportunityRecommendationNote = ""
    @Published var isWorking = false
    @Published var errorMessage: String?
    @Published var showGoogleConnection = false
    @Published var connectionStatusMessage: String?
    @Published private(set) var activeStorySources: [YouTubeOpportunityCandidate] = []
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

    private var googleConnectionServer: LoopbackOAuthServer?
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
        let defaultsClientID = UserDefaults.standard.string(
            forKey: Self.importedOAuthClientIDDefaultsKey
        )?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let keychainClientID = BlackstockKeychain.read(
            "google.oauth.importedClientID"
        ).trimmingCharacters(in: .whitespacesAndNewlines)
        importedOAuthClientID = keychainClientID.isEmpty
            ? defaultsClientID
            : keychainClientID
        if !keychainClientID.isEmpty {
            UserDefaults.standard.set(
                keychainClientID,
                forKey: Self.importedOAuthClientIDDefaultsKey
            )
        }
        originalMediaLibraryPath = UserDefaults.standard.string(
            forKey: "blackstock.originalMediaLibraryPath"
        ) ?? ""
        onboardingComplete = UserDefaults.standard.bool(forKey: "blackstock.firstRun.complete")
        workspaceRightsResponsibilityAccepted = false
        activeProject = Self.loadStoredProject()
        activeOpportunitySource = Self.loadStoredSource()
        if let projectID = activeProject?.id,
           let data = UserDefaults.standard.data(
                forKey: "blackstock.storySources.\(projectID.uuidString)"
           ),
           let sources = try? JSONDecoder().decode(
                [YouTubeOpportunityCandidate].self,
                from: data
           ) {
            activeStorySources = sources
        }
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
        SourceDownloadManager.youtubeExecutable != nil || (
            approvedSourceProviderAuthorization?.mayIngestYouTubeLinks == true
            && approvedSourceProviderEndpointURL != nil
        )
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
            if BlackstockKeychain.hasBlockedReads {
                BlackstockKeychain.startFreshCredentialStore()
                clearOAuthRuntimeAuthorizationState(clearChannelSelection: true)
            }
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
            UserDefaults.standard.set(
                config.clientID,
                forKey: Self.importedOAuthClientIDDefaultsKey
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
            UserDefaults.standard.removeObject(
                forKey: Self.importedOAuthClientIDDefaultsKey
            )
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

    func retryKeychainAccess() async {
        connectionStatusMessage = "Gespeicherte Anmeldung wird geprüft …"
        showGoogleConnection = true
        BlackstockKeychain.retryBlockedReads()
        let storedClientID = BlackstockKeychain.read(
            "google.oauth.importedClientID"
        ).trimmingCharacters(in: .whitespacesAndNewlines)
        if !storedClientID.isEmpty {
            importedOAuthClientID = storedClientID
            UserDefaults.standard.set(
                storedClientID,
                forKey: Self.importedOAuthClientIDDefaultsKey
            )
        }
        if BlackstockKeychain.hasBlockedReads {
            connectionStatusMessage = "macOS lehnt die gespeicherte Anmeldung weiterhin ab. Melde dich erneut mit Google an."
            return
        }
        guard workspaceChannelID != nil else {
            connectionStatusMessage = "Melde dich mit Google an und wähle anschließend deinen YouTube-Kanal."
            return
        }
        errorMessage = nil
        await refreshWorkspaceChannelIdentity()
        connectionStatusMessage = errorMessage ?? "Die gespeicherte Kanalverbindung ist wieder verfügbar."
    }

    func useConnectedChannel(_ id: String) async {
        await chooseChannel(id)
        guard errorMessage == nil, selectedChannelID == id else { return }
        if onboardingComplete {
            if activeProject?.targetChannelID != id {
                activeProject = nil
                activeOpportunitySource = nil
                UserDefaults.standard.removeObject(forKey: "blackstock.activeProject")
                UserDefaults.standard.removeObject(forKey: "blackstock.activeOpportunitySource")
            }
            UserDefaults.standard.set(id, forKey: "blackstock.workspace.channelID")
            opportunities = []
            latestChannelAnalytics = nil
        }
        connectionStatusMessage = "Verbunden mit " + (selectedChannel?.title ?? "YouTube")
        showGoogleConnection = false
    }

    func cancelGoogleConnection() {
        googleConnectionServer?.cancel()
    }

    func connectGoogle() async {
        guard !isWorking else { return }
        errorMessage = nil
        connectionStatusMessage = nil
        if BlackstockKeychain.hasBlockedReads {
            let clientID = effectiveClientID
            let secret = effectiveClientSecret
            BlackstockKeychain.startFreshCredentialStore()
            clearOAuthRuntimeAuthorizationState(clearChannelSelection: true)
            do {
                if !clientID.isEmpty {
                    try BlackstockKeychain.write(clientID, account: "google.oauth.importedClientID")
                    importedOAuthClientID = clientID
                }
                if let secret { try BlackstockKeychain.write(secret, account: "google.oauth.importedClientSecret") }
            } catch {
                errorMessage = "Neue Anmeldung konnte nicht vorbereitet werden: " + describe(error)
                return
            }
        }
        guard !effectiveClientID.isEmpty else {
            errorMessage = "Keine Google-OAuth-Konfiguration verfügbar. Verwende die integrierte Blackstock-Konfiguration oder importiere eine Desktop-OAuth-JSON."
            return
        }

        isWorking = true
        defer { isWorking = false }
        channels = []
        selectedChannelID = nil

        do {
            let server = try LoopbackOAuthServer()
            googleConnectionServer = server
            defer {
                server.cancel()
                googleConnectionServer = nil
            }
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

            connectionStatusMessage = "Schließe die Anmeldung im Google-Fenster ab."
            let callbackURL = try await server.waitForCallback()
            connectionStatusMessage = "Deine YouTube-Kanäle werden geladen …"
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
            connectionStatusMessage = "Wähle jetzt deinen YouTube-Kanal."
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
            if analyticsScopePlan()?.state == .alreadyAuthorized {
                analyticsAuthorizedChannelID = channelID
            }
        } catch {
            if let urlError = error as? URLError,
               urlError.code == .cancelled {
                return
            }
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
            if let snapshot = try store.loadPublishPreparation(
                projectID: projectID
            ) {
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

    @Published var isLoadingOpportunities = false
    @Published var opportunityNextPageToken: String?
    private var opportunityRequestID = UUID()
    private var opportunityRequestKey: [String] = []
    private var opportunitySearchDate = Date()

    func loadWorkspaceOpportunities(
        query: String,
        order: OpportunitySortMode,
        timeWindow: OpportunityTimeWindow? = nil,
        contentFilter: OpportunityContentFilter? = nil,
        loadMore: Bool = false
    ) async {
        let resolvedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let window = timeWindow ?? opportunityTimeWindow
        let filter = contentFilter ?? opportunityContentFilter
        // Capture every input before the first suspension. Earlier requests must
        // never overwrite a more recently selected country, query, or sort.
        let category = channelCategoryID
        let region = channelRegionCode
        let language = contentLanguage
        let key = [resolvedQuery, order.rawValue, window.rawValue, filter.rawValue,
                   category, region, language, workspaceChannelID ?? ""]
        let token: String?
        let existingOpportunities: [YouTubeOpportunityCandidate]
        if loadMore {
            guard !isLoadingOpportunities, key == opportunityRequestKey,
                  let next = opportunityNextPageToken else { return }
            token = next
            existingOpportunities = opportunities
        } else {
            token = nil
            opportunitySearchDate = Date()
            // Keep the previous result visible while YouTube answers. Replacing
            // it up front makes a slow or failed search look like a dead UI.
            existingOpportunities = []
            opportunityNextPageToken = nil
        }
        let requestID = UUID()
        opportunityRequestID = requestID
        opportunityRequestKey = key
        opportunityContentFilter = filter
        let defaults = UserDefaults.standard
        defaults.set(filter.rawValue, forKey: "blackstock.workspace.opportunityContentFilter")
        defaults.set(window.rawValue, forKey: "blackstock.workspace.opportunityTimeWindow")
        defaults.set(category, forKey: "blackstock.workspace.channelCategoryID")
        defaults.set(region, forKey: "blackstock.workspace.regionCode")
        defaults.set(language, forKey: "blackstock.workspace.contentLanguage")
        defaults.set(primaryTopic, forKey: "blackstock.workspace.primaryTopic")
        guard let channelID = selectedChannelID ?? workspaceChannelID else {
            errorMessage = "Kein YouTube-Kanal ist verbunden."
            return
        }
        isLoadingOpportunities = true
        errorMessage = nil
        defer {
            if opportunityRequestID == requestID { isLoadingOpportunities = false }
        }
        do {
            let accessToken = try await validatedReadOnlyAccessToken(targetChannelID: channelID)
            guard opportunityRequestID == requestID else { return }
            let client = YouTubeAuthorizedClient(accessToken: accessToken)
            // Shorts/video classification needs video details. A search page
            // can therefore become empty only after enrichment although a
            // following page contains valid matches. Scan ahead before
            // declaring a valid time/filter combination empty.
            func matchingPage(
                searchQuery: String = resolvedQuery,
                categoryID: String?,
                regionCode: String?,
                relevanceLanguage: String?,
                initialToken: String? = nil
            ) async throws -> YouTubeOpportunityPage {
                var candidates: [YouTubeOpportunityCandidate] = []
                var nextToken = initialToken
                var returnedNextToken: String?
                // YouTube search requests are quota-heavy. Automatic feeds
                // use the inexpensive popularity chart first; a typed/topic
                // query may scan one additional page only when necessary.
                let pageLimit = loadMore || searchQuery.isEmpty ? 1 : 2
                for _ in 0..<pageLimit {
                    let part = try await client.opportunityPage(
                        query: searchQuery,
                        categoryID: categoryID,
                        regionCode: regionCode,
                        relevanceLanguage: relevanceLanguage,
                        publishedAfter: window.publishedAfter(
                            now: opportunitySearchDate
                        ),
                        maxResults: 50,
                        order: order,
                        contentFilter: filter,
                        pageToken: nextToken
                    )
                    candidates.append(contentsOf: part.candidates)
                    returnedNextToken = part.nextPageToken
                    guard candidates.isEmpty,
                          let following = part.nextPageToken,
                          following != nextToken else { break }
                    nextToken = following
                }
                return YouTubeOpportunityPage(
                    candidates: candidates,
                    nextPageToken: returnedNextToken
                )
            }

            func filteredPopularChart(
                categoryID: String
            ) async throws -> [YouTubeOpportunityCandidate] {
                guard !region.isEmpty else { return [] }
                let cutoff = window.publishedAfter(
                    now: opportunitySearchDate
                )
                return try await client
                    .mostPopularOpportunityCandidates(
                        categoryID: categoryID,
                        regionCode: region,
                        maxResults: 50,
                        now: opportunitySearchDate
                    )
                    .filter { candidate in
                        let insideWindow = cutoff.map {
                            (candidate.publishedAt ?? .distantPast) >= $0
                        } ?? true
                        let matchesFormat: Bool
                        switch filter {
                        case .all:
                            matchesFormat = true
                        case .shorts:
                            matchesFormat = candidate.contentKind == .short
                        case .videos:
                            matchesFormat = candidate.contentKind == .video
                        case .live:
                            matchesFormat = candidate.contentKind == .live
                        }
                        return insideWindow && matchesFormat
                    }
            }

            var recommendationNote = ""
            var page: YouTubeOpportunityPage
            let initialChart = !loadMore && resolvedQuery.isEmpty
                ? try await filteredPopularChart(categoryID: category)
                : []
            if !initialChart.isEmpty {
                page = YouTubeOpportunityPage(
                    candidates: YouTubeAuthorizedClient.sortedOpportunities(
                        initialChart,
                        order: order
                    ),
                    nextPageToken: nil
                )
                recommendationNote = language.isEmpty
                    ? "Aktuelle YouTube-Trends für Kategorie und Region. Zeitraum und Format wurden exakt angewendet."
                    : "Aktuelle YouTube-Trends für Kategorie und Region. Zeitraum und Format gelten exakt; die Sprachwahl wurde für mehr passende Treffer erweitert."
            } else {
                page = try await matchingPage(
                    // A typed query expresses the user's intent and must not
                    // be restricted to the saved channel category.
                    categoryID: resolvedQuery.isEmpty
                        ? (category.isEmpty ? nil : category)
                        : nil,
                    regionCode: region.isEmpty ? nil : region,
                    relevanceLanguage: language.isEmpty ? nil : language,
                    initialToken: token
                )
            }
            // An empty search field means automatic recommendations. Narrow
            // time/category combinations can legitimately return no search
            // rows, so fall back to YouTube's regional popularity chart.
            if !loadMore, resolvedQuery.isEmpty, page.candidates.isEmpty,
               !category.isEmpty {
                page = try await matchingPage(
                    categoryID: nil,
                    regionCode: region.isEmpty ? nil : region,
                    relevanceLanguage: language.isEmpty ? nil : language
                )
                if !page.candidates.isEmpty {
                    recommendationNote =
                        "Im gewählten Zeitraum gab es in der Kategorie zu wenige Treffer. Die Kategorie wurde erweitert; Zeitraum, Region und Format bleiben strikt aktiv."
                }
            }
            if !loadMore, resolvedQuery.isEmpty, page.candidates.isEmpty,
               !language.isEmpty {
                page = try await matchingPage(
                    categoryID: nil,
                    regionCode: region.isEmpty ? nil : region,
                    relevanceLanguage: nil
                )
                if !page.candidates.isEmpty {
                    recommendationNote =
                        "Für Sprache und Kategorie gab es zu wenige Treffer. Sprache und Kategorie wurden erweitert; Zeitraum, Region und Format bleiben strikt aktiv."
                }
            }
            if !loadMore, resolvedQuery.isEmpty, page.candidates.isEmpty,
               !region.isEmpty {
                page = try await matchingPage(
                    categoryID: nil,
                    regionCode: nil,
                    relevanceLanguage: nil
                )
                if !page.candidates.isEmpty {
                    recommendationNote =
                        "Für die enge Auswahl gab es zu wenige Treffer. Kategorie, Sprache und Region wurden erweitert; Zeitraum und Format bleiben strikt aktiv."
                }
            }
            // Some YouTube accounts/regions return an empty category-only
            // search even though normal keyword search has current results.
            // Use the official category title as an automatic query while
            // keeping the chosen time window and format strict.
            if !loadMore, resolvedQuery.isEmpty, page.candidates.isEmpty {
                let categoryTitle = youtubeVideoCategories.first(
                    where: { $0.id == category }
                )?.title.trimmingCharacters(in: .whitespacesAndNewlines)
                let automaticTopic = (categoryTitle?.isEmpty == false
                    ? categoryTitle
                    : primaryTopic.trimmingCharacters(
                        in: .whitespacesAndNewlines
                    )) ?? ""
                if !automaticTopic.isEmpty {
                    page = try await matchingPage(
                        searchQuery: automaticTopic,
                        categoryID: nil,
                        regionCode: region.isEmpty ? nil : region,
                        relevanceLanguage: language.isEmpty ? nil : language
                    )
                    if !page.candidates.isEmpty {
                        recommendationNote =
                            "Blackstock nutzt die gewählte Kategorie als automatisches Thema. Zeitraum, Region und Format bleiben aktiv."
                    }
                }
            }
            // The videos.list popularity chart is more dependable than an
            // empty search feed and still comes from YouTube. Filter its rows
            // locally so the selected time window and format remain true.
            if !loadMore, resolvedQuery.isEmpty, page.candidates.isEmpty,
               !region.isEmpty {
                var chart = try await filteredPopularChart(
                    categoryID: category
                )
                if chart.isEmpty, !category.isEmpty {
                    chart = try await filteredPopularChart(categoryID: "")
                }
                if !chart.isEmpty {
                    page = YouTubeOpportunityPage(
                        candidates: YouTubeAuthorizedClient
                            .sortedOpportunities(chart, order: order),
                        nextPageToken: nil
                    )
                    recommendationNote =
                        "Aktuelle YouTube-Trends für die gewählte Region. Zeitraum und Format wurden exakt angewendet."
                }
            }
            guard opportunityRequestID == requestID,
                  channelCategoryID == category, channelRegionCode == region,
                  contentLanguage == language,
                  (selectedChannelID ?? workspaceChannelID) == channelID else { return }
            opportunityRecommendationNote = recommendationNote
            var seen = Set(existingOpportunities.map(\.videoID))
            let added = page.candidates.filter { seen.insert($0.videoID).inserted }
            opportunities = YouTubeAuthorizedClient.sortedOpportunities(
                existingOpportunities + added,
                order: order
            )
            opportunityNextPageToken = page.nextPageToken == token ? nil : page.nextPageToken
            if opportunities.isEmpty {
                errorMessage = opportunityNextPageToken == nil
                    ? "Keine passenden Videos gefunden. Erweitere Zeitraum oder Format oder ändere den Suchbegriff."
                    : "Auf dieser Ergebnisseite passt noch kein Video zum Format. Mit ‚Mehr laden‘ weitere Treffer prüfen."
            }
        } catch {
            guard opportunityRequestID == requestID else { return }
            opportunityRecommendationNote = ""
            errorMessage = "Videos konnten nicht geladen werden: \(describe(error))"
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

    @discardableResult
    func useMultiSourceStory(
        _ sources: [YouTubeOpportunityCandidate]
    ) -> Bool {
        let unique = sources.reduce(into: [YouTubeOpportunityCandidate]()) {
            result, source in
            if !result.contains(where: { $0.videoID == source.videoID }) {
                result.append(source)
            }
        }
        guard unique.count >= 2 else {
            errorMessage = "Wähle mindestens zwei Videos für eine Mehrquellen-Story aus."
            return false
        }
        guard workspaceRightsResponsibilityAccepted else {
            errorMessage =
                "Bestätige die Nutzungsrechte, bevor du eine Mehrquellen-Story erstellst."
            return false
        }
        let selected = Array(unique.prefix(5))
        useOpportunity(selected[0], productionIntentKind: .clipFromOpportunity)
        guard let projectID = activeProject?.id else {
            if errorMessage == nil {
                errorMessage = "Die Mehrquellen-Story konnte nicht angelegt werden."
            }
            return false
        }
        activeStorySources = selected
        if let data = try? JSONEncoder().encode(selected) {
            UserDefaults.standard.set(
                data,
                forKey: "blackstock.storySources.\(projectID.uuidString)"
            )
        }
        errorMessage = nil
        return true
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
            activeStorySources = []
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
        guard selectedChannel != nil else {
            errorMessage = "Wähle zuerst deinen YouTube-Kanal."
            return
        }
        guard workspaceRightsResponsibilityAccepted else {
            errorMessage = "Bestätige zuerst die Nutzungsrechte für deinen Arbeitsbereich."
            return
        }
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
        opportunityTimeWindow = .last7Days
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
