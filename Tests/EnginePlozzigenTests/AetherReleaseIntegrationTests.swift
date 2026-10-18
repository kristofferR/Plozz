import AetherEngine
import CoreModels
import FeaturePlayback
import XCTest
@testable import EnginePlozzigen

final class AetherReleaseIntegrationTests: XCTestCase {
    func testResolvedEngineAndSourceCreditIdentifyPinnedDTSXIntegration() throws {
        XCTAssertEqual(AetherEngine.version, "7.36.0")
        let credit = try XCTUnwrap(PlozzAttributions.entries.first { $0.title == "AetherEngine" })
        XCTAssertTrue(credit.detail.contains(
            "https://github.com/brandomoore/AetherEngine/tree/299a3d9ea767e2382158c2a3d137c4b1d302ab4a"
        ))
    }

    func testEngineLivesInItsOwnDynamicFramework() {
        let engineBundle = Bundle(for: AetherEngine.self)
        XCTAssertEqual(engineBundle.bundleURL.lastPathComponent, "AetherEngine.framework")
        XCTAssertNotEqual(engineBundle.bundleURL, Bundle.main.bundleURL)
    }

    func testUpstreamDefaultsRemainOptIn() {
        let options = LoadOptions()
        XCTAssertEqual(options.objectAudioRendering, .off)
        XCTAssertFalse(options.progressiveSegmentDelivery)
    }

    func testPlozzAutomaticallyRequestsSpatialAudioOnSupportedTVOS() {
        for channels in [0, 2, 6, 8] {
            let options = PlozzigenVideoEngine.onDemandLoadOptions(audioChannels: channels)
            #if os(tvOS)
            if #available(tvOS 26.0, *) {
                XCTAssertEqual(options.objectAudioRendering, .apac(.l714))
            } else {
                XCTAssertEqual(options.objectAudioRendering, .off)
            }
            #else
            XCTAssertEqual(options.objectAudioRendering, .off)
            #endif
            XCTAssertEqual(options.audioBridgeMode, channels > 6 ? .lossless : .surroundCompat)
            XCTAssertTrue(options.matchContentEnabled)
            XCTAssertFalse(options.isLive)
            XCTAssertFalse(options.progressiveSegmentDelivery)
        }
    }

    func testSharedLivePlayersAndMutedPreviewsKeepTheOrdinaryAudioBridge() {
        for policy in [
            LiveChannelOutputPolicy(isAudible: false),
            .init(isAudible: true, sharesAudioSession: true),
            .init(isAudible: false, sharesAudioSession: true, suppressesDisplayMatching: true)
        ] {
            let options = PlozzigenVideoEngine.onDemandLoadOptions(audioChannels: 8, outputPolicy: policy)
            XCTAssertEqual(options.objectAudioRendering, .off)
            XCTAssertEqual(options.audioBridgeMode, .lossless)
            XCTAssertEqual(options.suppressDisplayCriteria, policy.suppressesDisplayMatching)
            XCTAssertEqual(options.matchContentEnabled, !policy.suppressesDisplayMatching)
        }
    }

    func testDisablingSpatialAudioKeepsTheExistingChannelBridge() {
        for channels in [0, 2, 6, 8] {
            let options = PlozzigenVideoEngine.onDemandLoadOptions(
                audioChannels: channels, trueHDAtmosEnabled: false
            )
            XCTAssertEqual(options.objectAudioRendering, .off)
            XCTAssertEqual(options.audioBridgeMode, channels > 6 ? .lossless : .surroundCompat)
            XCTAssertTrue(options.matchContentEnabled)
            XCTAssertFalse(options.isLive)
        }
    }

    func testTrueHDLegalCreditIncludesSourceAndBothLicenses() throws {
        let credit = try XCTUnwrap(PlozzAttributions.entries.first { $0.title == "LibTrueHD" })
        XCTAssertTrue(credit.detail.contains(
            "https://github.com/superuser404notfound/LibTrueHD/tree/2.3.0"
        ))
        XCTAssertTrue(credit.detail.contains("Quick104"))
        XCTAssertTrue(credit.detail.contains("Rainbaby"))
        XCTAssertTrue(credit.detail.contains("LibTrueHDNotices.txt"))
        XCTAssertEqual(Set(credit.licenses.map(\.label)), ["MIT", "Apache-2.0"])
    }

    func testDTSXLegalCreditIncludesSourceAndLicense() throws {
        let credit = try XCTUnwrap(PlozzAttributions.entries.first { $0.title == "LibDTSX" })
        XCTAssertTrue(credit.detail.contains(
            "https://github.com/superuser404notfound/LibDTSX/tree/1.0.1"
        ))
        XCTAssertTrue(credit.detail.contains("kristofferR"))
        XCTAssertTrue(credit.detail.contains("harletty"))
        XCTAssertTrue(credit.detail.contains("LibDTSXNotices.txt"))
        XCTAssertTrue(credit.detail.contains("LibDTSXLicense.txt"))
        XCTAssertEqual(credit.licenses.map(\.label), ["Apache-2.0"])
    }

    func testReleasedProbeCancellationAPIIsAvailable() {
        let cancellation = ProbeCancellation()
        XCTAssertFalse(cancellation.isCancelled)
        cancellation.cancel()
        XCTAssertTrue(cancellation.isCancelled)
    }

    func testInformationalRemoteHLSTracksDoNotBecomeNonworkingMenuActions() {
        let tracks = [
            TrackInfo(id: 400_000, name: "English", codec: "aac", language: "en", channels: 2, isDefault: true),
            TrackInfo(id: 400_001, name: "French", codec: "aac", language: "fr", channels: 2, isDefault: false)
        ]
        XCTAssertTrue(PlozzigenVideoEngine.selectableAudioTracks(from: tracks, route: .remoteBypass).isEmpty)
    }

    func testSelectableRoutesKeepAudioTrackIdentityAndFlags() {
        let tracks = [
            TrackInfo(
                id: 3, name: "English", codec: "eac3", language: "en",
                channels: 6, isDefault: true, isCommentary: true, isAtmos: true
            )
        ]
        for route in [VideoRoute.loopback, .software, .audio] {
            let mapped = PlozzigenVideoEngine.selectableAudioTracks(from: tracks, route: route)
            XCTAssertEqual(mapped.map(\.id), [3])
            XCTAssertEqual(mapped.first?.language, "en")
            XCTAssertEqual(mapped.first?.channels, 6)
            XCTAssertEqual(mapped.first?.isAtmos, true)
            XCTAssertEqual(mapped.first?.isCommentary, true)
            XCTAssertEqual(mapped.first?.isDefault, true)
        }
    }
}
