import CoreModels
import Foundation
import XCTest

final class PlaybackDeliveryFailureTests: XCTestCase {
    func testRefusalsBelongOnlyToTheirExactPlaybackURLAndSurviveUnregistration() throws {
        let first = try XCTUnwrap(URL(string: "http://127.0.0.1:1234/\(UUID())/stream.m3u8"))
        let second = try XCTUnwrap(URL(string: "http://127.0.0.1:1234/\(UUID())/stream.m3u8"))
        let state = PlaybackDeliveryFailure.register(loopbackURL: first)
        let other = PlaybackDeliveryFailure.register(loopbackURL: second)
        defer {
            PlaybackDeliveryFailure.unregister(loopbackURL: first)
            PlaybackDeliveryFailure.unregister(loopbackURL: second)
        }
        XCTAssertTrue(PlaybackDeliveryFailure.state(for: first) === state)
        XCTAssertTrue(PlaybackDeliveryFailure.state(for: second) === other)
        state.record(.cancelled)
        XCTAssertNil(state.error)
        state.record(.accessRestricted)
        state.record(.invalidResponse)
        XCTAssertEqual(state.error, .accessRestricted)
        XCTAssertNil(other.error)
        PlaybackDeliveryFailure.unregister(loopbackURL: first)
        XCTAssertNil(PlaybackDeliveryFailure.state(for: first))
        XCTAssertEqual(state.error, .accessRestricted)
        XCTAssertTrue(PlaybackDeliveryFailure.state(for: second) === other)
    }
}
