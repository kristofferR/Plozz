# Discord support forums and GitHub issues

GitHub remains the canonical Plozz backlog. The bridge makes the Discord `bugs`
and `feature-requests` forums another way to contribute to it without maintaining
a separate triage queue.

**Installing the workflow does not activate public mirroring.** Its push-triggered
preflight is read-only. Live synchronization requires an explicit activation
variable, a public-posting notice, and the workflow on `main`.

## Behavior

- A new human-authored forum post is compared with open GitHub issues of the
  appropriate kind. Copilot links a clearly equivalent report to an existing
  issue, or creates a new `bug` / `enhancement` issue when no confident match exists.
  Closed issues are not candidates for new reports; existing links remain intact.
- Report text and subsequent human replies are copied to GitHub with attribution
  and links to their Discord originals. Edits update bridge-managed content.
  Maintainer text outside the marked regions is preserved.
- The forum's default reaction counts as a vote, falling back to thumbs-up when
  no default is configured. Unique non-bot voters are counted across all Discord
  posts linked to an issue. Normal and burst reactions from the same person count
  once. The total is a bot-owned GitHub comment, not impersonated GitHub reactions.
- GitHub comments on linked issues and issue open/closed status flow back to
  Discord. Queued replies are sent oldest-first by creation time, with comment
  IDs breaking ties; editing an older comment does not move it to the end.
  A failed send stops later replies to that thread from overtaking it. Long
  comments are split without dropping content. Bot imports do not bounce between
  services. The bridge never closes or reopens a GitHub issue.
- Other channels, private threads, bot-created posts, and posts created before
  the published activation timestamp are excluded.

The scheduled action runs approximately every 15 minutes, not in real time.
Synced replies appear when delivered: Discord cannot insert a delayed GitHub
reply retroactively between native Discord messages already posted. Additional
parts introduced by expanding an older GitHub comment also appear when synced.
GitHub can delay or skip scheduled runs and can disable schedules after prolonged
repository inactivity. Standard hosted runners are free for public repositories;
Copilot matching uses the authenticated account's allowance and policies.

Copilot runs only when classifying a new report, or during an explicit connection
preflight. Existing links and vote/status updates are deterministic. Authentication,
model, or malformed-response failures leave new reports pending and fail the run
visibly; they do not silently create duplicates or choose another model.

## One-time setup

The configured server and forum IDs are in `tools/discord-bridge.py`. The bot needs
View Channels, Read Message History, Send Messages in Threads, and Embed Links in
both forums, plus Message Content Intent. Administrator, Presence Intent, and
Server Members Intent are unnecessary. Set each forum's default reaction to
thumbs-up for a consistent voting affordance.

Repository Actions secrets:

| Secret | Purpose |
| --- | --- |
| `DISCORD_BOT_TOKEN` | The configured Discord bot's token. |
| `COPILOT_GITHUB_TOKEN` | A personal fine-grained PAT with only the Copilot Requests account permission. |

Issue/comment writes use the job's separate built-in `GITHUB_TOKEN`. Do not grant
the Copilot credential repository-write permissions. Tokens are never committed.
Choose token expiration according to the account owner's maintenance and security
requirements; a nonexpiring token must still be revoked if compromised.

The public Copilot CLI package is version-pinned in the workflow. The script
explicitly selects **GPT-6.1 Sol (`gpt-6.1-sol`)** with **high** reasoning effort.
Newer Sol models require an explicit configuration update rather than an
automatic model switch. The preflight must
successfully verify that exact selection for the credential's account before
activation. No provider/model fallback is configured.

### Public-posting notice

Publish this in the guidelines of **both** forums before activation:

> Posts and replies automatically sync to GitHub

The bridge verifies that this notice remains in both forums' guidelines before
processing reports, including dry runs. Extra forum-specific instructions can
surround it; whitespace and line breaks can vary. Removing the notice stops
mirroring even if the activation variable remains enabled.

After approval of the notice and live operation:

1. Run **Discord issue bridge -> Run workflow -> preflight** on the reviewed
   revision. Verify both forum connections and the exact Copilot model.
2. Set repository variable `DISCORD_PUBLIC_SINCE` to the UTC timestamp after both
   notices were published, for example `2026-01-01T12:00:00Z`. Only later-created
   posts are eligible; this timestamp is not retroactive publication consent.
3. Run `dry-run` to inspect proposed routing without changing either service.
   Dry-run output contains thread IDs and decisions, not report contents.
4. With the reviewed workflow on `main`, set `DISCORD_BRIDGE_ENABLED` to `true`
   and run `sync`. Confirm an approved test post, reply, edit, duplicate, vote,
   and GitHub reply/status change reach the intended destinations.

Remove or set `DISCORD_BRIDGE_ENABLED` to `false` to stop scheduled writes.
Do not advance the notice timestamp after linking posts: that would exclude
existing sources and make vote totals incomplete.

### Forum tags and posting templates

Both forums use optional device tags (`Apple TV`, `iPhone`, `iPad`) and media-source
tags (`Plex`, `Jellyfin`, `Emby`, `Silo`, `Network shares`, `IPTV`). Members can select
the relevant device and source without a mandatory-tag barrier. These describe
the report, not its status; the bridge's issue link shows GitHub's open/closed
state. Tags do not change matching, assign priority, or automatically become
GitHub labels.

Forum guidelines should keep the public notice above and briefly ask people to
search first, post one bug/idea at a time, use relevant tags, and keep private data
out of text, screenshots, and diagnostics. Each forum has a pinned "Start here"
post with a copyable template. Bug reports ask for version/build, device/OS,
source, expected/actual behavior, and reproduction steps. Feature requests ask
for the goal, benefit, current workaround, and example behavior.

The canonical pinned copy is `POSTING_GUIDES` in `tools/discord-bridge.py`. To
publish or refresh it, explicitly run **Discord issue bridge -> Run workflow ->
publish-guides** on the intended revision. This manual-only job uses only the
Discord secret: it does not invoke Copilot, receive a GitHub write token, or
change the live bridge's activation. The bot needs Send Messages in the two
forums to create their starter posts, in addition to its normal thread-reply
permissions. Pin each returned post using a moderator account; do not grant the
bot Administrator, Manage Channels, or Manage Threads just for this setup.

Guides are bot-authored, so the existing bridge excludes the entire guide thread,
including replies, without relying on user-editable tags or titles. Publishing
again verifies or updates the same bot-owned starter instead of making another
post. A conflicting human-owned title or multiple matching guides stops the
operation. Ambiguous creation failures are not retried immediately; a later run
rediscovers a successfully created guide.

## Operational limits and recovery

Mappings live in the bot-authored GitHub report bodies/comments and Discord
message footers, not in an expiring Actions cache. Keep those identifiers and
managed-region boundaries intact. Untrusted users cannot establish a mapping
by pasting a marker into their own GitHub issue or Discord message.

The workflow serializes runs. It discovers existing mappings before writing;
ambiguous POST failures are not immediately retried. A later run can recover a
successfully created remote record after a lost response. Discord writes also
use deterministic nonces. A partial source failure never publishes a partial
voter set as a complete total. Check failed Actions runs rather than repeatedly
rerunning a job without reading its error.

Locked Discord threads retain inbound synchronization but defer outbound updates
with a warning until unlocked. No Manage Threads permission is used. Posting a
GitHub reply to an unlocked archived thread may unarchive it. Previously linked
threads that disappear cause a visible failure rather than silently reducing
their vote counts.

Deletions are not propagated between services. For sensitive content, remove or
edit the Discord source first, then remove every GitHub copy and any mirrored
Discord copies. Otherwise the next run may restore a missing managed GitHub
record from its still-present source. Do not rely on the bridge to detect secrets
inside free text, screenshots, or attachments.

Discord attachment links can expire. The bridge copies their links and provides
the original Discord message link; it is **not** a durable attachment archive.
Upload an important diagnostic attachment to GitHub separately if permanent
availability there is required.

Copilot matching is conservative, not infallible. An incorrect link needs a
maintainer correction; ordinary reports do not require manual approval. Large
backlogs can exceed API or matching-context budgets; those failures are explicit
instead of silently truncating candidates or report text.

Offline regression tests:

```bash
python3 -m unittest discover -s tools/tests -p 'test_discord_bridge.py'
actionlint .github/workflows/discord-bridge.yml
```

## TestFlight announcements

The separate **TestFlight Discord announcements** workflow uses the same Plozz
bot in the [updates channel](https://discord.com/channels/1527028230106906704/1560139816757235762).
It does not run Copilot, mirror conversations, or change the issue bridge.
Publishing a GitHub release triggers a check; a roughly 15-minute schedule also
handles delayed Apple review and builds uploaded outside Fastlane. GitHub may
delay scheduled runs, so this is not an instant-delivery guarantee.

App Store Connect is the authority: only nonexpired, `VALID` builds that belong
to `Plozz External` and have external state `IN_BETA_TESTING` are announced.
Uploads, internal availability, and pending review are not advertised as ready.
The public beta link must still be enabled for that group.

Each Apple version/build has one bot-owned message with its available platforms,
Plozz display version, TestFlight link, and published GitHub release-notes link
when available. Published releases read the catalog from their exact release tag
and validate its release ID, build, and Apple version against TestFlight. The
public date does not depend on the release entry already being merged into `main`.
An unreadable or mismatched tagged catalog fails visibly rather than substituting
Apple's retained marketing version.

Before a GitHub release is published, the bot uses a matching entry from `main`
if present; otherwise it announces only the build number, without inventing a
public date. It directs readers to TestFlight's notes and adds the public date
and release link on a later check. Platform availability and label corrections
update the same message instead of creating another announcement. Dotted hotfix
builds remain distinct and sort numerically.

Setup:

1. Configure repository Actions secrets `TESTFLIGHT_ASC_KEY_ID`,
   `TESTFLIGHT_ASC_ISSUER_ID`, and `TESTFLIGHT_ASC_PRIVATE_KEY` (the complete
   `.p8` PEM), alongside the existing `DISCORD_BOT_TOKEN`. A dedicated read-only
   App Store Connect key is preferable; an existing release key may be reused
   with the owner's approval, but retains its broader privileges. The script
   only makes GET requests to Apple and signs short-lived JWTs in memory.
2. Give the bot View Channel, Send Messages, Embed Links, and Read Message
   History in the updates channel. Administrator is not required. The preflight
   checks effective role/channel/member permissions before reading history.
3. Set repository variable `TESTFLIGHT_DISCORD_MIN_BUILD` to the first build
   that should be announced (initial deployment: `56`). Earlier builds are
   excluded to prevent a backlog of old announcements.
4. Merge the workflow to `main`, then manually run it in `check` mode. This
   verifies both services and logs the proposed public messages without posting.
5. Set `TESTFLIGHT_DISCORD_ENABLED=true` and run `sync`. Disable that variable to
   stop automatic posts. Pushes run offline tests only and never receive secrets.

Live jobs always execute the code on `main`, including release-triggered jobs;
they do not run scripts from a release tag or a manually selected feature branch.
Only release-catalog JSON is read from release tags; tagged code is never executed.
They share a single concurrency group. Message footers and deterministic nonces
provide retry deduplication without a database or expiring Actions cache. Existing
bot messages are verified before writing; human copies of markers are ignored.
Ambiguous writes are not retried immediately, and duplicate bot markers fail
visibly. Keep the bot's messages/footers intact: deleting a message allows a later
run to recreate it while its build remains eligible.

Failures appear as failed Actions runs; they do not rebuild, reupload, change
App Store Connect, or turn a successful app release into a failed release lane.
Recover by fixing the reported credentials/permissions/API problem and rerunning
this workflow, not `fastlane beta`.

```bash
python3 -m unittest discover -s tools/tests -p 'test_*discord*.py'
actionlint .github/workflows/testflight-discord.yml
```
