import Foundation

public enum PrivacyDataExportError: Error, Sendable, Equatable {
    case nonFileURL
    case destinationMissing
}

public struct PrivacyDataExportReport: Sendable, Equatable {
    public let exportURL: URL
    public let copiedLocalData: Bool
    public let includedUserDefaults: Bool

    public init(
        exportURL: URL,
        copiedLocalData: Bool,
        includedUserDefaults: Bool
    ) {
        self.exportURL = exportURL
        self.copiedLocalData = copiedLocalData
        self.includedUserDefaults = includedUserDefaults
    }
}

public struct PrivacyDataExporter: Sendable {
    public init() {}

    public func export(
        applicationSupportRoot: URL,
        userDefaultsPlist: Data,
        destinationDirectory: URL,
        exportID: UUID = UUID()
    ) throws -> PrivacyDataExportReport {
        guard applicationSupportRoot.isFileURL,
              destinationDirectory.isFileURL else {
            throw PrivacyDataExportError.nonFileURL
        }

        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(
            atPath: destinationDirectory.path,
            isDirectory: &isDirectory
        ), isDirectory.boolValue else {
            throw PrivacyDataExportError.destinationMissing
        }

        let exportURL = destinationDirectory
            .appendingPathComponent(
                "Blackstock-Privacy-Export-\(exportID.uuidString)",
                isDirectory: true
            )
        try FileManager.default.createDirectory(
            at: exportURL,
            withIntermediateDirectories: false
        )

        var copiedLocalData = false
        if FileManager.default.fileExists(
            atPath: applicationSupportRoot.path
        ) {
            let localDataURL = exportURL.appendingPathComponent(
                "LocalData",
                isDirectory: true
            )
            try FileManager.default.copyItem(
                at: applicationSupportRoot,
                to: localDataURL
            )
            copiedLocalData = true
        }

        let defaultsURL = exportURL.appendingPathComponent(
            "BlackstockUserDefaults.plist"
        )
        try userDefaultsPlist.write(
            to: defaultsURL,
            options: [.atomic]
        )

        let notice = """
        Blackstock Datenschutzexport

        Enthalten:
        - lokale Blackstock-Projekt-/Workspace-/Growth-Daten, soweit vorhanden
        - Blackstock-bezogene UserDefaults

        Nicht enthalten:
        - OAuth Access Tokens
        - OAuth Refresh Tokens
        - Keychain-Geheimnisse
        - client_secret

        Der Export bleibt vollständig lokal in dem von dir gewählten Ordner.
        """
        try Data(notice.utf8).write(
            to: exportURL.appendingPathComponent("README.txt"),
            options: [.atomic]
        )

        return PrivacyDataExportReport(
            exportURL: exportURL,
            copiedLocalData: copiedLocalData,
            includedUserDefaults: true
        )
    }
}
