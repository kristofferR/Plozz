import CoreModels
import CoreNetworking
import CoreTrackerAuth
import Foundation
import XCTest
@testable import WetrakrService
@testable import TestSupportNetworking

private let config = WetrakrConfig(clientID: "test-client")
private let tokenJSON = #"{"access_token":"access","refresh_token":"refresh","expires_in":604800,"token_type":"bearer"}"#
private let pageHeaders = ["X-Pagination-Page-Count": "1"]

private func store() -> InMemoryTrackerTokenStore {
    InMemoryTrackerTokenStore(tokens: .init(
        accessToken: "access", refreshToken: "refresh",
        expiresAt: Date().addingTimeInterval(604800), accountIdentity: "viewer-one"
    ))
}

final class WetrakrAuthorizationTests: XCTestCase {
    func testConfigurationRejectsUnexpandedSettingsAndUsesEnvironment() {
        XCTAssertFalse(WetrakrConfig(clientID: "$(WETRAKR_CLIENT_ID)").isConfigured)
        XCTAssertFalse(WetrakrConfig(clientID: "  ").isConfigured)
        XCTAssertEqual(WetrakrConfig.resolved(
            environment: ["WETRAKR_CLIENT_ID": "configured"],
            featureFlags: .init(enabled: [.wetrakr])
        ).clientID, "configured")
    }

    @MainActor
    func testProductionRolloutDisablesSavedConnectionsWithoutRequestsOrErasure() async throws {
        XCTAssertFalse(RuntimeFeatureFlags.productionDefault.isEnabled(.wetrakr))
        XCTAssertTrue(RuntimeFeatureFlags.productionDefault.isEnabled(.universalWatchlist))
        let disabled = WetrakrConfig.resolved(environment: ["WETRAKR_CLIENT_ID": "configured"])
        XCTAssertFalse(disabled.isConfigured)
        XCTAssertNil(disabled.clientID)
        let http = RecordingHTTPClient()
        let tokens = store()
        let saved = tokens.load()
        let service = WetrakrService(config: disabled, http: http, tokenStore: tokens, coordinator: .init())

        await service.refreshStatus()
        await service.setActiveProfile(namespace: nil)
        service.connect()
        await service.connectTask?.value
        service.connect { _, _ in
            XCTFail("Disabled integration must not open browser authorization")
            throw CancellationError()
        }
        await service.connectTask?.value
        XCTAssertEqual(service.phase, .unavailable)
        XCTAssertFalse(service.isConfigured)
        XCTAssertNil(service.accountIdentity)
        XCTAssertNil(service.watchlistDestination)

        let scrobbler = service.playbackScrobbler()
        let item = MediaItem(id: "movie", title: "Movie", kind: .movie, providerIDs: ["Imdb": "tt1234567"])
        XCTAssertNil(scrobbler.accountIdentity)
        await scrobbler.scrobble(item: item, progress: 50, event: .start)
        try await scrobbler.recordWatch(
            item: item, capturedAt: Date(), idempotencyKey: "disabled-watch",
            expectedAccountIdentity: "viewer-one"
        )
        XCTAssertTrue(http.sent.isEmpty)
        XCTAssertEqual(tokens.load(), saved)
    }

    func testPKCEUsesRegisteredCallbackAndValidatesState() throws {
        let pkce = try TrackerPKCE(
            clientID: config.clientID,
            authorizationEndpoint: config.apiBaseURL.appendingPathComponent("oauth/authorize"),
            redirectURI: config.redirectURI,
            verifier: "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk", state: "expected"
        )
        let parts = try XCTUnwrap(URLComponents(url: pkce.authorizationURL, resolvingAgainstBaseURL: false))
        XCTAssertEqual(parts.host, "api.wetrakr.com")
        XCTAssertEqual(parts.queryItems?.first(where: { $0.name == "code_challenge" })?.value,
                       "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")
        XCTAssertNil(parts.queryItems?.first(where: { $0.name == "client_secret" }))
        for suffix in ["", "#"] {
            XCTAssertEqual(try pkce.authorizationCode(from: XCTUnwrap(
                URL(string: config.redirectURI.absoluteString + "?code=approved&state=expected" + suffix)
            )), "approved")
        }
        XCTAssertThrowsError(try pkce.authorizationCode(from: XCTUnwrap(
            URL(string: "https://plozz.app/auth/trakt/callback?code=approved&state=expected")
        )))
    }

    func testOAuthShapesHeadersAndSecretlessRefresh() async throws {
        let http = RecordingHTTPClient()
        http.stub(pathSuffix: "/oauth/token", json: tokenJSON)
        http.stub(pathSuffix: "/oauth/token/refresh", json: tokenJSON)
        http.stub(pathSuffix: "/account/settings", json: #"{"id":42,"info":{"username":"viewer"}}"#)
        http.stub(pathSuffix: "/oauth/logout", json: #"{"revoked":true}"#)
        let auth = WetrakrAuthService(client: .init(config: config, http: http, gate: WetrakrRequestGate()))
        let tokens = try await auth.exchange(code: "approved", verifier: "verifier")
        _ = try await auth.refresh(tokens.refreshToken)
        _ = try await auth.user(accessToken: tokens.accessToken)
        try await auth.revoke(tokens)
        XCTAssertEqual(http.sentPaths, ["/oauth/token", "/oauth/token/refresh", "/account/settings", "/oauth/logout"])
        for request in http.sent {
            XCTAssertEqual(request.baseURL, config.apiBaseURL)
            XCTAssertEqual(request.headers["wetrakr-api-key"], "test-client")
            XCTAssertEqual(request.headers["wetrakr-api-version"], "1")
            XCTAssertNil(request.json?["client_secret"])
        }
        XCTAssertEqual(http.sent[0].json?["code_verifier"] as? String, "verifier")
        XCTAssertEqual(http.sent[1].json?["refresh_token"] as? String, "refresh")
        XCTAssertEqual(http.sent[3].headers["Authorization"], "Bearer access")
        XCTAssertTrue(tokens.expiresAt > Date().addingTimeInterval(600000))
    }

    func testCallbackFailureReasonsContainNoReturnedValues() throws {
        let pkce = try TrackerPKCE(
            clientID: config.clientID,
            authorizationEndpoint: config.apiBaseURL.appendingPathComponent("oauth/authorize"),
            redirectURI: config.redirectURI, state: "expected"
        )
        let base = config.redirectURI.absoluteString
        let cases: [(String, TrackerPKCE.CallbackError)] = [
            ("https://other.example/callback?code=private-code&state=expected", .unexpectedHost),
            ("http://plozz.app/auth/wetrakr/callback?code=private-code&state=expected", .unexpectedScheme),
            ("https://plozz.app:443/auth/wetrakr/callback?code=private-code&state=expected", .unexpectedPort),
            ("https://plozz.app/auth/wetrakr/callback/?code=private-code&state=expected", .unexpectedPath),
            ("https://user@plozz.app/auth/wetrakr/callback?code=private-code&state=expected", .unexpectedUserInfo),
            (base + "?code=private-code&state=expected#fragment", .unexpectedFragment),
            (base + "?code=private-code", .invalidState),
            (base + "?code=private-code&state=private-state", .invalidState),
            (base + "?code=private-code&state=private-state#", .invalidState),
            (base + "?code=private-code&state=expected&state=expected", .invalidState),
            (base + "?state=expected", .invalidCode),
            (base + "?state=expected&code=", .invalidCode),
            (base + "?state=expected&code=one&code=two", .invalidCode),
            (base + "?state=expected&code=one&code=two#", .invalidCode),
        ]
        for (url, expected) in cases {
            XCTAssertThrowsError(try pkce.authorizationCode(from: XCTUnwrap(URL(string: url)))) {
                XCTAssertEqual($0 as? TrackerPKCE.CallbackError, expected)
                XCTAssertFalse(String(describing: $0).contains("private"))
            }
        }
    }

    @MainActor
    func testBrowserAndCallbackFailuresAreDistinctAndNeverExchangeOrSave() async throws {
        let cases: [(browserFailure: Bool, message: LocalizedStringResource)] = [
            (true, "The sign-in browser couldn't return to Plozz. Please try again."),
            (false, "WeTrakr returned a missing or mismatched sign-in security token. Please try again."),
        ]
        for (browserFailure, message) in cases {
            let http = RecordingHTTPClient()
            let tokens = InMemoryTrackerTokenStore()
            let service = WetrakrService(config: config, http: http, tokenStore: tokens, coordinator: .init())
            service.connect { _, callback in
                if browserFailure { throw AppError.invalidResponse }
                return try XCTUnwrap(URL(string: callback.absoluteString + "?code=private-code&state=wrong"))
            }
            await service.connectTask?.value
            XCTAssertEqual(service.phase, .error(message))
            XCTAssertTrue(http.sent.isEmpty)
            XCTAssertNil(tokens.load())
        }
    }

    @MainActor
    func testCodeExchangeFailuresAreDistinctAndDoNotRetryOrSave() async throws {
        let cases: [(status: Int, json: String, message: LocalizedStringResource)] = [
            (400, #"{"message":"Invalid authorization code"}"#,
             "WeTrakr rejected the sign-in code. Please start sign-in again."),
            (200, "{}",
             "WeTrakr couldn't complete the sign-in exchange. Please try again."),
            (200, #"{"access_token":"","refresh_token":"refresh","expires_in":604800,"token_type":"bearer"}"#,
             "WeTrakr couldn't complete the sign-in exchange. Please try again."),
        ]
        for (status, json, message) in cases {
            let http = RecordingHTTPClient()
            http.stub(pathSuffix: "/oauth/token", json: json, status: status)
            let tokens = InMemoryTrackerTokenStore()
            let service = WetrakrService(config: config, http: http, tokenStore: tokens, coordinator: .init())
            service.connect { url, callback in try Self.approvedCallback(url: url, callback: callback) }
            await service.connectTask?.value
            XCTAssertEqual(service.phase, .error(message))
            XCTAssertEqual(http.sentPaths, ["/oauth/token"])
            XCTAssertNil(tokens.load())
        }
    }

    @MainActor
    func testValidBrowserReturnExchangesOnceAndSavesConnection() async throws {
        for suffix in ["", "#"] {
            let http = RecordingHTTPClient()
            http.stub(pathSuffix: "/oauth/token", json: tokenJSON)
            http.stub(pathSuffix: "/account/settings", json: #"{"id":42,"info":{"username":"viewer"}}"#)
            let tokens = InMemoryTrackerTokenStore()
            let service = WetrakrService(config: config, http: http, tokenStore: tokens, coordinator: .init())
            service.connect { url, callback in
                let approved = try Self.approvedCallback(url: url, callback: callback)
                return try XCTUnwrap(URL(string: approved.absoluteString + suffix))
            }
            await service.connectTask?.value
            XCTAssertEqual(service.phase, .connected(username: "viewer"))
            XCTAssertEqual(http.sentPaths, ["/oauth/token", "/account/settings"])
            XCTAssertEqual(http.sent.first?.json?["code"] as? String, "approved")
            XCTAssertEqual((http.sent.first?.json?["code_verifier"] as? String)?.count, 43)
            XCTAssertEqual(tokens.load()?.accessToken, "access")
            XCTAssertNotNil(tokens.load()?.accountIdentity)
        }
    }

    private static func approvedCallback(url: URL, callback: URL) throws -> URL {
        let state = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?.first(where: { $0.name == "state" })?.value)
        return try XCTUnwrap(URL(string: callback.absoluteString + "?code=approved&state=\(state)"))
    }

    func testOnlyExplicitAuthorizationPendingKeepsPolling() async throws {
        let http = RecordingHTTPClient()
        http.stub(pathSuffix: "/oauth/device/token", json: #"{"error":"authorization_pending"}"#, status: 400)
        http.stub(pathSuffix: "/oauth/device/token", json: tokenJSON)
        let auth = WetrakrAuthService(
            client: .init(config: config, http: http, gate: WetrakrRequestGate()), sleep: { _ in }
        )
        let code = try JSONDecoder().decode(WetrakrDeviceCode.self, from: Data("""
        {"device_code":"device","user_code":"ABC123","verification_url":"https://wetrakr.com/activate","expires_in":600,"interval":5}
        """.utf8))
        _ = try await auth.awaitToken(for: code)
        XCTAssertEqual(http.sent.count, 2)
        XCTAssertEqual(http.sent[0].json?["code"] as? String, "device")
        XCTAssertNil(http.sent[0].json?["device_code"])
        for status in [400, 401, 404, 409, 410, 418, 500] {
            let terminal = RecordingHTTPClient()
            terminal.stub(pathSuffix: "/oauth/device/token", json: #"{"error":"invalid_request"}"#, status: status)
            let terminalAuth = WetrakrAuthService(
                client: .init(config: config, http: terminal, gate: WetrakrRequestGate()), sleep: { _ in }
            )
            do { _ = try await terminalAuth.awaitToken(for: code); XCTFail("Expected terminal failure") }
            catch { XCTAssertEqual(terminal.sent.count, 1) }
        }
    }

    func testRateLimitStopsOtherRequestsWithoutSendingAgain() async {
        let http = RecordingHTTPClient()
        http.stub(pathSuffix: "/account/settings", json: "{}", status: 429, headers: ["Retry-After": "120"])
        let client = WetrakrClient(config: config, http: http, gate: WetrakrRequestGate())
        for _ in 0..<2 {
            do { _ = try await client.send(Endpoint(path: "/account/settings")); XCTFail("Expected throttle") }
            catch AppError.rateLimited(let delay) { XCTAssertGreaterThan(delay ?? 0, 100) }
            catch { XCTFail("Unexpected error \(error)") }
        }
        XCTAssertEqual(http.sent.count, 1)
    }

    func testForbiddenRequestDoesNotMasqueradeAsExpiredSignIn() async {
        let http = RecordingHTTPClient()
        http.stub(pathSuffix: "/account/settings", json: #"{"status":403,"detail":"Request blocked"}"#, status: 403)
        let client = WetrakrClient(config: config, http: http, gate: WetrakrRequestGate())
        do { _ = try await client.send(Endpoint(path: "/account/settings")); XCTFail("Expected rejection") }
        catch { XCTAssertEqual(error as? WetrakrError, .requestBlocked) }
    }

    @MainActor
    func testBrowserCancellationRestoresExistingConnectionWithoutReplacingGrant() async throws {
        let http = RecordingHTTPClient()
        http.stub(pathSuffix: "/account/settings", json: #"{"id":42,"info":{"username":"viewer"}}"#)
        let tokens = store()
        let original = tokens.load()
        let service = WetrakrService(config: config, http: http, tokenStore: tokens, coordinator: .init())
        await service.refreshStatus()
        XCTAssertEqual(service.phase, .connected(username: "viewer"))
        let restored = expectation(description: "Existing connection restored")
        service.onConnectionChanged = { restored.fulfill() }
        service.connect { _, _ in throw CancellationError() }
        await fulfillment(of: [restored], timeout: 3)
        XCTAssertEqual(service.phase, .connected(username: "viewer"))
        XCTAssertEqual(tokens.load(), original)
        XCTAssertEqual(http.sentPaths, ["/account/settings", "/account/settings"])
    }
}

final class WetrakrScrobblingTests: XCTestCase {
    func testEpisodePayloadUsesExplicitSeriesIDsAndSupportsSpecials() throws {
        let item = MediaItem(
            id: "episode", title: "Special", kind: .episode,
            seasonNumber: 0, episodeNumber: 1,
            providerIDs: ["Tmdb": "111", "SeriesTmdb": "222"]
        )
        let realtime = try XCTUnwrap(WetrakrScrobbler.body(for: item, progress: 95))
        XCTAssertEqual(realtime.show?.ids?.tmdb, 222)
        XCTAssertNil(realtime.episode?.id)
        XCTAssertEqual(realtime.episode?.season, 0)
        let history = try XCTUnwrap(WetrakrScrobbler.historyBody(for: item, capturedAt: Date(timeIntervalSince1970: 1000)))
        XCTAssertEqual(history.shows?.first?.ids?.tmdb, 222)
        XCTAssertEqual(history.shows?.first?.seasons?.first?.episodes?.first?.number, 1)
        XCTAssertEqual(history.shows?.first?.seasons?.first?.episodes?.first?.trackedAt, "1970-01-01T00:16:40.000Z")
        XCTAssertEqual(history.allowRewatch, true)
    }

    func testNoEpisodeIdentityGuessAndNoLiveTVScrobble() {
        let episode = MediaItem(id: "episode", title: "Episode", kind: .episode, seasonNumber: 1, episodeNumber: 1, providerIDs: ["Tmdb": "111"])
        XCTAssertNil(WetrakrScrobbler.body(for: episode, progress: 90))
        XCTAssertNil(WetrakrScrobbler.body(for: MediaItem(id: "series", title: "Series", kind: .series), progress: 90))
        XCTAssertNil(WetrakrScrobbler.body(for: MediaItem(id: "movie", title: "Movie", kind: .movie, providerIDs: ["Tmdb": "1"]), progress: .nan))
    }

    func testScrobblingSendsNinetyPercentThresholdAndSkipsClockTicks() async throws {
        let http = RecordingHTTPClient()
        http.stub(pathSuffix: "/scrobble/start", json: #"{"action":"start","progress":50}"#, status: 201)
        let scrobbler = WetrakrScrobbler(client: .init(config: config, http: http), tokenStore: store(), coordinator: .init())
        let item = MediaItem(id: "movie", title: "Movie", kind: .movie, providerIDs: ["Tmdb": "1"])
        await scrobbler.scrobble(item: item, progress: 50, event: .start)
        await scrobbler.scrobble(item: item, progress: 60, event: .progress)
        XCTAssertEqual(http.sent.count, 1)
        XCTAssertEqual(http.sent.first?.queryItems.first(where: { $0.name == "min_progress" })?.value, "90")
    }

    func testDurableWatchUsesOriginalTimestampAndStableRetryKey() async throws {
        let http = RecordingHTTPClient()
        http.stub(pathSuffix: "/sync/tracking", json: #"{"added":{"watched":{"movies":1}}}"#)
        let scrobbler = WetrakrScrobbler(client: .init(config: config, http: http), tokenStore: store(), coordinator: .init())
        let item = MediaItem(id: "movie", title: "Movie", kind: .movie, providerIDs: ["Tmdb": "1"])
        for _ in 0..<2 {
            try await scrobbler.recordWatch(item: item, capturedAt: Date(timeIntervalSince1970: 1000),
                                           idempotencyKey: "durable-id", expectedAccountIdentity: "viewer-one")
        }
        XCTAssertEqual(http.sent.count, 2)
        for request in http.sent {
            XCTAssertEqual(request.headers["Idempotency-Key"], "durable-id")
            let movies = request.json?["movies"] as? [[String: Any]]
            XCTAssertEqual(movies?.first?["tracked_at"] as? String, "1970-01-01T00:16:40.000Z")
            XCTAssertEqual(request.json?["allow_rewatch"] as? Bool, true)
        }
    }

    func testHTTP200PartialFailureIsNotSuccessAndKnownDuplicateIsSafe() throws {
        for payload in [
            #"{"added":{"total":0},"notFound":{"movies":[{"ids":{"tmdb":1}}]}}"#,
            #"{"added":{"total":0},"errored":{"movies":[{"error":"Status rejected"}]}}"#,
            #"{"added":{},"removed":{},"existing":{}}"#,
            #"{"added":{"total":0,"watched":{"movies":0,"shows":0,"episodes":0}}}"#,
            "{}",
        ] {
            let result = try JSONDecoder().decode(WetrakrTrackingResult.self, from: Data(payload.utf8))
            XCTAssertThrowsError(try result.validate(allowDuplicateWatch: true))
        }
        let duplicate = try JSONDecoder().decode(WetrakrTrackingResult.self, from: Data(
            #"{"errored":{"movies":[{"error":"Already added!"}]}}"#.utf8
        ))
        XCTAssertNoThrow(try duplicate.validate(allowDuplicateWatch: true))
        XCTAssertThrowsError(try duplicate.validate(allowDuplicateWatch: false))
    }

    func testPlanningWritesNeedPositiveEvidenceOrConfirmedAbsence() throws {
        let existing = try JSONDecoder().decode(WetrakrTrackingResult.self, from: Data(
            #"{"existing":{"planning":{"movies":1}}}"#.utf8
        ))
        XCTAssertNoThrow(try existing.validate(allowDuplicateWatch: false))
        XCTAssertThrowsError(try existing.validate(allowDuplicateWatch: false, removing: true))
        let absent = try JSONDecoder().decode(WetrakrTrackingResult.self, from: Data(
            #"{"errored":{"movies":[{"error":"Nothing to remove"}]}}"#.utf8
        ))
        XCTAssertNoThrow(try absent.validate(allowDuplicateWatch: false, removing: true))
        XCTAssertThrowsError(try absent.validate(allowDuplicateWatch: false))
    }

    func testReconnectDoesNotSendAnOldPlaybackOrQueuedWatchToNewAccount() async throws {
        let http = RecordingHTTPClient()
        let tokens = store()
        let scrobbler = WetrakrScrobbler(client: .init(config: config, http: http), tokenStore: tokens, coordinator: .init())
        try tokens.save(.init(accessToken: "other", refreshToken: "other", expiresAt: .distantFuture, accountIdentity: "viewer-two"))
        let item = MediaItem(id: "movie", title: "Movie", kind: .movie, providerIDs: ["Tmdb": "1"])
        await scrobbler.scrobble(item: item, progress: 50, event: .start)
        try await scrobbler.recordWatch(item: item, capturedAt: Date(), idempotencyKey: "old", expectedAccountIdentity: "viewer-one")
        XCTAssertTrue(http.sent.isEmpty)
    }
}

final class WetrakrWatchlistTests: XCTestCase {
    func testNativeOnlyIdentitySurvivesPersistenceAndCanBeRemoved() async throws {
        let http = RecordingHTTPClient()
        http.stub(pathSuffix: "/sync/last_activities", json: #"{"journal_visible_until":"2026-10-01T00:00:00Z"}"#)
        http.stub(pathSuffix: "/sync/tracking/planning/all", json: #"[{"id":42,"type":"movie","title":"Native movie"}]"#, headers: pageHeaders)
        http.stub(pathSuffix: "/sync/tracking/remove", json: #"{"removed":{"planning":{"movies":1}}}"#)
        let destination = WetrakrWatchlistDestination(
            client: .init(config: config, http: http), tokenStore: store(), coordinator: .init(), generation: .init()
        )
        let fetched = try await destination.fetchEntries()
        let entry = try XCTUnwrap(fetched.first)
        let restored = try JSONDecoder().decode(WatchlistDestinationEntry.self, from: JSONEncoder().encode(entry))
        XCTAssertEqual(restored.externalIDs, [WatchlistExternalID(namespace: .wetrakr, value: "42")!])
        XCTAssertEqual(restored.mediaAliasEvidence?.strong, [.init(kind: .movie, namespace: .wetrakr, value: "42")!])
        let item = MediaItem(id: "placeholder", title: "Native movie", kind: .movie, providerIDs: ["Wetrakr": "42"])
        XCTAssertEqual(MediaAliasEvidence(item: item)?.strong, restored.mediaAliasEvidence?.strong)
        let target = try XCTUnwrap(WatchlistMutationTarget(aliasID: MediaAliasID(), item: item))
        let resolved = try await destination.resolve(target)
        let binding = try XCTUnwrap(resolved)
        try await destination.apply(.absent, to: binding)
        let movies = http.sent.last?.json?["movies"] as? [[String: Any]]
        XCTAssertEqual(movies?.first?["id"] as? Int, 42)
        XCTAssertNil(movies?.first?["ids"])
    }

    func testCacheAndIncrementalPlanningRemovalWithoutFullRefetch() async throws {
        let http = RecordingHTTPClient()
        let clock = TestClock()
        let destination = WetrakrWatchlistDestination(
            client: .init(config: config, http: http), tokenStore: store(),
            coordinator: .init(), generation: .init(), now: { clock.now }
        )
        http.stub(pathSuffix: "/sync/last_activities", json: #"{"all":"2026-10-01T00:00:00.000Z","journal_visible_until":"2026-10-01T00:00:01.000Z"}"#)
        http.stub(pathSuffix: "/sync/last_activities", json: #"{"all":"2026-10-01T00:02:00.000Z","journal_visible_until":"2026-10-01T00:02:01.000Z"}"#)
        http.stub(pathSuffix: "/sync/tracking/planning/all", json: #"[{"id":42,"type":"movie","title":"Movie","ids":{"tmdb":1}}]"#, headers: pageHeaders)
        let first = try await destination.fetchEntries()
        XCTAssertEqual(first.count, 1)
        XCTAssertEqual(first.first?.attribution?.source, .wetrakr)
        XCTAssertEqual(first.first?.attribution?.sourceURL?.absoluteString, "https://wetrakr.com/movies/42")
        _ = try await destination.fetchEntries()
        XCTAssertEqual(http.sent.count, 2)
        clock.advance()
        http.stub(pathSuffix: "/sync/journal", json: """
        {"visible_until":"2026-10-01T00:02:01.000Z","journal":[
        {"entry_id":"change","category":"planning","status":"removed","action_at":"2026-10-01T00:02:00.000Z","type":"movie","id":42,"ids":{"tmdb":1}}]}
        """, headers: pageHeaders)
        let second = try await destination.fetchEntries()
        XCTAssertTrue(second.isEmpty)
        XCTAssertEqual(http.sentPaths.filter { $0 == "/sync/tracking/planning/all" }.count, 1)
        XCTAssertEqual(http.sent.last?.queryItems.first(where: { $0.name == "from_date" })?.value, "2026-09-30T23:59:56.000Z")
    }

    func testMissingPaginationCannotPublishPartialList() async {
        let http = RecordingHTTPClient()
        http.stub(pathSuffix: "/sync/last_activities", json: #"{"journal_visible_until":"2026-10-01T00:00:00Z"}"#)
        http.stub(pathSuffix: "/sync/tracking/planning/all", json: "[]")
        let destination = WetrakrWatchlistDestination(
            client: .init(config: config, http: http), tokenStore: store(), coordinator: .init(), generation: .init()
        )
        do { _ = try await destination.fetchEntries(); XCTFail("Incomplete response must fail") }
        catch { XCTAssertEqual(error as? WatchlistDestinationError, .transient) }
    }

    func testInvisibleJournalActivityIsNotMarkedConsumed() async throws {
        let http = RecordingHTTPClient()
        let clock = TestClock()
        let destination = WetrakrWatchlistDestination(
            client: .init(config: config, http: http), tokenStore: store(),
            coordinator: .init(), generation: .init(), now: { clock.now }
        )
        http.stub(pathSuffix: "/sync/last_activities", json: #"{"all":"2026-10-01T00:00:05Z","journal_visible_until":"2026-10-01T00:00:01Z"}"#)
        http.stub(pathSuffix: "/sync/tracking/planning/all", json: "[]", headers: pageHeaders)
        _ = try await destination.fetchEntries()
        clock.advance()
        http.stub(pathSuffix: "/sync/journal", json: #"{"visible_until":"2026-10-01T00:00:01Z","journal":[]}"#, headers: pageHeaders)
        http.stub(pathSuffix: "/sync/journal", json: #"{"visible_until":"2026-10-01T00:00:06Z","journal":[{"entry_id":"new","category":"planning","status":"added","action_at":"2026-10-01T00:00:05Z","type":"movie","id":42,"title":"Movie","ids":{"tmdb":1}}]}"#, headers: pageHeaders)
        _ = try await destination.fetchEntries()
        clock.advance()
        let entries = try await destination.fetchEntries()
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(http.sentPaths.filter { $0 == "/sync/journal" }.count, 2)
    }

    func testExpiredJournalPerformsFullResync() async throws {
        let http = RecordingHTTPClient()
        let clock = TestClock()
        let destination = WetrakrWatchlistDestination(
            client: .init(config: config, http: http), tokenStore: store(),
            coordinator: .init(), generation: .init(), now: { clock.now }
        )
        http.stub(pathSuffix: "/sync/last_activities", json: #"{"journal_visible_until":"2026-10-01T00:00:01Z"}"#)
        http.stub(pathSuffix: "/sync/tracking/planning/all", json: "[]", headers: pageHeaders)
        _ = try await destination.fetchEntries()
        clock.advance()
        http.stub(pathSuffix: "/sync/journal", json: #"{"error":"JOURNAL_EXPIRED"}"#, status: 400)
        _ = try await destination.fetchEntries()
        XCTAssertEqual(http.sentPaths.filter { $0 == "/sync/tracking/planning/all" }.count, 2)
    }

    func testNewConnectionCannotReuseThePreviousAccountsCache() async throws {
        let http = RecordingHTTPClient()
        let tokens = store()
        let destination = WetrakrWatchlistDestination(
            client: .init(config: config, http: http), tokenStore: tokens,
            coordinator: .init(), generation: .init()
        )
        http.stub(pathSuffix: "/sync/last_activities", json: #"{"journal_visible_until":"2026-10-01T00:00:01Z"}"#)
        http.stub(pathSuffix: "/sync/tracking/planning/all", json: #"[{"id":42,"type":"movie","title":"Old","ids":{"tmdb":1}}]"#, headers: pageHeaders)
        http.stub(pathSuffix: "/sync/tracking/planning/all", json: "[]", headers: pageHeaders)
        _ = try await destination.fetchEntries()
        try tokens.save(.init(accessToken: "second", refreshToken: "second", expiresAt: .distantFuture, accountIdentity: "second"))
        let entries = try await destination.fetchEntries()
        XCTAssertTrue(entries.isEmpty)
        XCTAssertEqual(http.sentPaths.filter { $0 == "/sync/tracking/planning/all" }.count, 2)
    }
}

private final class TestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var value = Date()
    var now: Date { lock.lock(); defer { lock.unlock() }; return value }
    func advance() { lock.lock(); defer { lock.unlock() }; value.addTimeInterval(61) }
}
