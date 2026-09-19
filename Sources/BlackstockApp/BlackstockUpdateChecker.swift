#if os(macOS)
import Foundation
import BlackstockCore

enum BlackstockUpdateCheckResult: Sendable, Equatable {
    case notConfigured
    case upToDate
    case updateAvailable(BlackstockUpdateManifest)
}

enum BlackstockUpdateCheckError: Error, LocalizedError {
    case invalidManifestURL
    case manifestURLMustUseHTTPS
    case invalidHTTPStatus(Int)
    case missingPublicKey
    case missingInstallerTeamID
    case invalidCurrentBuild

    var errorDescription: String? {
        switch self {
        case .invalidManifestURL:
            return "Die konfigurierte Update-Manifest-URL ist ungültig."
        case .manifestURLMustUseHTTPS:
            return "Das Update-Manifest muss über HTTPS geladen werden."
        case .invalidHTTPStatus(let status):
            return "Der Update-Server antwortete mit HTTP \(status)."
        case .missingPublicKey:
            return "Für Update-Prüfungen ist kein öffentlicher Signaturschlüssel konfiguriert."
        case .missingInstallerTeamID:
            return "Für Update-Prüfungen ist keine erwartete Developer-ID-Installer-Team-ID konfiguriert."
        case .invalidCurrentBuild:
            return "Die installierte Build-Nummer konnte nicht gelesen werden."
        }
    }
}

struct BlackstockUpdateChecker: Sendable {
    func check(
        bundle: Bundle = .main,
        session: URLSession = .shared
    ) async throws -> BlackstockUpdateCheckResult {
        let rawURL = (
            bundle.object(
                forInfoDictionaryKey: "BlackstockUpdateManifestURL"
            ) as? String ?? ""
        ).trimmingCharacters(in: .whitespacesAndNewlines)
        let publicKey = (
            bundle.object(
                forInfoDictionaryKey: "BlackstockUpdatePublicKeyBase64"
            ) as? String ?? ""
        ).trimmingCharacters(in: .whitespacesAndNewlines)
        let installerTeamID = (
            bundle.object(
                forInfoDictionaryKey: "BlackstockUpdateInstallerTeamID"
            ) as? String ?? ""
        ).trimmingCharacters(in: .whitespacesAndNewlines)

        if rawURL.isEmpty && publicKey.isEmpty && installerTeamID.isEmpty {
            return .notConfigured
        }
        guard let manifestURL = URL(string: rawURL) else {
            throw BlackstockUpdateCheckError.invalidManifestURL
        }
        guard manifestURL.scheme?.lowercased() == "https" else {
            throw BlackstockUpdateCheckError.manifestURLMustUseHTTPS
        }
        guard !publicKey.isEmpty else {
            throw BlackstockUpdateCheckError.missingPublicKey
        }
        guard !installerTeamID.isEmpty else {
            throw BlackstockUpdateCheckError.missingInstallerTeamID
        }

        var request = URLRequest(url: manifestURL)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse,
              200..<300 ~= http.statusCode else {
            throw BlackstockUpdateCheckError.invalidHTTPStatus(
                (response as? HTTPURLResponse)?.statusCode ?? -1
            )
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let manifest = try decoder.decode(
            BlackstockUpdateManifest.self,
            from: data
        )
        let verifier = UpdateManifestVerifier()
        try verifier.verify(
            manifest,
            publicKeyBase64: publicKey
        )

        let currentVersion = bundle.object(
            forInfoDictionaryKey: "CFBundleShortVersionString"
        ) as? String ?? "0.0.0"
        guard let buildString = bundle.object(
            forInfoDictionaryKey: "CFBundleVersion"
        ) as? String,
              let currentBuild = Int(buildString) else {
            throw BlackstockUpdateCheckError.invalidCurrentBuild
        }

        switch try verifier.availability(
            manifest: manifest,
            currentVersion: currentVersion,
            currentBuild: currentBuild
        ) {
        case .upToDate:
            return .upToDate
        case .updateAvailable(let update):
            BlackstockUpdateAudit.recordAvailableUpdate(
                manifest: update,
                manifestURL: manifestURL,
                installerTeamID: installerTeamID,
                bundle: bundle
            )
            return .updateAvailable(update)
        }
    }
}
#endif
