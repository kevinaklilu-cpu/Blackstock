import Foundation
import XCTest
@testable import BlackstockCore

final class YouTubePackagingRecoveryTests: XCTestCase {
    func testThumbnail403KeepsCommittedVideoAndRetryDoesNotUploadVideoAgain() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let video = root.appendingPathComponent("video.mp4")
        try Data("committed-video-fixture".utf8).write(to: video)
        let thumbnail = root.appendingPathComponent("thumbnail.png")
        try XCTUnwrap(Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aL1sAAAAASUVORK5CYII=")).write(to: thumbnail)
        let id = UUID()
        let project = BlackstockProject(id: id, title: "Test", targetChannelID: "channel", stage: .publishing,
            strategyVersion: 1, createdAt: Date(), updatedAt: Date())
        let artifact = RenderArtifact(projectID: id, fileURL: video, sha256: "fixture", mimeType: "video/mp4", validated: true, createdAt: Date())
        let package = PublishPackage(projectID: id, targetChannelID: "channel", renderArtifactID: artifact.id,
            metadata: .init(title: "Test", description: "", privacyStatus: .privateVideo, selfDeclaredMadeForKids: false),
            thumbnail: .init(fileURL: thumbnail, mimeType: "image/png"), captions: [])
        let evidence = QualityEvidence(source: "Test", observedFact: "Fixture", reference: nil, observedAt: Date())
        let quality = CreatorQualityReview(projectID: id, stage: .review, evidence: [evidence],
            findings: AutomaticPublishReview.requiredAreas.map { QualityFinding(area: $0, severity: .info,
                title: "Fixture", explanation: "Fixture", recommendedAction: nil, evidenceIDs: [evidence.id]) }, reviewedAt: Date())
        let review = PublishReviewContext(project: project, artifact: artifact, package: package,
            qualityReview: quality, rightsValidated: true, publicPublishingAllowed: false, userConfirmed: true)
        let key = ["youtube-upload", id.uuidString, "channel", "fixture"].joined(separator: ":")
        let journal = ExternalActionJournal(entries: [.init(idempotencyKey: key, actionType: .youtubeUpload,
            targetChannelID: "channel", state: .remoteCommitted, remoteResourceID: "existing-video", createdAt: Date(), updatedAt: Date())])
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [ThumbnailRecoveryProtocol.self]
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }
        ThumbnailRecoveryProtocol.calls = 0
        let coordinator = YouTubePublishingCoordinator(uploadClient: .init(accessToken: "test"), packagingClient: .init(accessToken: "test"))
        let first = try await coordinator.publish(review: review, workspaceChannelID: "channel",
            authorizedUploadChannelID: "channel", quotaState: .unknown, networkAvailable: true,
            experimentID: nil, journal: journal, session: session)
        XCTAssertEqual(first.videoID, "existing-video")
        XCTAssertTrue(first.uploadReused)
        XCTAssertEqual(first.packagingWarnings?.count, 1)
        let second = try await coordinator.publish(review: review, workspaceChannelID: "channel",
            authorizedUploadChannelID: "channel", quotaState: .unknown, networkAvailable: true,
            experimentID: nil, journal: journal, session: session)
        XCTAssertNil(second.packagingWarnings)
        XCTAssertEqual(second.videoID, "existing-video")
        XCTAssertTrue(second.uploadReused)
        XCTAssertEqual(ThumbnailRecoveryProtocol.calls, 2)
    }
}

private final class ThumbnailRecoveryProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var calls = 0
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        XCTAssertEqual(request.url?.path, "/upload/youtube/v3/thumbnails/set")
        Self.calls += 1
        let status = Self.calls == 1 ? 403 : 200
        let body = status == 403 ? #"{"error":{"errors":[{"reason":"forbidden"}]}}"# : "{}"
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
