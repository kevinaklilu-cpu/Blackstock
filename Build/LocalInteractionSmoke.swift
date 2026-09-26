import Foundation
import Security

@main struct LocalInteractionSmoke {
    enum Expected: Error { case failure }

    @MainActor static func main() async throws {
        var original: DarwinBoolean = false
        precondition(SecKeychainGetUserInteractionAllowed(&original) == errSecSuccess)
        try BlackstockKeychain.withoutUserInteraction {
            var allowed: DarwinBoolean = true
            precondition(SecKeychainGetUserInteractionAllowed(&allowed) == errSecSuccess && !allowed.boolValue)
            try BlackstockKeychain.withoutUserInteraction {
                precondition(SecKeychainGetUserInteractionAllowed(&allowed) == errSecSuccess && !allowed.boolValue)
            }
            precondition(SecKeychainGetUserInteractionAllowed(&allowed) == errSecSuccess && !allowed.boolValue)
        }
        do {
            try BlackstockKeychain.withoutUserInteraction { throw Expected.failure }
        } catch Expected.failure {}
        var restored: DarwinBoolean = false
        precondition(SecKeychainGetUserInteractionAllowed(&restored) == errSecSuccess && restored.boolValue == original.boolValue)
        print("KEYCHAIN_NO_UI_RESTORE_PASS")
        let fixtureAccount = "test-blocked-" + UUID().uuidString
        BlackstockKeychain.recordAccessResult(errSecInteractionNotAllowed, account: fixtureAccount)
        for _ in 0..<100 { precondition(BlackstockKeychain.read(fixtureAccount).isEmpty) }
        try await Task.sleep(nanoseconds: 20_000_000)
        precondition(BlackstockKeychain.accessIssue.value != nil)
        BlackstockKeychain.recordAccessResult(errSecSuccess, account: fixtureAccount)
        try await Task.sleep(nanoseconds: 20_000_000)
        precondition(BlackstockKeychain.accessIssue.value == nil)
        print("KEYCHAIN_BLOCKED_READ_COALESCING_PASS")
        let oldGeneration = UserDefaults.standard.string(forKey: "blackstock.keychain.generation")
        defer {
            if let oldGeneration { UserDefaults.standard.set(oldGeneration, forKey: "blackstock.keychain.generation") }
            else { UserDefaults.standard.removeObject(forKey: "blackstock.keychain.generation") }
        }
        let oldAccount = BlackstockKeychain.storageAccount("test.account")
        BlackstockKeychain.startFreshCredentialStore()
        let newAccount = BlackstockKeychain.storageAccount("test.account")
        precondition(oldAccount != newAccount)
        precondition(newAccount == BlackstockKeychain.storageAccount("test.account"))
        precondition(newAccount != BlackstockKeychain.storageAccount("other.account"))
        print("FRESH_LOGIN_CREDENTIAL_ISOLATION_PASS")

        let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let first = root.appendingPathComponent("first", isDirectory: true)
        let second = root.appendingPathComponent("second", isDirectory: true)
        try FileManager.default.createDirectory(at: first, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: second, withIntermediateDirectories: true)
        let watcher = IngestDirectoryWatcher()
        var events = 0
        for index in 0..<20 {
            watcher.start(directoryURL: first) { events += 1 }
            try Data("event".utf8).write(to: first.appendingPathComponent("file-\(index)"))
            for _ in 0..<20 {
                if watcher.lastEventAt != nil { break }
                try await Task.sleep(nanoseconds: 10_000_000)
            }
            watcher.stop()
            watcher.start(directoryURL: second) { events += 1 }
            try Data("event".utf8).write(to: second.appendingPathComponent("file-\(index)"))
            try await Task.sleep(nanoseconds: 20_000_000)
            watcher.stop()
        }
        try await Task.sleep(nanoseconds: 100_000_000)
        precondition(events > 0 && !watcher.isWatching)
        let before = events
        try Data("after stop".utf8).write(to: second.appendingPathComponent("stopped"))
        try await Task.sleep(nanoseconds: 100_000_000)
        precondition(events == before)
        print("INGEST_START_EVENT_CANCEL_RESTART_PASS", events)
    }
}
