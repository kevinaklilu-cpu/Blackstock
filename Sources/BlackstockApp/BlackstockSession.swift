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
        }
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
    @Published var contentLanguage = "de"
    @Published var opportunities: [YouTubeOpportunityCandidate] = []
    @Published var isWorking = false
    @Published var errorMessage: String?
    @Published private(set) var onboardingComplete: Bool
    @Published private(set) var activeProject: BlackstockProject?
    @Published private(set) var activeOpportunitySource: MediaSourceReference?
    @Published private(set) var publishingAuthorizedChannelID: String?
    @Published var isAuthorizingPublishing = false

    private var tokenSet: GoogleOAuthTokenSet?
    private var cachedPublishingJournal: ExternalActionJournal?

    init() {
        onboardingComplete = UserDefaults.standard.bool(forKey: "blackstock.firstRun.complete")
        activeProject = Self.loadStoredProject()
        activeOpportunitySource = Self.loadStoredSource()
        primaryTopic = UserDefaults.standard.string(forKey: "blackstock.workspace.primaryTopic") ?? ""
        contentLanguage = UserDefaults.standard.string(forKey: "blackstock.workspace.contentLanguage") ?? "de"
    }

    var selectedChannel: YouTubeChannelIdentity? {
        guard let selectedChannelID else { return nil }
        return channels.first { $0.id == selectedChannelID }
    }

    var oauthConfigurationSource: String {
        if !bundledClientID.isEmpty { return "Blackstock-Konfiguration" }
        if !importedClientID.isEmpty { return "Eigene OAuth-JSON" }
        return "Nicht konfiguriert"
    }

    func importOAuthJSON(from url: URL) {
        do {
            let data = try Data(contentsOf: url)
            let config = try OAuthClientConfiguration.parseGoogleDesktopJSON(data)
            try BlackstockKeychain.write(config.clientID, account: "google.oauth.importedClientID")
            errorMessage = nil
        } catch {
            errorMessage = "OAuth-JSON konnte nicht übernommen werden: \(describe(error))"
        }
    }

    func removeImportedOAuthConfiguration() {
        do {
            try BlackstockKeychain.write("", account: "google.oauth.importedClientID")
            errorMessage = nil
        } catch {
            errorMessage = "OAuth-Konfiguration konnte nicht entfernt werden: \(describe(error))"
        }
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
            }
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
            errorMessage = "Kein aktives Projekt für Publishing vorhanden."
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
                guard identities.contains(where: {
                    $0.id == project.targetChannelID
                }) else {
                    publishingAuthorizedChannelID = nil
                    errorMessage = "Die aktuelle Google-Autorisierung gehört nicht zum Projekt-Zielkanal."
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
                errorMessage = "Google hat keine verifizierbare Scope-Liste zurückgegeben. Blackstock aktiviert Publishing nicht."
                return
            }

            let granted = GoogleOAuthScopePlanner.parseGrantedScopes(
                grantedScopeString
            )
            guard requestedScopes.isSubset(of: granted) else {
                publishingAuthorizedChannelID = nil
                errorMessage = "Nicht alle für Publishing benötigten Google-Berechtigungen wurden gewährt."
                return
            }

            let identities = try await YouTubeAuthorizedClient(
                accessToken: tokens.accessToken
            ).myChannels()
            guard identities.contains(where: {
                $0.id == project.targetChannelID
            }) else {
                publishingAuthorizedChannelID = nil
                errorMessage = "Die neu autorisierte Google-Sitzung enthält nicht den Projekt-Zielkanal. Publishing bleibt gesperrt."
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

            tokenSet = tokens
            publishingAuthorizedChannelID = project.targetChannelID
        } catch {
            publishingAuthorizedChannelID = nil
            errorMessage = "Publishing-Autorisierung fehlgeschlagen: \(describe(error))"
        }
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

        let refreshToken = BlackstockKeychain.read(
            "youtube.\(targetChannelID).refreshToken"
        )
        if !refreshToken.isEmpty {
            let refreshed = try await GoogleOAuthTokenRefresher().refresh(
                refreshToken: refreshToken,
                clientID: effectiveClientID
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
        qualityReview: CreatorQualityReview
    ) throws {
        let snapshot = PublishPreparationSnapshot(
            package: package,
            qualityReview: qualityReview,
            savedAt: Date()
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(snapshot)
        UserDefaults.standard.set(
            data,
            forKey: "blackstock.publish-preparation.\(package.projectID.uuidString)"
        )
    }

    func loadPublishPreparation(
        projectID: UUID
    ) -> PublishPreparationSnapshot? {
        guard let data = UserDefaults.standard.data(
            forKey: "blackstock.publish-preparation.\(projectID.uuidString)"
        ) else {
            return nil
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(
            PublishPreparationSnapshot.self,
            from: data
        )
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
            redirectURI: redirectURI,
            verifier: pkce.verifier
        )
    }

    func continueFromTopic() {
        let value = primaryTopic.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else {
            errorMessage = "Lege zuerst den strategischen Kanal-Schwerpunkt fest."
            return
        }
        primaryTopic = value
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

            let strategy = ChannelStrategy(
                channelID: channel.id,
                primaryTopic: primaryTopic,
                topicDefinition: primaryTopic,
                contentPromise: primaryTopic,
                pillars: [],
                adjacentTopics: [],
                excludedTopics: [],
                defaultContentLanguage: contentLanguage,
                researchLanguages: contentLanguage == "de" ? ["de", "en"] : [contentLanguage],
                audienceHypothesis: "",
                objectives: [.balanced],
                explorationPolicy: .init(),
                effectiveFrom: Date(),
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
        guard let channel = selectedChannel else { return }
        let accessToken = tokenSet?.accessToken ?? BlackstockKeychain.read("youtube.\(channel.id).accessToken")
        guard !accessToken.isEmpty, !primaryTopic.isEmpty else { return }

        isWorking = true
        defer { isWorking = false }

        do {
            let candidates = try await YouTubeAuthorizedClient(accessToken: accessToken)
                .firstOpportunityCandidates(
                    query: primaryTopic,
                    maxResults: 12,
                    order: order
                )
            if !candidates.isEmpty {
                opportunities = candidates
                errorMessage = nil
            }
        } catch {
            errorMessage = "YouTube-Sortierung konnte nicht aktualisiert werden: \(describe(error))"
        }
    }

    func useOpportunity(_ opportunity: YouTubeOpportunityCandidate) {
        guard let channel = selectedChannel else {
            errorMessage = "Kein Zielkanal ausgewählt."
            return
        }

        do {
            let seed = try OpportunityProjectFactory().make(
                opportunity: opportunity,
                targetChannelID: channel.id,
                strategyVersion: storedStrategyVersion(for: channel.id)
            )
            try Self.store(project: seed.project)
            try Self.store(source: seed.source)
            activeProject = seed.project
            activeOpportunitySource = seed.source
            UserDefaults.standard.set(channel.id, forKey: "blackstock.workspace.channelID")
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

    func resetFirstRun() {
        UserDefaults.standard.set(false, forKey: "blackstock.firstRun.complete")
        onboardingComplete = false
        activeProject = nil
        activeOpportunitySource = nil
        UserDefaults.standard.removeObject(forKey: "blackstock.activeProject")
        UserDefaults.standard.removeObject(forKey: "blackstock.activeOpportunitySource")
        UserDefaults.standard.removeObject(forKey: "blackstock.workspace.primaryTopic")
        UserDefaults.standard.removeObject(forKey: "blackstock.workspace.contentLanguage")
        primaryTopic = ""
        contentLanguage = "de"
        step = .welcome
        channels = []
        selectedChannelID = nil
        opportunities = []
        errorMessage = nil
    }

    private func storedStrategyVersion(for channelID: String) -> Int {
        guard let data = UserDefaults.standard.data(forKey: "blackstock.strategy.\(channelID)") else { return 1 }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode(ChannelStrategy.self, from: data).version) ?? 1
    }

    private static func store(project: BlackstockProject) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        UserDefaults.standard.set(try encoder.encode(project), forKey: "blackstock.activeProject")
    }

    private static func store(source: MediaSourceReference) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        UserDefaults.standard.set(try encoder.encode(source), forKey: "blackstock.activeOpportunitySource")
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

    private var bundledClientID: String {
        (Bundle.main.object(forInfoDictionaryKey: "BlackstockGoogleOAuthClientID") as? String ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var importedClientID: String {
        BlackstockKeychain.read("google.oauth.importedClientID")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var effectiveClientID: String {
        bundledClientID.isEmpty ? importedClientID : bundledClientID
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

    private func describe(_ error: Error) -> String {
        if let localized = error as? LocalizedError, let description = localized.errorDescription {
            return description
        }
        return String(describing: error)
    }
}
#endif
