#if os(macOS)
import Foundation
import BlackstockCore

enum BlackstockUpdateDownloadError: Error, LocalizedError {
    case packageURLMustUseHTTPS
    case invalidHTTPStatus(Int)
    case temporaryFileMissing
    case missingInstallerTeamID

    var errorDescription: String? {
        switch self {
        case .packageURLMustUseHTTPS:
            return "Das Update-Paket muss über HTTPS geladen werden."
        case .invalidHTTPStatus(let status):
            return "Der Update-Server antwortete beim Paketdownload mit HTTP \(status)."
        case .temporaryFileMissing:
            return "Das geladene Update-Paket ist nicht verfügbar."
        case .missingInstallerTeamID:
            return "Für das Update ist keine erwartete Developer-ID-Installer-Team-ID konfiguriert."
        }
    }
}

struct BlackstockUpdatePackageDownloader: Sendable {
    func downloadAndVerify(
        manifest: BlackstockUpdateManifest,
        bundle: Bundle = .main,
        session: URLSession = .shared
    ) async throws -> URL {
        guard ProductionUpdateURLPolicy.allows(
            manifest.packageURL
        ) else {
            throw BlackstockUpdateDownloadError
                .packageURLMustUseHTTPS
        }
        let expectedTeamID = (
            bundle.object(
                forInfoDictionaryKey: "BlackstockUpdateInstallerTeamID"
            ) as? String ?? ""
        ).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !expectedTeamID.isEmpty else {
            throw BlackstockUpdateDownloadError.missingInstallerTeamID
        }

        var request = URLRequest(url: manifest.packageURL)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 120
        request.setValue(
            "application/octet-stream",
            forHTTPHeaderField: "Accept"
        )

        let (temporaryURL, response) = try await session.download(for: request)
        guard let http = response as? HTTPURLResponse,
              200..<300 ~= http.statusCode else {
            try? FileManager.default.removeItem(at: temporaryURL)
            throw BlackstockUpdateDownloadError.invalidHTTPStatus(
                (response as? HTTPURLResponse)?.statusCode ?? -1
            )
        }
        guard let finalURL = http.url,
              ProductionUpdateURLPolicy.allows(
                finalURL
              ) else {
            try? FileManager.default.removeItem(
                at: temporaryURL
            )
            throw BlackstockUpdateDownloadError
                .packageURLMustUseHTTPS
        }

        guard FileManager.default.fileExists(atPath: temporaryURL.path) else {
            throw BlackstockUpdateDownloadError.temporaryFileMissing
        }

        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "Blackstock-\(manifest.version)-\(manifest.build)-\(UUID().uuidString)"
            )
            .appendingPathExtension("pkg")

        do {
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.moveItem(
                at: temporaryURL,
                to: destination
            )
            try UpdatePackageIntegrityVerifier().verify(
                fileURL: destination,
                expectedSHA256: manifest.sha256
            )
            try BlackstockInstallerPackageVerifier().verify(
                fileURL: destination,
                expectedTeamID: expectedTeamID
            )
            BlackstockUpdateAudit.recordVerifiedPackage(
                manifest: manifest
            )
            return destination
        } catch {
            try? FileManager.default.removeItem(at: temporaryURL)
            try? FileManager.default.removeItem(at: destination)
            throw error
        }
    }
}
#endif
