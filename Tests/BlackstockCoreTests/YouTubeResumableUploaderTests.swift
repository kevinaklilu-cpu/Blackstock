import Foundation
import XCTest
@testable import BlackstockCore

final class YouTubeResumableUploaderTests: XCTestCase {
    final class MockURLProtocol: URLProtocol {
        nonisolated(unsafe) static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

        override class func canInit(with request: URLRequest) -> Bool {
            true
        }

        override class func canonicalRequest(for request: URLRequest) -> URLRequest {
            request
        }

        override func startLoading() {
            guard let handler = Self.handler else {
                XCTFail("MockURLProtocol handler missing")
                return
            }
            do {
                let (response, data) = try handler(request)
                client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
                client?.urlProtocol(self, didLoad: data)
                client?.urlProtocolDidFinishLoading(self)
            } catch {
                client?.urlProtocol(self, didFailWithError: error)
            }
        }

        override func stopLoading() {}
    }

    func testResumeUsesRemoteOffsetPersistsProgressAndCommitsJournal() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        defer {
            MockURLProtocol.handler = nil
            try? FileManager.default.removeItem(at: directory)
        }

        let videoURL = directory.appendingPathComponent("video.mp4")
        let bytes = Data("0123456789".utf8)
        try bytes.write(to: videoURL)

        let projectID = UUID()
        let project = BlackstockProject(
            id: projectID,
            title: "Resume Test",
            targetChannelID: "channel-A",
            stage: .publishing,
            strategyVersion: 1,
            createdAt: Date(timeIntervalSince1970: 1),
            updatedAt: Date(timeIntervalSince1970: 2)
        )
        let artifact = RenderArtifact(
            projectID: projectID,
            fileURL: videoURL,
            sha256: String(repeating: "a", count: 64),
            mimeType: "video/mp4",
            validated: true,
            createdAt: Date(timeIntervalSince1970: 3)
        )
        let idempotencyKey = [
            "youtube-upload",
            project.id.uuidString,
            project.targetChannelID,
            artifact.sha256
        ].joined(separator: ":")

        let journalURL = directory.appendingPathComponent("journal.json")
        let journal = try ExternalActionJournal.persistent(at: journalURL)
        let uploadURL = URL(string: "https://upload.example/resumable/session-1")!
        try await journal.upsert(
            ExternalActionJournalEntry(
                idempotencyKey: idempotencyKey,
                actionType: .youtubeUpload,
                targetChannelID: project.targetChannelID,
                state: .remoteSessionCreated,
                remoteSessionURL: uploadURL,
                nextByteOffset: 2,
                createdAt: Date(timeIntervalSince1970: 4),
                updatedAt: Date(timeIntervalSince1970: 5)
            )
        )

        let lock = NSLock()
        var requestCount = 0

        MockURLProtocol.handler = { request in
            lock.lock()
            defer { lock.unlock() }
            requestCount += 1

            XCTAssertEqual(
                request.value(forHTTPHeaderField: "Authorization"),
                "Bearer access-token"
            )

            if requestCount == 1 {
                XCTAssertEqual(request.httpMethod, "PUT")
                XCTAssertEqual(
                    request.value(forHTTPHeaderField: "Content-Range"),
                    "bytes */10"
                )
                XCTAssertEqual(
                    request.value(forHTTPHeaderField: "Content-Length"),
                    "0"
                )
                let response = HTTPURLResponse(
                    url: uploadURL,
                    statusCode: 308,
                    httpVersion: nil,
                    headerFields: ["Range": "bytes=0-3"]
                )!
                return (response, Data())
            }

            XCTAssertEqual(requestCount, 2)
            XCTAssertEqual(request.httpMethod, "PUT")
            XCTAssertEqual(
                request.value(forHTTPHeaderField: "Content-Range"),
                "bytes 4-9/10"
            )
            XCTAssertEqual(
                request.httpBody,
                Data("456789".utf8)
            )
            let response = HTTPURLResponse(
                url: uploadURL,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            return (
                response,
                Data(#"{"id":"video-123"}"#.utf8)
            )
        }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        let session = URLSession(configuration: configuration)

        let result = try await YouTubeResumableUploader(
            accessToken: "access-token",
            chunkSize: 256 * 1024
        ).upload(
            artifact: artifact,
            project: project,
            workspaceChannelID: "channel-A",
            authorizedUploadChannelID: "channel-A",
            metadata: YouTubeUploadMetadata(
                title: "Video",
                description: "Beschreibung",
                privacyStatus: .privateVideo,
                selfDeclaredMadeForKids: false
            ),
            rightsValidated: true,
            quotaState: .unknown,
            networkAvailable: true,
            journal: journal,
            session: session,
            now: Date(timeIntervalSince1970: 6)
        )

        XCTAssertEqual(result.videoID, "video-123")
        XCTAssertFalse(result.reusedCommittedAction)
        XCTAssertEqual(requestCount, 2)

        let committedEntry = await journal.entry(for: idempotencyKey)
        let committed = try XCTUnwrap(committedEntry)
        XCTAssertEqual(committed.state, .remoteCommitted)
        XCTAssertEqual(committed.remoteResourceID, "video-123")
        XCTAssertEqual(committed.nextByteOffset, 10)

        let reloaded = try ExternalActionJournal.persistent(at: journalURL)
        let persistedEntry = await reloaded.entry(for: idempotencyKey)
        let persisted = try XCTUnwrap(persistedEntry)
        XCTAssertEqual(persisted.state, .remoteCommitted)
        XCTAssertEqual(persisted.remoteResourceID, "video-123")
        XCTAssertEqual(persisted.nextByteOffset, 10)
    }

    func testResumeRequestBuildersAuthenticateEveryPut() {
        let uploadURL = URL(string: "https://upload.example/session")!

        let status = YouTubeResumableUploader.resumableStatusRequest(
            uploadURL: uploadURL,
            totalSize: 100,
            accessToken: "token"
        )
        XCTAssertEqual(
            status.value(forHTTPHeaderField: "Authorization"),
            "Bearer token"
        )
        XCTAssertEqual(
            status.value(forHTTPHeaderField: "Content-Range"),
            "bytes */100"
        )

        let chunk = YouTubeResumableUploader.resumableChunkRequest(
            uploadURL: uploadURL,
            mimeType: "video/mp4",
            totalSize: 100,
            offset: 20,
            data: Data(repeating: 1, count: 10),
            accessToken: "token"
        )
        XCTAssertEqual(
            chunk.value(forHTTPHeaderField: "Authorization"),
            "Bearer token"
        )
        XCTAssertEqual(
            chunk.value(forHTTPHeaderField: "Content-Range"),
            "bytes 20-29/100"
        )
    }
}
