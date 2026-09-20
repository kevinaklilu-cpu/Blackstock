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
    @Published var isLoadingComments = false
    @Published private(set) var latestCommentPage: YouTubeCommentThreadPage?
    @Published private(set) var latestCommentsVideoID: String?
    @Published private(set) var importedOAuthClientID: String
    @Published private(set) var workspaceRightsResponsibilityAccepted: Bool

    private var tokenSet: GoogleOAuthTokenSet?
    private var cachedPublishingJournal: ExternalActionJournal?

    init() {
        BlackstockUpdateAudit.reconcilePostUpdateLaunch()
        BlackstockCaptureHardwareAudit.reconcilePostRestart()
        _ = try? PrivacyRetentionEnforcer().purgeExpiredUpdatePackages(
            in: FileManager.default.temporaryDirectory
        )
        importedOAuthClientID = BlackstockKeychain.read("google.oauth.importedClientID")
            .trimmingCharacters(in: .whitespacesAndNewlines)
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
        primaryTopic = UserDefaults.standard.string(forKey: "blackstock.workspace.primaryTopic") ?? ""
        contentLanguage = UserDefaults.standard.string(forKey: "blackstock.workspace.contentLanguage") ?? "de"
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
        onboardingComplete = !failures.isEmpty
        activeProject = nil
        activeOpportunitySource = nil
        publishingAuthorizedChannelID = nil
        analyticsAuthorizedChannelID = nil
        lastPublishingResult = nil
        latestGrowthLearning = nil
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
                scopes: [.youtubeReadOnly],
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

            tokenSet = tokens
            channels = identities
            selectedChannelID = nil
            step = .channel
        } catch {
            errorMessage = "Google-Verbindung fehlgeschlagen: \(describe(error))"
        }
    }

    func chooseChannel(_ id: String) {
        guard channels.contains(where: { $0.id == id }) else { return }
        selectedChannelID = id
        do {
            if let tokenSet {
                try BlackstockKeychain.write(tokenSet.accessToken, account: "youtube.\(id).accessToken")
                if let refresh = tokenSet.refreshToken, !refresh.isEmpty {
                    try BlackstockKeychain.write(refresh, account: "youtube.\(id).refreshToken")
                }
                if let scope = tokenSet.scope {
                    try BlackstockKeychain.write(scope, account: "youtube.\(id).scopes")
                }
                try BlackstockKeychain.write(
                    effectiveClientID,
                    account: "youtube.\(id).oauthClientID"
                )
            }
            workspaceRightsResponsibilityAccepted =
                Self.loadStoredWorkspaceRightsAttestation(
                    channelID: id
                )?.permitsUserDirectedProduction == true
            step = .topic
            errorMessage = nil
        } catch {
            errorMessage = "Die autorisierte Sitzung konnte nicht sicher gespeichert werden: \(describe(error))"
        }
    }

    var workspaceChannelID: String? {
        activeProject?.targetChannelID
            ?? UserDefaults.standard.string(
                forKey: "blackstock.workspace.channelID"
            )
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
                "Wähle zuerst den YouTube-Arbeitsbereich."
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

            tokenSet = tokens
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
        guard let authorizedChannelID = publishingAuthorizedChannelID,
              authorizedChannelID == project.targetChannelID else {
            errorMessage = "Die Veröffentlichung ist für den Projekt-Zielkanal noch nicht verifiziert."
            return
        }
        guard let workspaceChannelID,
              workspaceChannelID == project.targetChannelID else {
            errorMessage = "Arbeitsbereich- und Projekt-Zielkanal stimmen nicht überein."
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
        guard let project = activeProject else {
            errorMessage = "Kein aktives Projekt für Analytics vorhanden."
            return
        }
        guard !effectiveClientID.isEmpty else {
            errorMessage = "Keine Google-OAuth-Konfiguration verfügbar."
            return
        }

        isAuthorizingAnalytics = true
        defer { isAuthorizingAnalytics = false }
        errorMessage = nil

        do {
            let currentPlan = analyticsScopePlan()
            if currentPlan?.state == .alreadyAuthorized {
                let accessToken = try await validatedAnalyticsAccessToken(
                    targetChannelID: project.targetChannelID
                )
                let identities = try await YouTubeAuthorizedClient(
                    accessToken: accessToken
                ).myChannels()
                guard identities.contains(where: {
                    $0.id == project.targetChannelID
                }) else {
                    analyticsAuthorizedChannelID = nil
                    errorMessage = "Die Analytics-Autorisierung gehört nicht zum Projekt-Zielkanal."
                    return
                }
                analyticsAuthorizedChannelID = project.targetChannelID
                return
            }

            let requestedScopes = currentPlan?.scopesForAuthorization
                ?? Set([
                    GoogleOAuthScope.youtubeReadOnly,
                    .analyticsReadOnly
                ])

            let tokens = try await performOAuthAuthorization(
                scopes: requestedScopes
            )

            guard let grantedScopeString = tokens.scope else {
                analyticsAuthorizedChannelID = nil
                errorMessage = "Google hat keine verifizierbare Scope-Liste zurückgegeben. Analytics bleibt gesperrt."
                return
            }

            let granted = GoogleOAuthScopePlanner.parseGrantedScopes(
                grantedScopeString
            )
            guard requestedScopes.isSubset(of: granted) else {
                analyticsAuthorizedChannelID = nil
                errorMessage = "Nicht alle für Analytics benötigten Google-Berechtigungen wurden gewährt."
                return
            }

            let identities = try await YouTubeAuthorizedClient(
                accessToken: tokens.accessToken
            ).myChannels()
            guard identities.contains(where: {
                $0.id == project.targetChannelID
            }) else {
                analyticsAuthorizedChannelID = nil
                errorMessage = "Die Analytics-Sitzung enthält nicht den Projekt-Zielkanal."
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

            tokenSet = tokens
            analyticsAuthorizedChannelID = project.targetChannelID
        } catch {
            analyticsAuthorizedChannelID = nil
            errorMessage = "Analytics-Autorisierung fehlgeschlagen: \(describe(error))"
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

    func validatedReadOnlyAccessToken(
        targetChannelID: String
    ) async throws -> String {
        let storedScopes = BlackstockKeychain.read(
            "youtube.\(targetChannelID).scopes"
        )
        let plan = GoogleOAuthScopePlanner().plan(
            capabilities: [.discoveryReadOnly],
            tokenScopeString: storedScopes
        )
        guard plan.state == .alreadyAuthorized else {
            throw PublishingSessionError.missingScopes
        }
        try validateStoredOAuthClient(for: targetChannelID)

        let refreshToken = BlackstockKeychain.read(
            "youtube.\(targetChannelID).refreshToken"
        )
        if !refreshToken.isEmpty {
            let refreshed = try await GoogleOAuthTokenRefresher().refresh(
                refreshToken: refreshToken,
                clientID: effectiveClientID,
                clientSecret: effectiveClientSecret
            )
            try BlackstockKeychain.write(
                refreshed.accessToken,
                account: "youtube.\(targetChannelID).accessToken"
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
        let plan = GoogleOAuthScopePlanner().plan(
            capabilities: [.discoveryReadOnly, .analytics],
            tokenScopeString: storedScopes
        )
        guard plan.state == .alreadyAuthorized else {
            throw PublishingSessionError.missingScopes
        }
        try validateStoredOAuthClient(for: targetChannelID)

        let refreshToken = BlackstockKeychain.read(
            "youtube.\(targetChannelID).refreshToken"
        )
        if !refreshToken.isEmpty {
            let refreshed = try await GoogleOAuthTokenRefresher().refresh(
                refreshToken: refreshToken,
                clientID: effectiveClientID,
                clientSecret: effectiveClientSecret
            )
            try BlackstockKeychain.write(
                refreshed.accessToken,
                account: "youtube.\(targetChannelID).accessToken"
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
        let plan = GoogleOAuthScopePlanner().plan(
            capabilities: [.discoveryReadOnly, .upload, .packaging],
            tokenScopeString: storedScopes
        )
        guard plan.state == .alreadyAuthorized else {
            throw PublishingSessionError.missingScopes
        }
        try validateStoredOAuthClient(for: targetChannelID)

        let refreshToken = BlackstockKeychain.read(
            "youtube.\(targetChannelID).refreshToken"
        )
        if !refreshToken.isEmpty {
            let refreshed = try await GoogleOAuthTokenRefresher().refresh(
                refreshToken: refreshToken,
                clientID: effectiveClientID,
                clientSecret: effectiveClientSecret
            )
            try BlackstockKeychain.write(
                refreshed.accessToken,
                account: "youtube.\(targetChannelID).accessToken"
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

    func continueFromTopic() {
        let value = primaryTopic.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else {
            errorMessage = "Gib zuerst ein Kanalthema ein."
            return
        }

        let audience = strategyAudienceHypothesis
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !audience.isEmpty else {
            errorMessage = "Gib zuerst deine Zielgruppe ein."
            return
        }

        primaryTopic = value

        if strategyContentPromise
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .isEmpty {
            strategyContentPromise = value
        }

        if ChannelStrategyDraft.list(from: strategyPillarsText).isEmpty {
            strategyPillarsText = value
        }

        errorMessage = nil
        step = .language
    }

    func prepareChannelAndLoadOpportunities() async {
        guard let channel = selectedChannel else {
            errorMessage = "Kein Zielkanal ausgewählt."
            return
        }
        guard !primaryTopic.isEmpty else {
            errorMessage = "Kein Kanalthema festgelegt."
            return
        }

        step = .preparing
        isWorking = true
        errorMessage = nil
        opportunities = []
        defer { isWorking = false }

        do {
            let accessToken = tokenSet?.accessToken ?? BlackstockKeychain.read("youtube.\(channel.id).accessToken")
            guard !accessToken.isEmpty else {
                errorMessage = "Die Google-Autorisierung ist nicht mehr verfügbar. Verbinde den Kanal erneut."
                step = .welcome
                return
            }

            let strategy = try ChannelStrategyDraft(
                primaryTopic: primaryTopic,
                contentPromise: strategyContentPromise,
                audienceHypothesis: strategyAudienceHypothesis,
                pillarsText: strategyPillarsText,
                adjacentTopicsText: strategyAdjacentTopicsText,
                excludedTopicsText: strategyExcludedTopicsText,
                objective: strategyObjective
            ).makeStrategy(
                channelID: channel.id,
                contentLanguage: contentLanguage,
                version: nextStrategyVersion(for: channel.id)
            )
            try persist(strategy: strategy)

            let candidates = try await YouTubeAuthorizedClient(accessToken: accessToken)
                .firstOpportunityCandidates(query: primaryTopic, maxResults: 12, order: .relevance)
            guard !candidates.isEmpty else {
                errorMessage = "YouTube hat für diesen strategischen Suchraum aktuell keine Opportunity-Kandidaten geliefert."
                return
            }

            opportunities = candidates
            step = .opportunities
        } catch {
            errorMessage = "Die ersten Chancen konnten nicht aus realen YouTube-Daten erstellt werden: \(describe(error))"
        }
    }

    func reloadOpportunities(order: OpportunitySortMode) async {
        await loadWorkspaceOpportunities(
            query: primaryTopic,
            order: order
        )
    }

    func loadWorkspaceOpportunities(
        query: String,
        order: OpportunitySortMode
    ) async {
        let resolvedQuery = query.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard !resolvedQuery.isEmpty else {
            errorMessage = "Gib zuerst einen konkreten Suchraum für neue Chancen ein."
            return
        }
        guard let channelID = workspaceChannelID else {
            errorMessage = "Kein YouTube-Arbeitsbereich ist verbunden."
            return
        }

        let accessToken =
            tokenSet?.accessToken
            ?? BlackstockKeychain.read(
                "youtube.\(channelID).accessToken"
            )
        guard !accessToken.isEmpty else {
            errorMessage = "Die Google-Autorisierung für den Arbeitsbereich ist nicht mehr verfügbar."
            return
        }

        isWorking = true
        errorMessage = nil
        defer { isWorking = false }

        do {
            let candidates = try await YouTubeAuthorizedClient(
                accessToken: accessToken
            ).firstOpportunityCandidates(
                query: resolvedQuery,
                maxResults: 20,
                order: order
            )
            opportunities = candidates
            if candidates.isEmpty {
                errorMessage = "YouTube hat für diesen Suchraum aktuell keine passenden Videos geliefert."
            }
        } catch {
            errorMessage = "Neue Chancen konnten nicht aus realen YouTube-Daten geladen werden: \(describe(error))"
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
                "Bestätige einmalig die Nutzungsverantwortung für diesen Arbeitsbereich, bevor du ein Video als Clip-Projekt übernimmst."
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
                strategyVersion: storedStrategyVersion(for: channelID)
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
                    createdAt: Date()
                )
            )
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
            activeProject = seed.project
            activeOpportunitySource = seed.source
            lastPublishingResult = nil
            latestGrowthLearning = nil
            latestCommentPage = nil
            latestCommentsVideoID = nil
            UserDefaults.standard.set(channelID, forKey: "blackstock.workspace.channelID")
            UserDefaults.standard.set(primaryTopic, forKey: "blackstock.workspace.primaryTopic")
            UserDefaults.standard.set(contentLanguage, forKey: "blackstock.workspace.contentLanguage")
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
            errorMessage = "Recherche benötigt eine konkrete Frage, Provider-Fakten und eigene Notizen."
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
            errorMessage = "Opportunity wurde bewusst verworfen. Das Projekt bleibt in der Analyse und wechselt nicht in Produktion."
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
        primaryTopic = ""
        contentLanguage = "de"
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

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        UserDefaults.standard.set(
            try encoder.encode(catalog),
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

    private var bundledClientSecret: String {
        (Bundle.main.object(
            forInfoDictionaryKey: "BlackstockGoogleOAuthClientSecret"
        ) as? String ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var importedClientSecret: String {
        BlackstockKeychain.read("google.oauth.importedClientSecret")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var effectiveClientSecret: String? {
        let value = importedClientID.isEmpty
            ? bundledClientSecret
            : importedClientSecret
        return value.isEmpty ? nil : value
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
