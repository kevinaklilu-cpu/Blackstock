import XCTest
@testable import BlackstockCore

final class SavedClipSelectionTests: XCTestCase {
    func testTitleRoundTripPreservesClipBindings() throws {
        let projectID = UUID()
        let artifact = RenderArtifact(
            projectID: projectID,
            fileURL: URL(fileURLWithPath: "/tmp/clip.mp4"),
            sha256: String(repeating: "a", count: 64),
            mimeType: "video/mp4",
            validated: true,
            createdAt: Date(timeIntervalSince1970: 5)
        )
        let transcript = LocalTranscript(
            localeIdentifier: "de-DE",
            text: "Ein gespeicherter Clip",
            segments: [],
            onDevice: true,
            createdAt: Date(timeIntervalSince1970: 4)
        )
        let clip = SavedClipSelection(
            sourceRange: EditTimeRange(
                startSeconds: 10,
                durationSeconds: 25
            ),
            title: "Starker Einstieg",
            transcriptPreview: "Ein gespeicherter Clip",
            wordCount: 3,
            transcript: transcript,
            renderArtifact: artifact,
            savedAt: Date(timeIntervalSince1970: 6)
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(clip)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let restored = try decoder.decode(
            SavedClipSelection.self,
            from: data
        )

        XCTAssertEqual(restored, clip)
        XCTAssertEqual(
            restored.displayTitle,
            "Starker Einstieg"
        )
        XCTAssertEqual(
            restored.renderArtifact?.id,
            artifact.id
        )
        XCTAssertEqual(
            restored.transcript,
            transcript
        )
    }

    func testLegacyClipWithoutTitleStillDecodes() throws {
        let clip = SavedClipSelection(
            sourceRange: EditTimeRange(
                startSeconds: 2,
                durationSeconds: 20
            ),
            transcriptPreview: "Legacy Clip",
            wordCount: 2,
            savedAt: Date(timeIntervalSince1970: 3)
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let encoded = try encoder.encode(clip)
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(
                with: encoded
            ) as? [String: Any]
        )
        object.removeValue(forKey: "title")
        let legacyData = try JSONSerialization.data(
            withJSONObject: object
        )

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let restored = try decoder.decode(
            SavedClipSelection.self,
            from: legacyData
        )

        XCTAssertNil(restored.title)
        XCTAssertEqual(
            restored.displayTitle,
            "Clip"
        )
        XCTAssertEqual(
            restored.transcriptPreview,
            "Legacy Clip"
        )
    }

    func testWithTitleNormalizesWhitespaceAndPreservesRender() {
        let projectID = UUID()
        let artifact = RenderArtifact(
            projectID: projectID,
            fileURL: URL(fileURLWithPath: "/tmp/clip.mp4"),
            sha256: String(repeating: "b", count: 64),
            mimeType: "video/mp4",
            validated: true,
            createdAt: Date(timeIntervalSince1970: 5)
        )
        let clip = SavedClipSelection(
            sourceRange: EditTimeRange(
                startSeconds: 0,
                durationSeconds: 30
            ),
            transcriptPreview: "Text",
            wordCount: 1,
            renderArtifact: artifact,
            savedAt: Date(timeIntervalSince1970: 6)
        )

        let renamed = clip.withTitle(
            "  Mein Clip  "
        )

        XCTAssertEqual(renamed.title, "Mein Clip")
        XCTAssertEqual(
            renamed.renderArtifact,
            artifact
        )
        XCTAssertEqual(
            renamed.sourceRange,
            clip.sourceRange
        )
    }
}
