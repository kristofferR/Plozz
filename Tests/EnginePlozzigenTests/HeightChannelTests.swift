@testable import AetherEngine
import CoreModels
import FeaturePlayback
import XCTest
@testable import EnginePlozzigen

@MainActor
final class HeightChannelTests: XCTestCase {
    func testHeightChannelComponentsAreLinked() {
        XCTAssertTrue(AetherEngine.OptionalComponent.trueHDObjectAudio.isBuiltIn)
        XCTAssertTrue(AetherEngine.OptionalComponent.dtsxObjectAudio.isBuiltIn)
    }

    func testAudiblePlaybackRendersTheChosenLayout() {
        XCTAssertEqual(HeightChannelLayout.allCases.count, SpatialSpeakerLayout.allCases.count)
        for layout in HeightChannelLayout.allCases {
            XCTAssertEqual(PlozzigenVideoEngine.speakerLayout(layout).rawValue, layout.rawValue)
            let options = PlozzigenVideoEngine.requestingHeightChannels(
                LoadOptions(), outputPolicy: .init(), layout: layout
            )
            assertRendering(options, layout: layout)
        }
    }

    func testOffOrIneligibleOutputKeepsOrdinaryChannelAudio() {
        let off = PlozzigenVideoEngine.requestingHeightChannels(LoadOptions(), outputPolicy: .init(), layout: nil)
        XCTAssertEqual(off.objectAudioRendering, .off)
        for policy in [
            LiveChannelOutputPolicy(isAudible: false),
            .init(isAudible: true, sharesAudioSession: true)
        ] {
            let options = PlozzigenVideoEngine.requestingHeightChannels(
                LoadOptions(), outputPolicy: policy, layout: .default
            )
            XCTAssertEqual(options.objectAudioRendering, .off)
        }
    }

    func testStoreDefaultsOnAndFollowsTheToggleAndLayout() throws {
        let suite = "HeightChannelTests.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = HeightChannelSettingsStore(defaults: defaults)
        XCTAssertEqual(store.renderingLayout(), .nineOneSix)
        defaults.set("7.1.4", forKey: HeightChannelSettingsStore.layoutKey)
        XCTAssertEqual(store.renderingLayout(), .sevenOneFour)
        defaults.set("11.1.8", forKey: HeightChannelSettingsStore.layoutKey)
        XCTAssertEqual(store.renderingLayout(), .nineOneSix)
        defaults.set(false, forKey: HeightChannelSettingsStore.enabledKey)
        XCTAssertNil(store.renderingLayout())
    }

    func testOnDemandLoadsUseTheDevicePreference() throws {
        let defaults = UserDefaults.standard
        let keys = [HeightChannelSettingsStore.enabledKey, HeightChannelSettingsStore.layoutKey]
        let saved = keys.map { defaults.object(forKey: $0) }
        defer { zip(keys, saved).forEach { defaults.set($1, forKey: $0) } }
        let engine = try PlozzigenVideoEngine()
        defer { engine.stop() }
        let request = PlaybackRequest(
            item: MediaItem(id: "movie", title: "Fixture", kind: .movie),
            streamURL: URL(string: "https://example.invalid/movie.mkv")!
        )

        defaults.set(true, forKey: HeightChannelSettingsStore.enabledKey)
        defaults.set("7.1.4", forKey: HeightChannelSettingsStore.layoutKey)
        assertRendering(engine.onDemandLoadOptions(for: request), layout: .sevenOneFour)
        defaults.set(false, forKey: HeightChannelSettingsStore.enabledKey)
        XCTAssertEqual(engine.onDemandLoadOptions(for: request).objectAudioRendering, .off)
    }

    private func assertRendering(
        _ options: LoadOptions, layout: HeightChannelLayout,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        #if os(tvOS) || os(iOS)
        if #available(tvOS 26.0, iOS 26.0, *) {
            XCTAssertEqual(
                options.objectAudioRendering, .render(PlozzigenVideoEngine.speakerLayout(layout)),
                file: file, line: line
            )
            return
        }
        #endif
        XCTAssertEqual(options.objectAudioRendering, .off, file: file, line: line)
    }
}
