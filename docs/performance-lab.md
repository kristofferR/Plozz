# Simulator performance lab

Use this for the agent-driven optimization loop without installing on an Apple
TV, iPhone, or iPad. It complements [physical profiling](performance-debugging.md),
not a replacement for device-specific evidence. No cloud account, real media
server, credential, or external model service is required.

## Agent entry point

From the active checkout, inspect the machine-readable inventory:

```sh
python3 tools/performance.py list
```

Use a simulator you own. Select an explicit platform and UUID; an iPad is an
`iOS` simulator. The runner verifies platform, runtime build, and device type
before booting, never selects a different simulator or discovers physical devices.

```sh
export GIT_CONFIG_PARAMETERS="'safe.bareRepository=all'"
python3 tools/performance.py run --platform tvOS --sim-id "$PLOZZ_SIM_ID" --suite core
python3 tools/performance.py run --platform tvOS --sim-id "$PLOZZ_SIM_ID" --suite matrix
python3 tools/performance.py run --platform iOS --sim-id "$PLOZZ_IOS_SIM_ID" --suite ui
```

`core` is the default. `ui`, `matrix`, `diagnostics`, `network`, and `all` are explicit selections.
Suites include only scenarios supported on the requested platform; explicitly
requesting a platform-incompatible scenario fails before a build starts.
For a bounded investigation, select one or more scenario names instead of a suite:

```sh
python3 tools/performance.py run --platform tvOS --sim-id "$PLOZZ_SIM_ID" \
  --scenario sync-unchanged library-unchanged
```

These are optimized **Debug `-O`** tests so DEBUG-only test interfaces remain
available. They are not a distribution Release build. The debugger, coverage,
sanitizers, and parallel test execution are disabled for measurement. Run
correctness/sanitizer checks separately, not inside the timing experiment.
Builds are incremental in platform- and lane-private DerivedData. Each group
builds once and executes without rebuilding. There is no cache deletion,
from-clean recovery, test retry, dependency version update, or hardware install.

The whole lane owns a shared Apple build lease, including gaps, and a local
performance-runner lock. Do not overlap with another project writer in this
checkout. The runner temporarily moves a shadowing generated project while
using package test schemes, then restores it; a restoration conflict preserves
both copies and fails. A simulator booted by this invocation is shut down in
`finally`; a caller-owned simulator that was already running stays running.
The default whole-run limit is 2,400 seconds (`--timeout`, bounded to 60–7,200).
Cancellation/timeout stops only the owned process group and preserves evidence.

## Baseline → attribution → candidate → regression

1. Select the scenario matching the suspected work and capture a baseline
   **before** editing production code. Keep the printed run path. Record the
   symptom and configuration; do not replace a reported failure with an easier
   unrelated workload.
2. Inspect sample distributions and counters. Use Instruments/Time Profiler,
   Allocations, or SwiftUI Instruments on the owned simulator when attribution
   is needed. An elapsed-time regression alone does not name its cause.
   `python3 tools/performance.py report .build/performance/runs/BASELINE`
   prints compact JSON with medians, dispersion and counter ranges, omitting
   the large source/fixture manifests so agents need not load them into context.
3. Change only the measured cause. Repeat the identical scenario, simulator
   device type/runtime, toolchain and compilation settings. Keep the host quiet;
   do not benchmark while another build or many simulators compete for resources.
4. Compare the two saved runs:

   ```sh
   python3 tools/performance.py compare \
     .build/performance/runs/BASELINE/result.json \
     .build/performance/runs/CANDIDATE/result.json
   ```

5. Retain an optimization only with explained evidence and preserved behavior.
   A no-benefit result is valid. Add a focused correctness/work-count regression;
   do not weaken assertions, alter the workload, or reset the baseline to pass.
   A changed fixture requires a new baseline under that fixture.

Comparison never overwrites a baseline. Exit codes are **0 within budget**,
**1 regression/invalid evidence**, **2 inconclusive noisy comparison**.
The default timing allowance is the largest of 15% of the baseline median,
three median absolute deviations, and 1 ms. `--tolerance-percent` changes only
the declared percentage; set it for the experiment, never to hide a failure.
Noise above the larger of 20% of baseline or 1 ms is inconclusive.
Do not repeatedly rerun until a favorable sample passes. Diagnose contention or
capture a deliberately new controlled experiment, retaining the failed/noisy one.

`within-budget` is **not** proof of improvement. Read the deltas and their
dispersion. Work counts are reported separately and bounded by XCTest
assertions, not statistical timing allowances. Resident snapshots/deltas are
informational: allocator caches and framework lifetime make them unsuitable
for a blanket byte threshold. Lifecycle scenarios additionally assert weak
references actually release.

## Native Home navigation attribution

For focus/scroll lag rather than isolated work counts, run the production Home
fixture with real `XCUIRemote` directional input:

```sh
python3 tools/performance.py profile --platform tvOS --sim-id "$PLOZZ_SIM_ID"
python3 tools/performance.py report .build/performance/runs/RUN_ID
```

This route requires an **owned, initially shut-down tvOS simulator**. It builds
the optimized fixture and UI driver, verifies the installed `FocusHost` process,
starts recording, and only then sends navigation input. The driver attaches to
that same app without relaunching it. Three traversals must return focus to the
hero. The runner stops its recorder, terminates its fixture, restores its
temporary scheme and shuts down the simulator even on failure.

`Process Sample` is the default backend and uses macOS's installed `sample`
tool. The report separates main-thread frames, app-owned main-thread frames and
app-owned background frames. Counts are **inclusive stack observations**, which
include blocked/waiting threads; do not add parent and child counts together or
convert them into CPU milliseconds, hitch duration, FPS or input latency.
The capture includes setup/settling and the driver's eight-second idle window,
not only the directional-input intervals. Raw stacks and the XCTest result are
retained for attribution.

`--template 'Time Profiler'` and `--template SwiftUI` explicitly select installed
Instruments templates. They require a tracing-started notification and exportable
samples for the verified PID. On hosts where Instruments cannot attach to the
simulator, the run fails **before input**, retaining the logs; there is no silent
backend fallback. Choose Process Sample for a separate experiment instead.

The fixture uses local artwork and one synthetic provider, 75 items per row,
and a run-specific item namespace so the textless-artwork answer index cannot
skip all writes because of a previous run. It does not delete caches. This makes
the answer identities cold, **not every metadata/image cache**; artwork itself
is prewarmed. It does not reproduce the complete account/session, sidebar,
Live TV guide or concurrent cloud-sync workload. Extend the relevant fixture
dimension when investigating those paths; the separate matrix is not proof of
their navigation behavior.

These runs use `evidenceKind: simulator-navigation-profile`, not statistical
benchmark evidence. `compare` intentionally rejects them. Use stacks to identify
an owner, add a deterministic regression for that mechanism, and retain a fresh
candidate capture. A vanished stack on a warm cache alone is not an optimization.
For example, the textless-artwork index's atomic writes were observed on the
main thread; its regression blocks the disk writer while requiring the main
actor to accept and coalesce newer answers. That tests executor separation
without pretending a sample count measures frame smoothness.

## Workloads and configuration interactions

| Suite | Production path and limits |
| --- | --- |
| `core` | Unchanged sync persistence (10,000 records, 1,000 checks), warm incremental Share scanning (1,000 films), fresh SQLite IPTV import (10,000 generated records). The sync/Share fixtures also verify an actual edit is not suppressed. |
| `ui` | Shared `MediaRowView`/poster presentation with generated local artwork, settled idle, programmatic scrolling, repeated host/view teardown. Shared card scenarios run on tvOS, iPhone and iPad simulators and are **not the entire Home screen**. The tvOS-only `home-artwork-layout` scenarios exercise production Showcase artwork invalidation and duplicate reports across eight populated rows, with direct nested-host fitting duration/counts, sizing/placement counters and layout/focus controls. The `-cold` variant mounts a fresh view graph with warm artwork; it does not simulate every cold cache or a complete navigation session. |
| `matrix` | Full 16-case factorial: 1/4 resolved fixture-provider accounts × Plozz automatic channels off/on × cached Live TV data off/on × local cloud-sync processing off/on. Uses account resolution, `LiveTVLibraryRuntime`, source/portable sync bridges, and ledger persistence, with isolated defaults, in-memory credentials, local catalogues and provider doubles. |
| `diagnostics` | 10,000 operation attempts with recording disabled/enabled, plus 100 bounded snapshot encodes. Measures recorder and event-time serialization overhead without starting Sentry or creating uploads. |
| `network` | `catalog-cached-refresh`: 1,000-channel loopback M3U import with a 100-ms header delay, then an expired-catalog refresh held while three cached reads complete. Verifies one refresh and actual replacement visibility. Cold/cached foreground timings are separate counters; whole-cycle wall time includes setup, controlled waiting and settling. No external playlist or stream links are fetched. |

For Home metadata work, select `home-metadata-publication`,
`home-observed-metadata-publication`, `home-row-metadata-updates`, and
`home-row-metadata-reuse` on either platform.
These hosted scenarios measure real silent Home reloads and production-row
updates, distinguishing independently decoded equal snapshots from reuse of
existing values. The observed-publication variant changes metadata and waits
for the observing production row to receive every update. A background sampler
reports main-actor scheduling delays, not presented-frame hitches or FPS.
Pair `home-observed-metadata-publication` with
`home-observed-metadata-diagnostics` in the same run to measure the same Home
workload with the in-memory diagnostic recorder disabled/enabled. The enabled
variant does not start Sentry or upload anything.
Credits, sort metadata, membership/order, and provider parity
remain correctness controls; unchanged identity must not hide changed metadata.

The matrix uses 500 library items per provider and 1,000 cached IPTV channels
when enabled. Startup/discovery happens before measurement; each warm sample
performs ten unchanged refresh/capture cycles. It distinguishes feature
interaction and provider-count scaling without introducing real network noise.
Its providers are doubles labeled Plex/Jellyfin, not real Plex, Jellyfin, Emby,
SMB and IPTV transports running together. A cheap settled refresh does not
exonerate initial discovery, playlist replacement, guide fan-out or slow servers.
Catalogue revision callbacks and ledger capture acknowledgements mirror the
production sync composition, so warm samples exercise its unchanged-state path.
Assertions require the initial export to run, subsequent unchanged exports to
be reused, and an actual source edit to invalidate that reuse after measurement.
It does **not** log into iCloud, run CKSyncEngine delivery, simulate CloudKit
push timing, fetch a provider's server, or mount the Live TV guide UI.
“Live TV on” here means cached source/channel data participates, not a claim
that every Live TV feature has been exercised. Use paired cases to attribute
cost, not just the all-enabled versus all-disabled extremes.

There is intentionally no combinatorial cross-product of every app setting.
Add the specific suspected dimension (profile count, library size, pending sync
changes, artwork state, active/retained guide, playback, slow/offline provider)
and its positive controls when evidence calls for it. Keep cold startup, warm
steady state, and changed-data workloads separate. Preserve equal first-class
Plex/Jellyfin coverage when an optimization reaches provider behavior.

## Evidence contract

Runs live in ignored `.build/performance/runs/<id>/`. `result.json` contains:

- exact Git HEAD and hashes of current source/test/config/tool inputs, including
  staged, unstaged and untracked files; concurrent source changes fail the run;
- platform, simulator type/runtime build, SDK/Xcode, host OS/hardware,
  optimization flags, runner fingerprint, all test-fixture fingerprints,
  timestamps and host-load samples;
- each scenario's **one discarded warmup and five measured samples**, wall/CPU
  milliseconds, process resident bytes/delta, and actual workload counters.

Raw command logs, build/test `.xcresult` bundles, summaries, generated schemes
and exported JSON attachments remain beside the result. A clean driver exit,
exact expected test count, zero skips/failures, and complete unique finite
measurement attachments are all required. An interrupted or partial matrix is
failed evidence, not a smaller passing suite. Invalid/missing results fail closed.

Comparison requires matching scenarios, fixture fingerprints and environment;
source code may differ because that is the experiment. Keep baselines tied to
the corresponding machine/runtime. Hosted CI machines are useful for
deterministic counters and correctness, but their absolute timings should not
be compared against a developer Mac. No full suite runs or schedules are
automatically enabled by installing this tooling.

Measurements cover the test process, including any framework work it triggers.
`persistenceCalls` counts entry into the ledger's guarded persistence closure,
not total filesystem operations; `inventoryUpdates` counts SQLite row updates,
not physical writes. An unchanged Share scan still stamps retained inventory
with its new scan identifier so final pruning does not delete valid entries.
Those stamps are neither fresh file discovery nor one network request per item.
The Share fixture uses an immediate in-memory directory lister; `catalog-import`
uses preconstructed IPTV records and does not include M3U download or parsing.
Do not turn these counters into a claim about total device I/O.
They do not measure total device CPU, allocation count, GPU time, energy use,
presented-frame hitches or memory-pressure limits. Do not describe a sleeping
idle window's wall time as work; its comparison gates CPU only.

## Adding a scenario

Reuse existing production fixtures and helpers first. Add an opt-in XCTest
method that calls `PerformanceProbe.requireEnabled()` **before setup**, then
`PerformanceProbe.measure(self, scenario: ...)` around the bounded workload.
Supply observed counters and meaningful positive controls; never constant
“success” counters as a substitute for checking outcomes. Ordinary test runs
skip these probes. The probe also refuses physical execution.

Package suites depend on the test-only `TestSupportPerformance` target; hosted
suites compile that same source directly, preserving their single umbrella
package-product linkage. Register the selector, fixture file, description and
required counter keys in `tools/performance.py`. Keep identifiers and units
stable; bump the report schema if their meaning changes. Extend
`tools/tests/test_performance.py` for evidence or comparison changes.

## Hardware checkpoint

Simulator evidence can establish reduced work and guard algorithms, not certify
Apple TV smoothness. Decoder/HDR behavior, GPU limits, actual thermal/memory
pressure and hardware frame pacing require a separately agreed physical check.
Batch that check after a meaningful set of improvements; use scripted input and
bounded traces where supported rather than asking a person to judge every edit.
Local performance work does not authorize distribution or new telemetry uploads.
