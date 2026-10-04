#if os(macOS)
import XCTest
import NaturalLanguage
@testable import BlackstockCore

final class SemanticSceneMatcherTests: XCTestCase {
    func testSemanticParaphraseSelectsLaterRelevantPassage() async throws {
        guard NLEmbedding.sentenceEmbedding(for: .english) != nil else {
            throw XCTSkip("Apple sentence model unavailable on this test host")
        }
        let transcript = LocalTranscript(localeIdentifier: "en-US", text: "The football player scores the winning goal in the final match. The baker prepares a chocolate cake in the kitchen.", segments: [
            .init(startSeconds: 0, durationSeconds: 4, text: "The baker prepares a chocolate cake in the kitchen.", confidence: 1),
            .init(startSeconds: 20, durationSeconds: 4, text: "The football player scores the winning goal in the final match.", confidence: 1)
        ], onDevice: true, createdAt: Date())
        let matcher = SemanticSceneMatcher()
        let match = await matcher.select(transcript: transcript,
            reference: "The striker wins the soccer game by scoring a goal.", sourceDuration: 30, maximumDuration: 6)
        XCTAssertEqual(match?.range.startSeconds, 20)
        let repeated = await matcher.select(transcript: transcript,
            reference: "The striker wins the soccer game by scoring a goal.", sourceDuration: 30, maximumDuration: 6,
            excluding: [.init(startSeconds: 20, durationSeconds: 4)])
        XCTAssertNil(repeated)
    }
}
#endif
