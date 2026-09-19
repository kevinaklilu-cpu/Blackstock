import XCTest
@testable import BlackstockCore

final class PublishingChannelIdentityGuardTests: XCTestCase {
    func testExactSingleTargetChannelPasses() throws {
        let identity = makeIdentity(id: "channel-A")
        let validated = try PublishingChannelIdentityGuard().validate(
            targetChannelID: "channel-A",
            identities: [identity]
        )

        XCTAssertEqual(validated.id, "channel-A")
    }

    func testWrongAuthorizedChannelHardStops() {
        XCTAssertThrowsError(
            try PublishingChannelIdentityGuard().validate(
                targetChannelID: "channel-A",
                identities: [makeIdentity(id: "channel-B")]
            )
        ) {
            XCTAssertEqual(
                $0 as? PublishingChannelIdentityValidationError,
                .targetChannelMismatch
            )
        }
    }

    func testMissingAuthorizedChannelHardStops() {
        XCTAssertThrowsError(
            try PublishingChannelIdentityGuard().validate(
                targetChannelID: "channel-A",
                identities: []
            )
        ) {
            XCTAssertEqual(
                $0 as? PublishingChannelIdentityValidationError,
                .noAuthorizedChannel
            )
        }
    }

    func testAmbiguousAuthorizedChannelsHardStop() {
        XCTAssertThrowsError(
            try PublishingChannelIdentityGuard().validate(
                targetChannelID: "channel-A",
                identities: [
                    makeIdentity(id: "channel-A"),
                    makeIdentity(id: "channel-B")
                ]
            )
        ) {
            XCTAssertEqual(
                $0 as? PublishingChannelIdentityValidationError,
                .ambiguousAuthorizedChannels
            )
        }
    }

    private func makeIdentity(id: String) -> YouTubeChannelIdentity {
        YouTubeChannelIdentity(
            id: id,
            title: id,
            handle: nil,
            avatarURL: nil,
            subscriberCount: nil,
            uploadsPlaylistID: nil
        )
    }
}
