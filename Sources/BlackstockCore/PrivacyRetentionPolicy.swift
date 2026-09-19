import Foundation

public enum PrivacyRetentionKind: String, Sendable, Equatable {
    case untilExplicitDeletion
    case untilRevokedOrDeleted
    case sessionOnly
    case hours24
    case userControlled
}

public struct PrivacyRetentionRule: Sendable, Equatable {
    public let dataClass: String
    public let retention: PrivacyRetentionKind
    public let rationale: String

    public init(
        dataClass: String,
        retention: PrivacyRetentionKind,
        rationale: String
    ) {
        self.dataClass = dataClass
        self.retention = retention
        self.rationale = rationale
    }
}

public enum PrivacyRetentionPolicy {
    public static let canonical: [PrivacyRetentionRule] = [
        .init(
            dataClass: "Projekt-, Workspace- und Growth-Daten",
            retention: .untilExplicitDeletion,
            rationale: "Bleiben lokal, bis der Nutzer sie löscht."
        ),
        .init(
            dataClass: "Google-/YouTube-OAuth-Zugangsdaten",
            retention: .untilRevokedOrDeleted,
            rationale: "Liegen ausschließlich im gerätegebundenen Keychain."
        ),
        .init(
            dataClass: "Eingebettete YouTube-Recherche-Webdaten",
            retention: .sessionOnly,
            rationale: "Nichtpersistenter WebKit-Datenspeicher."
        ),
        .init(
            dataClass: "Temporäre verifizierte Update-Pakete",
            retention: .hours24,
            rationale: "Nur kurzzeitig für Nutzer-initiierte Installation erforderlich."
        ),
        .init(
            dataClass: "Lokale Datenschutzexporte",
            retention: .userControlled,
            rationale: "Liegt ausschließlich am vom Nutzer gewählten Speicherort."
        ),
    ]
}

public struct PrivacyRetentionEnforcer: Sendable {
    public init() {}

    @discardableResult
    public func purgeExpiredUpdatePackages(
        in directory: URL,
        now: Date = Date(),
        maximumAge: TimeInterval = 24 * 60 * 60
    ) throws -> Int {
        guard directory.isFileURL else { return 0 }
        let manager = FileManager.default
        guard let entries = try? manager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            return 0
        }

        var removed = 0
        for url in entries {
            guard url.pathExtension.lowercased() == "pkg",
                  url.lastPathComponent.hasPrefix("Blackstock-") else {
                continue
            }
            let values = try url.resourceValues(
                forKeys: [.contentModificationDateKey]
            )
            guard let modified = values.contentModificationDate,
                  now.timeIntervalSince(modified) > maximumAge else {
                continue
            }
            try manager.removeItem(at: url)
            removed += 1
        }
        return removed
    }
}
