import CoreModels
import XCTest
@testable import FeatureHomeCore

@MainActor
final class PlaybackVersionChoiceTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suite: String!
    private var settings: PlaybackSettingsModel!
    private var preferences: VersionPreferenceStore!
    private var model: PlaybackVersionChoiceModel!

    override func setUp() async throws {
        suite = "version-choice-\(UUID())"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        settings = PlaybackSettingsModel(store: PlaybackSettingsStore(defaults: defaults))
        preferences = VersionPreferenceStore(defaults: defaults)
        model = PlaybackVersionChoiceModel()
    }

    override func tearDown() async throws {
        model.cancel()
        defaults.removePersistentDomain(forName: suite)
    }

    private func item(_ id: String = "movie", series: String? = nil) -> MediaItem {
        MediaItem(
            id: id, title: "Example", kind: series == nil ? .movie : .episode,
            seriesID: series, sourceAccountID: "server",
            versions: [
                .init(id: "\(id)-1080", height: 1080, videoRange: "SDR"),
                .init(id: "\(id)-4k", height: 2160, videoRange: "HDR10")
            ]
        )
    }

    private func start(_ item: MediaItem, isCurrent: @escaping () -> Bool = { true }) -> Task<MediaItem, Error> {
        let model = self.model!
        let settings = self.settings!
        let preferences = self.preferences!
        return Task {
            try await model.prepare(
                item, provider: FakeMediaProvider(allItems: [item]),
                settings: settings, preferences: preferences, isCurrent: isCurrent
            )
        }
    }

    private func pending() async throws -> PlaybackVersionChoiceModel.Prompt {
        let deadline = ContinuousClock.now + .seconds(2)
        while model.prompt == nil, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        return try XCTUnwrap(model.prompt)
    }

    private func assertCancelled(_ task: Task<MediaItem, Error>) async {
        do {
            _ = try await task.value
            XCTFail("A cancelled choice must not start playback.")
        } catch is CancellationError {
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testFirstUseAsksModeThenVersionForBothAnswers() async throws {
        for mode in PlaybackVersionSelectionMode.allCases {
            settings.settings.versionSelectionMode = nil
            let movie = item()
            let task = start(movie)
            defer { task.cancel() }
            let prompt = try await pending()
            XCTAssertTrue(prompt.needsIntroduction)
            model.chooseVersion(movie.versions[1].id, promptID: prompt.id)
            XCTAssertNotNil(model.prompt, "The introduction requires an explicit mode choice.")
            model.chooseMode(mode, promptID: prompt.id)
            XCTAssertEqual(settings.settings.versionSelectionMode, mode)
            XCTAssertFalse(try XCTUnwrap(model.prompt).needsIntroduction)
            model.chooseVersion(movie.versions[1].id, promptID: prompt.id)
            let selected = try await task.value
            XCTAssertEqual(selected.selectedVersionID, movie.versions[1].id)
            XCTAssertEqual(selected.sourceAccountID, "server")
            XCTAssertNil(model.prompt)
        }
    }

    func testAskEveryTimeStillAsksAfterRememberingIncludingNextEpisode() async throws {
        settings.settings.versionSelectionMode = .askEveryTime
        for id in ["episode-1", "episode-1", "episode-2"] {
            let episode = item(id, series: "series")
            let task = start(episode)
            defer { task.cancel() }
            let prompt = try await pending()
            XCTAssertFalse(prompt.needsIntroduction)
            model.chooseVersion(episode.versions[1].id, promptID: prompt.id)
            let selected = try await task.value
            XCTAssertEqual(selected.selectedVersionID, episode.versions[1].id)
        }
    }

    func testRememberedSeriesMatchesDifferentFileIDsButNeverFallsBackToDifferentQuality() async throws {
        settings.settings.versionSelectionMode = .rememberChoice
        let first = item("episode-1", series: "series")
        preferences.rememberVersion(first.versions[1], forTitle: DetailPlaybackSelection.versionPreferenceKey(for: first))
        let next = item("episode-2", series: "series")
        let selected = try await start(next).value
        XCTAssertEqual(selected.selectedVersionID, "episode-2-4k")
        XCTAssertNil(model.prompt)
        var missing = item("episode-3", series: "series")
        missing.versions.removeLast()
        let task = start(missing)
        defer { task.cancel() }
        let prompt = try await pending()
        XCTAssertEqual(prompt.versions.count, 1, "Even a sole remaining fallback needs consent.")
        model.cancel()
        await assertCancelled(task)
        XCTAssertEqual(preferences.preferredVersionDescriptor(forTitle: DetailPlaybackSelection.versionPreferenceKey(for: first))?.height, 2160)
    }

    func testRememberedMovieKeepsExactFileAndNewTitlesAsk() async throws {
        settings.settings.versionSelectionMode = .rememberChoice
        let movie = item()
        preferences.rememberVersion(movie.versions[0], forTitle: DetailPlaybackSelection.versionPreferenceKey(for: movie))
        let selected = try await start(movie).value
        XCTAssertEqual(selected.selectedVersionID, "movie-1080")
        let task = start(item("other"))
        defer { task.cancel() }
        let prompt = try await pending()
        XCTAssertFalse(prompt.needsIntroduction)
        model.cancel()
        await assertCancelled(task)
    }

    func testSingleVersionAndNonVideoDoNotConsumeIntroduction() async throws {
        var movie = item()
        movie.versions.removeLast()
        let selected = try await start(movie).value
        XCTAssertEqual(selected, movie)
        var container = item()
        container.kind = .series
        let bypassed = try await start(container).value
        XCTAssertEqual(bypassed, container)
        XCTAssertNil(settings.settings.versionSelectionMode)
        XCTAssertNil(model.prompt)
    }

    func testCancellationBeforeChoicePersistsNothingAndCanBeAskedAgain() async throws {
        let task = start(item())
        _ = try await pending()
        task.cancel()
        await assertCancelled(task)
        XCTAssertNil(settings.settings.versionSelectionMode)
        XCTAssertNil(model.prompt)
        let second = start(item())
        defer { second.cancel() }
        let prompt = try await pending()
        XCTAssertTrue(prompt.needsIntroduction)
        model.cancel()
        await assertCancelled(second)
    }

    func testCancelAfterModeKeepsModeButDoesNotInventFilePreference() async throws {
        let task = start(item())
        let prompt = try await pending()
        model.chooseMode(.rememberChoice, promptID: prompt.id)
        model.cancel()
        await assertCancelled(task)
        XCTAssertEqual(settings.settings.versionSelectionMode, .rememberChoice)
        XCTAssertNil(preferences.preferredVersionID(forTitle: DetailPlaybackSelection.versionPreferenceKey(for: item())))
    }

    func testStaleProfileAndStalePromptCannotSaveOrStart() async throws {
        var current = true
        let task = start(item(), isCurrent: { current })
        let prompt = try await pending()
        model.chooseMode(.askEveryTime, promptID: UUID())
        XCTAssertNil(settings.settings.versionSelectionMode)
        current = false
        model.chooseMode(.rememberChoice, promptID: prompt.id)
        await assertCancelled(task)
        XCTAssertNil(settings.settings.versionSelectionMode)
    }

    func testSettingsChoiceSkipsIntroductionAndCanChangeBetweenPlays() async throws {
        let movie = item()
        preferences.rememberVersion(movie.versions[1], forTitle: DetailPlaybackSelection.versionPreferenceKey(for: movie))
        settings.settings.versionSelectionMode = .rememberChoice
        let remembered = try await start(movie).value
        XCTAssertEqual(remembered.selectedVersionID, "movie-4k")
        settings.settings.versionSelectionMode = .askEveryTime
        let task = start(movie)
        defer { task.cancel() }
        let prompt = try await pending()
        XCTAssertFalse(prompt.needsIntroduction)
        model.cancel()
        await assertCancelled(task)
    }

    func testProfileInvalidationDuringFileChoiceCannotSavePreference() async throws {
        var current = true
        settings.settings.versionSelectionMode = .rememberChoice
        let movie = item()
        let task = start(movie, isCurrent: { current })
        let prompt = try await pending()
        current = false
        model.chooseVersion("movie-4k", promptID: prompt.id)
        await assertCancelled(task)
        XCTAssertNil(preferences.preferredVersionID(forTitle: DetailPlaybackSelection.versionPreferenceKey(for: movie)))
    }

    func testOfflineLightweightItemNeverRequiresServerDetails() async throws {
        struct Local: OfflinePlaybackResolving {
            func localPlaybackURL(for item: MediaItem, versionID: String?) async -> URL? {
                URL(fileURLWithPath: "/fixture/download.mkv")
            }
        }
        var movie = item()
        movie.versions = []
        let provider = FakeMediaProvider(allItems: [])
        let selected = try await model.prepare(
            movie, provider: provider, settings: settings, preferences: preferences,
            offlineResolver: Local()
        )
        XCTAssertEqual(selected, movie)
        XCTAssertEqual(provider.itemCallCount(for: movie.id), 0)
        XCTAssertNil(settings.settings.versionSelectionMode)
    }

    func testUnknownVersionsAreLoadedBeforeTheGateForBothServerKinds() async throws {
        for kind in [ProviderKind.jellyfin, .plex, .emby, .silo] {
            let full = item()
            var lightweight = full
            lightweight.versions = []
            let provider = FakeMediaProvider(allItems: [full], kind: kind)
            let task = Task {
                try await model.prepare(lightweight, provider: provider, settings: settings, preferences: preferences)
            }
            defer { task.cancel() }
            let prompt = try await pending()
            XCTAssertTrue(prompt.needsIntroduction)
            XCTAssertEqual(provider.itemCallCount(for: full.id), 1)
            model.cancel()
            await assertCancelled(task)
        }
    }

    func testDetailFailureIsAnErrorNotDefaultPlayback() async throws {
        var lightweight = item()
        lightweight.versions = []
        do {
            _ = try await model.prepare(
                lightweight, provider: FakeMediaProvider(allItems: []),
                settings: settings, preferences: preferences
            )
            XCTFail("Missing version details must not silently select a default.")
        } catch let error as AppError {
            XCTAssertEqual(error, .notFound)
        }
        XCTAssertNil(model.prompt)
        XCTAssertNil(settings.settings.versionSelectionMode)
    }

    func testCombinedEditionsRetainRawProviderIDsAndRejectForeignAccounts() async throws {
        settings.settings.versionSelectionMode = .askEveryTime
        let first = item()
        var extended = item("extended")
        extended.edition = "Extended"
        var foreign = first
        foreign.sourceAccountID = "foreign"
        var combined = first
        combined.sources = [first, extended, foreign].map {
            MediaSourceRef(accountID: $0.sourceAccountID!, itemID: $0.id, kind: $0.kind, versions: $0.versions)
        }
        let task = start(combined)
        defer { task.cancel() }
        let prompt = try await pending()
        XCTAssertTrue(prompt.versions.allSatisfy { $0.sourceAccountID == "server" })
        let version = try XCTUnwrap(prompt.versions.first { $0.sourceItemID == "extended" })
        model.chooseVersion(version.id, promptID: prompt.id)
        let selected = try await task.value
        XCTAssertEqual(selected.id, "extended")
        XCTAssertEqual(selected.sourceAccountID, "server")
        XCTAssertEqual(selected.selectedVersionID, version.playbackMediaSourceID)
        XCTAssertNotEqual(selected.selectedVersionID, version.id)
    }
}
