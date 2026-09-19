import XCTest
@testable import BlackstockCore

final class YouTubeWrongChannelHardStopTests: XCTestCase {
    func testWrongWorkspaceChannelStopsBeforeFileOrJournalMutation() async {
        await assertWrongChannelHardStop(
            workspaceChannelID: "channel-B",
            authorizedUploadChannelID: "channel-A"
        )
    }

    func testWrongAuthorizedChannelStopsBeforeFileOrJournalMutation() async {
        await assertWrongChannelHardStop(
            workspaceChannelID: "channel-A",
            authorizedUploadChannelID: "channel-B"
        )
    }

    private func assertWrongChannelHardStop(
        workspaceChannelID: String,
        authorizedUploadChannelID: String
    ) async {
        let projectID = UUID()
        let project = BlackstockProject(
            id: projectID,
            title: "Wrong-channel preflight",
            targetChannelID: "channel-A",
            stage: .publishing,
            strategyVersion: 1,
            createdAt: Date(timeIntervalSince1970: 1),
            updatedAt: Date(timeIntervalSince1970: 1)
        )
        let missingFile = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("mp4")
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: missingFile.path)
        )

        let artifact = RenderArtifact(
            projectID: projectID,
            fileURL: missingFile,
            sha256: "not-used-because-preflight-must-stop-first",
            mimeType: "video/mp4",
            validated: true,
            createdAt: Date(timeIntervalSince1970: 2)
        )
        let journal = ExternalActionJournal()
        let uploader = YouTubeResumableUploader(
            accessToken: "test-access-token"
        )

        do {
            _ = try await uploader.upload(
                artifact: artifact,
                project: project,
                workspaceChannelID: workspaceChannelID,
                authorizedUploadChannelID: authorizedUploadChannelID,
                metadata: YouTubeUploadMetadata(
                    title: "Test",
                    description: "",
                    privacyStatus: .privateVideo,
                    selfDeclaredMadeForKids: false
                ),
                rightsValidated: true,
                quotaState: .unknown,
                networkAvailable: true,
                journal: journal
            )
            XCTFail("Wrong-channel preflight must hard-stop.")
        } catch {
            XCTAssertEqual(
                error as? PublicationPreflightError,
                .wrongChannel
            )
        }

        let entries = await journal.snapshot()
        XCTAssertTrue(
            entries.isEmpty,
            "A wrong-channel attempt must not prepare or mutate a remote-action journal entry."
        )
    }
}
