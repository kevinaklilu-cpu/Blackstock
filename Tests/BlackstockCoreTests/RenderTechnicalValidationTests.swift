#if os(macOS)
import XCTest
import CoreGraphics
@testable import BlackstockCore

final class RenderTechnicalValidationTests: XCTestCase {
    func testValidSnapshotPassesTechnicalValidation() {
        let snapshot = RenderTechnicalSnapshot(
            fileSizeBytes: 5_000_000,
            durationSeconds: 30.02,
            videoTrackCount: 1,
            width: 1920,
            height: 1080,
            inspectedAt: Date()
        )

        let assessment = RenderTechnicalValidator().assess(
            snapshot: snapshot,
            expectedDurationSeconds: 30,
            expectedRenderSize: CGSize(width: 1920, height: 1080)
        )

        XCTAssertTrue(assessment.validated)
        XCTAssertTrue(assessment.blockers.isEmpty)
    }

    func testDurationMismatchBlocksValidation() {
        let snapshot = RenderTechnicalSnapshot(
            fileSizeBytes: 5_000_000,
            durationSeconds: 24,
            videoTrackCount: 1,
            width: 1920,
            height: 1080,
            inspectedAt: Date()
        )

        let assessment = RenderTechnicalValidator().assess(
            snapshot: snapshot,
            expectedDurationSeconds: 30,
            expectedRenderSize: CGSize(width: 1920, height: 1080)
        )

        XCTAssertFalse(assessment.validated)
        XCTAssertTrue(assessment.blockers.contains(.durationMismatch))
    }

    func testWrongOutputGeometryBlocksReframedRender() {
        let snapshot = RenderTechnicalSnapshot(
            fileSizeBytes: 5_000_000,
            durationSeconds: 30,
            videoTrackCount: 1,
            width: 1920,
            height: 1080,
            inspectedAt: Date()
        )

        let assessment = RenderTechnicalValidator().assess(
            snapshot: snapshot,
            expectedDurationSeconds: 30,
            expectedRenderSize: CGSize(width: 1080, height: 1920)
        )

        XCTAssertFalse(assessment.validated)
        XCTAssertTrue(assessment.blockers.contains(.dimensionMismatch))
    }

    func testMissingVideoTrackBlocksValidation() {
        let snapshot = RenderTechnicalSnapshot(
            fileSizeBytes: 1024,
            durationSeconds: 30,
            videoTrackCount: 0,
            width: 0,
            height: 0,
            inspectedAt: Date()
        )

        let assessment = RenderTechnicalValidator().assess(
            snapshot: snapshot,
            expectedDurationSeconds: 30,
            expectedRenderSize: nil
        )

        XCTAssertFalse(assessment.validated)
        XCTAssertTrue(assessment.blockers.contains(.missingVideoTrack))
        XCTAssertTrue(assessment.blockers.contains(.invalidDimensions))
    }


    func testMeasuredGeometryClassifiesUHDWithoutAssumingOrientation() {
        let landscape = RenderTechnicalSnapshot(
            fileSizeBytes: 1,
            durationSeconds: 1,
            videoTrackCount: 1,
            width: 3840,
            height: 2160,
            inspectedAt: Date()
        )
        let portrait = RenderTechnicalSnapshot(
            fileSizeBytes: 1,
            durationSeconds: 1,
            videoTrackCount: 1,
            width: 2160,
            height: 3840,
            inspectedAt: Date()
        )
        let ultrawideButNotUHD = RenderTechnicalSnapshot(
            fileSizeBytes: 1,
            durationSeconds: 1,
            videoTrackCount: 1,
            width: 3840,
            height: 1600,
            inspectedAt: Date()
        )

        XCTAssertTrue(landscape.meetsUHD4KOrGreater)
        XCTAssertTrue(portrait.meetsUHD4KOrGreater)
        XCTAssertFalse(ultrawideButNotUHD.meetsUHD4KOrGreater)
    }

    func testRenderArtifactPersistsMeasuredGeometryAndRequestedCeiling() throws {
        let snapshot = RenderTechnicalSnapshot(
            fileSizeBytes: 5_000_000,
            durationSeconds: 30,
            videoTrackCount: 1,
            width: 3840,
            height: 2160,
            inspectedAt: Date(timeIntervalSince1970: 10)
        )
        let artifact = RenderArtifact(
            projectID: UUID(),
            fileURL: URL(fileURLWithPath: "/tmp/final.mp4"),
            sha256: "abc",
            mimeType: "video/mp4",
            validated: true,
            requestedQuality: .upTo4K,
            technicalSnapshot: snapshot,
            createdAt: Date(timeIntervalSince1970: 11)
        )

        let data = try JSONEncoder().encode(artifact)
        let decoded = try JSONDecoder().decode(
            RenderArtifact.self,
            from: data
        )

        XCTAssertEqual(decoded.requestedQuality, .upTo4K)
        XCTAssertEqual(decoded.technicalSnapshot, snapshot)
        XCTAssertTrue(decoded.technicalSnapshot?.meetsUHD4KOrGreater == true)
    }

    func testLegacyArtifactWithoutValidationVersionIsNotCurrent() throws {
        struct LegacyArtifact: Codable {
            let id: UUID
            let projectID: UUID
            let fileURL: URL
            let sha256: String
            let mimeType: String
            let validated: Bool
            let createdAt: Date
        }

        let legacy = LegacyArtifact(
            id: UUID(),
            projectID: UUID(),
            fileURL: URL(fileURLWithPath: "/tmp/legacy.mp4"),
            sha256: "abc",
            mimeType: "video/mp4",
            validated: true,
            createdAt: Date(timeIntervalSince1970: 1)
        )

        let data = try JSONEncoder().encode(legacy)
        let decoded = try JSONDecoder().decode(
            RenderArtifact.self,
            from: data
        )

        XCTAssertTrue(decoded.validated)
        XCTAssertNil(decoded.validationVersion)
        XCTAssertFalse(decoded.hasCurrentTechnicalValidation)
    }
}
#endif
