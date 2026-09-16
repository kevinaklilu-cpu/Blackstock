import XCTest
@testable import BlackstockCore

final class ReleasePackageTests: XCTestCase {
    func testRenderCanvasDimensions() {
        XCTAssertEqual(RenderCanvas.landscape16x9.pixelWidth, 1920)
        XCTAssertEqual(RenderCanvas.landscape16x9.pixelHeight, 1080)
        XCTAssertEqual(RenderCanvas.vertical9x16.pixelWidth, 1080)
        XCTAssertEqual(RenderCanvas.vertical9x16.pixelHeight, 1920)
        XCTAssertNil(RenderCanvas.source.pixelWidth)
    }

    func testManifestRequiresReadyProject() throws {
        let project = Project(title: "Unfertig")
        XCTAssertThrowsError(try ReleasePackageBuilder().manifest(for: project))
    }

    func testManifestKeepsReleaseMetadata() throws {
        let project = Project(
            title: "Working",
            localMediaURL: URL(fileURLWithPath: "/tmp/source.mov"),
            targetFormat: .short,
            renderedOutputURL: URL(fileURLWithPath: "/tmp/final.mp4"),
            thumbnailURL: URL(fileURLWithPath: "/tmp/thumb.png"),
            publishTitle: "Finaler Titel",
            publishDescription: "Beschreibung",
            publishTags: ["eins", "zwei"],
            renderCanvas: .vertical9x16
        )
        let manifest = try ReleasePackageBuilder().manifest(for: project, createdAt: Date(timeIntervalSince1970: 1))
        XCTAssertEqual(manifest.product, "Blackstock")
        XCTAssertEqual(manifest.title, "Finaler Titel")
        XCTAssertEqual(manifest.tags, ["eins", "zwei"])
        XCTAssertEqual(manifest.targetFormat, .short)
        XCTAssertEqual(manifest.renderCanvas, .vertical9x16)
        XCTAssertEqual(manifest.videoFileName, "final.mp4")
        XCTAssertEqual(manifest.thumbnailFileName, "thumb.png")
    }

    func testOptionalRenderFieldsRemainBackwardDecodable() throws {
        let oldJSON = """
        {"id":"00000000-0000-0000-0000-000000000001","title":"Alt","sourceEvidenceIDs":[],"targetFormat":"short","transcript":"","notes":"","workingHook":"","titleVariants":[],"createdAt":0,"updatedAt":0}
        """.data(using: .utf8)!
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        let project = try decoder.decode(Project.self, from: oldJSON)
        XCTAssertEqual(project.effectiveRenderCanvas, .source)
        XCTAssertEqual(project.effectiveCropAnchorX, 0.5)
    }
}
