import XCTest
@testable import BlackstockCore

final class MarketReadinessTests: XCTestCase {
    func testResearchClustersUseObservedSignalsOnly() {
        let now = Date()
        let videos = [
            VideoMetric(id: "a", title: "AI Coding Workflow", channelID: "c1", channelTitle: "One", publishedAt: now.addingTimeInterval(-3600), durationSeconds: 600, viewCount: 10_000, tags: ["AI Coding"]),
            VideoMetric(id: "b", title: "AI Coding Tools", channelID: "c2", channelTitle: "Two", publishedAt: now.addingTimeInterval(-7200), durationSeconds: 80, viewCount: 8_000, tags: ["AI Coding"]),
            VideoMetric(id: "c", title: "Cooking Pasta", channelID: "c3", channelTitle: "Three", publishedAt: now.addingTimeInterval(-3600), durationSeconds: 500, viewCount: 5_000, tags: ["Cooking"])
        ]
        let signals = TrendEngine().rank(videos: videos, channel: nil)
        let clusters = ResearchEngine().clusters(from: signals, minimumVideos: 2)
        XCTAssertEqual(clusters.count, 1)
        XCTAssertEqual(clusters[0].videoCount, 2)
        XCTAssertEqual(clusters[0].creatorCount, 2)
        XCTAssertEqual(clusters[0].shortCount, 1)
    }

    func testProjectRangeIsClamped() {
        let project = Project(title: "Test", editInSeconds: -10, editOutSeconds: 500)
        let range = ProjectWorkflowEngine().clampedRange(for: project, duration: 100)
        XCTAssertEqual(range.lowerBound, 0)
        XCTAssertEqual(range.upperBound, 100)
    }

    func testReadyRequiresRealAssetsAndPackaging() {
        var project = Project(title: "Test")
        XCTAssertNotEqual(ProjectWorkflowEngine().stage(for: project), .ready)
        project.renderedOutputURL = URL(fileURLWithPath: "/tmp/video.mp4")
        project.thumbnailURL = URL(fileURLWithPath: "/tmp/thumb.png")
        project.publishTitle = "Titel"
        project.publishDescription = "Beschreibung"
        XCTAssertEqual(ProjectWorkflowEngine().stage(for: project), .ready)
    }

    func testLegacyProjectJSONDecodesWithoutNewOptionalFields() throws {
        let id = UUID()
        let json = """
        {"id":"\(id.uuidString)","title":"Alt","sourceEvidenceIDs":[],"targetFormat":"short","transcript":"","notes":"","workingHook":"","titleVariants":[],"createdAt":0,"updatedAt":0}
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        let project = try decoder.decode(Project.self, from: Data(json.utf8))
        XCTAssertNil(project.renderedOutputURL)
        XCTAssertNil(project.publishDescription)
    }
}
