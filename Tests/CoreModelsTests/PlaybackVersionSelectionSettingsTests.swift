import XCTest
@testable import CoreModels

final class PlaybackVersionSelectionSettingsTests: XCTestCase {
    func testOldUnknownAndNullModesRemainUnanswered() throws {
        for json in ["{}", #"{"versionSelectionMode":null}"#, #"{"versionSelectionMode":"future"}"#] {
            XCTAssertNil(try JSONDecoder().decode(PlaybackSettings.self, from: Data(json.utf8)).versionSelectionMode)
        }
    }

    func testModesRoundTripWithoutChangingOtherPlaybackPreferences() throws {
        for mode in PlaybackVersionSelectionMode.allCases {
            let settings = PlaybackSettings(backgroundAudio: true, versionSelectionMode: mode)
            XCTAssertEqual(try JSONDecoder().decode(PlaybackSettings.self, from: JSONEncoder().encode(settings)), settings)
        }
    }

    @MainActor
    func testChoiceIsProfileScopedAndIncludedInProfileTransfer() throws {
        let suite = "version-mode-\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let primary = PlaybackSettingsStore(defaults: defaults)
        let guest = PlaybackSettingsStore(defaults: defaults, namespace: "guest")
        let model = PlaybackSettingsModel(store: primary)
        model.settings.versionSelectionMode = .askEveryTime
        XCTAssertEqual(primary.load().versionSelectionMode, .askEveryTime)
        XCTAssertNil(guest.load().versionSelectionMode)
        let guestModel = PlaybackSettingsModel(store: guest)
        guestModel.settings.versionSelectionMode = .rememberChoice
        let snapshot = ProfileSettingsTransfer.capture(namespace: "guest", defaults: defaults)
        ProfileSettingsTransfer.apply(snapshot, namespace: "restored", defaults: defaults)
        XCTAssertEqual(PlaybackSettingsStore(defaults: defaults, namespace: "restored").load().versionSelectionMode, .rememberChoice)
        XCTAssertEqual(primary.load().versionSelectionMode, .askEveryTime)
    }

    func testAutomaticMatchingDoesNotSubstituteDifferentOrUnknownFacts() {
        let original = MediaVersion(
            id: "one", edition: "Extended", height: 2160,
            videoCodec: "hevc", videoRange: "HDR10", audioProfile: "Atmos"
        )
        let descriptor = MediaVersionDescriptor(version: original)
        var next = original
        next.id = "another-episode"
        XCTAssertTrue(descriptor.matchesForAutomaticSelection(next))
        next.height = 1080
        XCTAssertFalse(descriptor.matchesForAutomaticSelection(next))
        next = original
        next.videoRange = "SDR"
        XCTAssertFalse(descriptor.matchesForAutomaticSelection(next))
        next = original
        next.edition = "Theatrical"
        XCTAssertFalse(descriptor.matchesForAutomaticSelection(next))
        next = original
        next.audioProfile = nil
        XCTAssertFalse(descriptor.matchesForAutomaticSelection(next))
        XCTAssertFalse(MediaVersionDescriptor().matchesForAutomaticSelection(original))
    }
}
