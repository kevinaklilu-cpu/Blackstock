import XCTest
@testable import BlackstockCore

final class CaptionTechnicalInspectorTests: XCTestCase {
    func testValidWebVTTPasses() throws {
        let url = try writeTemporary(
            extension: "vtt",
            contents: """
            WEBVTT

            00:00:00.000 --> 00:00:02.500
            Hallo Welt.

            00:00:02.500 --> 00:00:05.000
            Zweiter Cue.
            """
        )
        defer { try? FileManager.default.removeItem(at: url) }

        let assessment = try CaptionTechnicalInspector().inspect(url: url)

        XCTAssertTrue(assessment.uploadCompatible)
        XCTAssertEqual(assessment.snapshot.format, .webVTT)
        XCTAssertEqual(assessment.snapshot.cueCount, 2)
        let lastCueEnd = try XCTUnwrap(
            assessment.snapshot.lastCueEndSeconds
        )
        XCTAssertEqual(
            lastCueEnd,
            5,
            accuracy: 0.001
        )
    }

    func testValidSubRipPasses() throws {
        let url = try writeTemporary(
            extension: "srt",
            contents: """
            1
            00:00:00,500 --> 00:00:02,000
            Hallo.

            2
            00:00:02,000 --> 00:00:03,250
            Welt.
            """
        )
        defer { try? FileManager.default.removeItem(at: url) }

        let assessment = try CaptionTechnicalInspector().inspect(url: url)

        XCTAssertTrue(assessment.uploadCompatible)
        XCTAssertEqual(assessment.snapshot.format, .subRip)
        XCTAssertEqual(assessment.snapshot.cueCount, 2)
    }

    func testMalformedTimingBlocksCaption() throws {
        let url = try writeTemporary(
            extension: "vtt",
            contents: """
            WEBVTT

            broken --> 00:00:02.000
            Text
            """
        )
        defer { try? FileManager.default.removeItem(at: url) }

        let assessment = try CaptionTechnicalInspector().inspect(url: url)

        XCTAssertFalse(assessment.uploadCompatible)
        XCTAssertTrue(
            assessment.blockers.contains(.invalidCueTiming)
        )
        XCTAssertTrue(
            assessment.blockers.contains(.noTimedCues)
        )
    }

    func testMissingWebVTTHeaderBlocksCaption() throws {
        let url = try writeTemporary(
            extension: "vtt",
            contents: """
            00:00:00.000 --> 00:00:02.000
            Text
            """
        )
        defer { try? FileManager.default.removeItem(at: url) }

        let assessment = try CaptionTechnicalInspector().inspect(url: url)

        XCTAssertFalse(assessment.uploadCompatible)
        XCTAssertTrue(
            assessment.blockers.contains(.missingWebVTTHeader)
        )
    }

    func testUnsupportedPlainTextDoesNotMasqueradeAsCaption() throws {
        let url = try writeTemporary(
            extension: "txt",
            contents: """
            00:00:00.000 --> 00:00:02.000
            Text
            """
        )
        defer { try? FileManager.default.removeItem(at: url) }

        let assessment = try CaptionTechnicalInspector().inspect(url: url)

        XCTAssertFalse(assessment.uploadCompatible)
        XCTAssertTrue(
            assessment.blockers.contains(.unsupportedFormat)
        )
    }

    private func writeTemporary(
        extension fileExtension: String,
        contents: String
    ) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(fileExtension)
        try contents.write(
            to: url,
            atomically: true,
            encoding: .utf8
        )
        return url
    }
}
