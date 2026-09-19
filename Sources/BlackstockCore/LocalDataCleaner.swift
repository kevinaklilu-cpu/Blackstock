import Foundation

public struct LocalDataDeletionReport: Sendable, Equatable {
    public let rootExisted: Bool
    public let fileCount: Int
    public let directoryCount: Int

    public init(
        rootExisted: Bool,
        fileCount: Int,
        directoryCount: Int
    ) {
        self.rootExisted = rootExisted
        self.fileCount = fileCount
        self.directoryCount = directoryCount
    }
}

public enum LocalDataDeletionError: Error, Sendable, Equatable {
    case nonFileURL
}

public struct LocalDataCleaner: Sendable {
    public init() {}

    public func deleteDirectoryIfPresent(
        _ rootURL: URL
    ) throws -> LocalDataDeletionReport {
        guard rootURL.isFileURL else {
            throw LocalDataDeletionError.nonFileURL
        }

        let manager = FileManager.default
        guard manager.fileExists(atPath: rootURL.path) else {
            return LocalDataDeletionReport(
                rootExisted: false,
                fileCount: 0,
                directoryCount: 0
            )
        }

        var files = 0
        var directories = 1

        if let enumerator = manager.enumerator(
            at: rootURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) {
            for case let url as URL in enumerator {
                let values = try url.resourceValues(
                    forKeys: [.isDirectoryKey]
                )
                if values.isDirectory == true {
                    directories += 1
                } else {
                    files += 1
                }
            }
        }

        try manager.removeItem(at: rootURL)

        return LocalDataDeletionReport(
            rootExisted: true,
            fileCount: files,
            directoryCount: directories
        )
    }
}
