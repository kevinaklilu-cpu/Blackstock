import XCTest
@testable import BlackstockCore

final class PublicationEditorDraftTests: XCTestCase {
    func testEditedFieldsAndSelectedThumbnailSurviveRoundTrip() throws {
        let options = [URL(fileURLWithPath: "/tmp/first.jpg"), URL(fileURLWithPath: "/tmp/second.jpg")]
        let draft = PublicationEditorDraft(title: "Ein eigener Titel", description: "Eigene Beschreibung\nMit zweiter Zeile.",
            tags: "Sport, Finale", thumbnailURL: options[1], thumbnailOptions: options)
        XCTAssertEqual(try JSONDecoder().decode(PublicationEditorDraft.self, from: JSONEncoder().encode(draft)), draft)
    }
    func testLegacyFooterCleanupPreservesDescription() {
        let original = "Eigene Beschreibung.\n\nShort · Ausschnitt 2:03–2:25\nQuelle: https://youtube.com/watch?v=source"
        XCTAssertEqual(PublicationEditorDraft.removingGeneratedSourceFooter(original), "Eigene Beschreibung.")
    }
    func testPublicDescriptionDoesNotInsertSourceBoilerplate() {
        let draft = StoryPublicationDraft.forClip(transcript: nil, sourceURL: URL(string: "https://youtube.com/watch?v=source"),
            start: 123, duration: 22, isShort: true)
        XCTAssertFalse(draft.description.contains("Quelle:"))
        XCTAssertFalse(draft.description.contains("youtube.com"))
        XCTAssertFalse(draft.description.contains("Ausschnitt"))
        XCTAssertTrue(draft.description.isEmpty)
    }
}
