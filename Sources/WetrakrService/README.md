# WeTrakr

Optional, profile-scoped movie/episode scrobbling and bidirectional planning-list
sync. All media backends use the same tracker boundary. Live channels and media
without an identifiable movie or episode are not scrobbled.

## Release availability

WeTrakr is currently disabled in `RuntimeFeatureFlags.productionDefault` while
API rate-limit behavior is investigated. Both platforms hide its tracker setup
and watchlist links. Resolved configuration remains unavailable even when a
client ID and saved connection exist, so status refresh, watchlist sync, and
playback tracking cannot contact WeTrakr. Stored connections are not erased.
Tests may explicitly enable the flag or inject a test configuration; restoring
the production flag is a separate release decision.

## Registration

Set `WETRAKR_CLIENT_ID` in the ignored `Config/Secrets.local.xcconfig`.
Only the public client ID is needed; do not ship a client secret. The registered
redirect is `https://plozz.app/auth/wetrakr/callback`.

Apple TV uses device authorization. Canonical iPhone/iPad builds use S256 PKCE
with `ASWebAuthenticationSession` and the existing `webcredentials:plozz.app`
association. Branded builds without the association use device authorization.
The callback fallback is maintained in `web/pairing-links`.

## Authorization and privacy

`CoreTrackerAuth` owns Keychain persistence, single-flight token refresh and
the encrypted CloudKit conditional-write protocol shared with Trakt. WeTrakr
uses a separate `wetrakr.oauth` account and coordinated cloud-record prefix;
existing Trakt storage names remain unchanged. Refresh-token rotation preserves
the connection identity. A new sign-in creates a new grant identity.

Credentials and API response bodies are never logged. Only the username needed
by Settings is decoded from account information. Requests carrying credentials
cannot redirect to another origin. Disconnect writes the coordinated tombstone,
discards local watchlist caches, and attempts remote session revocation. A failed
revocation is reported explicitly.
An HTTP 403 is reported as a blocked request, not an expired user sign-in or
proof that the client ID is invalid; the API's edge protection can reject a
request before it reaches authorization.
Browser failures, rejected callback addresses/state/codes, and failed token
exchanges have distinct Settings errors. Diagnostics contain only fixed failure
categories and numeric browser/HTTP error codes, never callback URLs, OAuth
codes, state values, credentials, or response bodies. Callback validation still
fails closed; these diagnostics do not bypass a failed sign-in.
Google sign-in can append a bare `#` to the callback. This empty fragment is
accepted without relaxing callback-address, state, or authorization-code checks.

## Playback and watchlists

- Start/resume/pause/stop events use the realtime API; progress ticks do not.
  The completion threshold is 90 percent. Realtime failures never stop playback.
- Durable completed watches retain the original capture time, connection
  identity and stable retry key. A later sign-in cannot receive an earlier
  connection's queued watch. Normal rewatches use `allow_rewatch: true`; known
  server duplicate responses are accepted, other per-item failures are not.
- Episode scrobbles use explicit series catalog IDs and episode coordinates,
  including season zero. Completed-watch writes can also use episode catalog
  IDs directly. Provider-local identifiers are never sent as WeTrakr IDs.
- WeTrakr's `planning` list participates in Plozz's universal watchlist. Reads
  have a minute-long memory cache, then check activities and consume the
  incremental journal. The visible journal watermark, overlap and event IDs
  prevent recent events from being lost. Expired journals require a full resync.
  Pagination must finish before a replacement list is published.
- The universal-watchlist runtime persists the last complete, identity-scoped
  view. Journal cursors remain in memory; a new process establishes a new full
  baseline. Imported entries are evidence, not permanent Plozz watchlist intent.
- Native entries retain canonical WeTrakr links through deduplication and
  library resolution. Detail pages expose the link directly (QR on Apple TV);
  mobile poster menus also offer it. Disconnect retracts native attribution.
- Native WeTrakr IDs provide stable, media-kind-scoped watchlist identity even
  without external catalog IDs. These entries remain removable; other trackers
  receive only catalog IDs they support, never WeTrakr IDs.

API contract: <https://api.wetrakr.com/>.
