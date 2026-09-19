import XCTest
@testable import BlackstockCore

final class ExternalActionJournalPersistenceTests: XCTestCase {
    func testPersistentJournalSurvivesReload() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let url = directory.appendingPathComponent("journal.json")
        defer { try? FileManager.default.removeItem(at: directory) }

        let journal = try ExternalActionJournal.persistent(at: url)
        let entry = ExternalActionJournalEntry(
            idempotencyKey: "upload:1",
            actionType: .youtubeUpload,
            targetChannelID: "channel-A",
            state: .remoteSessionCreated,
            remoteSessionURL: URL(string: "https://upload.example/session"),
            nextByteOffset: 1_024,
            createdAt: Date(timeIntervalSince1970: 1),
            updatedAt: Date(timeIntervalSince1970: 2)
        )

        try await journal.upsert(entry)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))

        let reloaded = try ExternalActionJournal.persistent(at: url)
        let restored = await reloaded.entry(for: "upload:1")

        XCTAssertEqual(restored, entry)
    }

    func testFailedPersistenceRollsBackInMemoryMutation() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }

        let blockingFile = directory.appendingPathComponent("not-a-directory")
        try Data("x".utf8).write(to: blockingFile)
        let impossibleURL = blockingFile
            .appendingPathComponent("journal.json")

        let journal = ExternalActionJournal(
            persistenceURL: impossibleURL
        )
        let entry = ExternalActionJournalEntry(
            idempotencyKey: "upload:2",
            actionType: .youtubeUpload,
            targetChannelID: "channel-A",
            createdAt: Date(),
            updatedAt: Date()
        )

        do {
            try await journal.upsert(entry)
            XCTFail("Persistenzfehler wurde erwartet.")
        } catch {
            XCTAssertNil(await journal.entry(for: "upload:2"))
        }
    }
}
