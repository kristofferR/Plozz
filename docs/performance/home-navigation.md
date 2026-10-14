# Home navigation performance

## Investigation

The comparison uses static analysis of Infuse 8.5.6 for tvOS and physical-TV
measurements of Plozz. Infuse's implementation details explain useful techniques;
they do not establish a measured speed advantage for any individual technique.

| Infuse behavior | Plozz comparison / action |
| --- | --- |
| Fixed-size collection-view cells inside independent Home sections | Plozz already fixes card geometry and uses lazy rows. Preserve those constraints. A full collection-view migration needs separate evidence. |
| Focus updates coordinate native transforms instead of preparing images | Plozz was calling artwork/badge preparation on every native poster layout. Reuse preparation until content or bounds change; keep badge projection and native focus animation live. |
| Display-size images rendered and decoded on bounded worker queues | Plozz already bounds image decoding. Its final card composition still contributes substantial main-thread work. A trial moving that composition to a worker queue did not improve immediate navigation consistently and was discarded. |
| Standard-range opaque rendering, JPEG for opaque images, PNG for alpha | Avoid Home's main-actor Top Shelf export. Reuse matching compressed bytes, and avoid decoding/re-encoding plain shelf posters. TV measurements support UIKit JPEG at quality 0.8 for opaque exports; preserve PNG for alpha. |
| Original and display caches, tiny previews, in-flight request sharing | Plozz already has downloaded-byte and decoded-image caches plus preview variants. The export path can reuse the policy-selected source's cached bytes at matching dimensions. |
| Home notification streams debounce for 200 ms; repositories support equality checks | Plozz already coalesces overlapping loads and suppresses equal progressive content. Do not add latency to initial row publication without evidence of redundant work. |
| Separate UI/indexing request priorities and display destinations | Plozz has separate foreground/background artwork limits, but Top Shelf was using the foreground lane. Route its metadata lookup and decoding through the background lane; preserve cancellation for superseded publications. |

The analyzed Infuse Home does not have Plozz's focus-driven hero. Its focus handler
performs bookkeeping, while Plozz also updates hero presentation. That difference
must be considered when comparing superficially similar screens.

Fresh disassembly confirms that Infuse's serializer calls
`UIImagePNGRepresentation` at `0x1003c1554` and
`UIImageJPEGRepresentation` at `0x1003c1580`. Its Home notification path calls
RxSwift `debounce` with 200 milliseconds at `0x1004f92a8`. These are addresses in
the analyzed tvOS executable, not stable API addresses.

## Physical-TV method

- Apple TV 4K, second generation (A12, 3 GB), tvOS 27.2.
- Optimized Debug measurement app, separate from the installed production app.
- Connect the remote before launching a fresh app process. Begin 40 Down presses
  at 10 Hz as soon as launch/foreground activation completes, without settling.
- Sample the final transition for two seconds, verify the bottom focus target,
  then send 40 Up presses and verify return to Home.
- Retain downloaded image bytes between runs; a fresh process clears decoded
  memory. This is not a cold disk-cache test.
- Reject runs with input lateness over 50 ms or missing focus endpoints.
- Score cumulative hitch-counter differences, worst frame, and peak memory.
  The sampler counts display-link intervals above 1.5 times the nominal frame budget.
  Use separate app-only Time Profiler runs for diagnosis, not scored comparisons.

## Initial evidence

Baseline `ea1d12f5` produced 18, 22, and 26 downward-pass hitches. Worst frames
were 457, 278, and 346 ms. These runs establish substantial startup variability.

In one baseline app-only profile, 179 of 180 main-thread samples attributed to
Home's Top Shelf resolver were in UIKit/ImageIO image encoding. Moving export
off-main removed that stack from the next profile. Two valid navigation runs
with that change alone recorded 25 and 22 downward hitches, so this is evidence
of removed main-thread work, not a demonstrated startup scrolling improvement.

Final card composition still accounted for roughly 460–485 one-millisecond
main-thread samples in these diagnostic traversals. This change removes redundant
layout preparation and export round-trips while retaining native focus behavior.
It does not remove all main-thread card composition.

The cell's 50 ms timer is **not evidence of a focus debounce**. Both its timer
and native focus coordinator capture `0x100836400` and the same context; that
closure checks/sets a shared applied flag before changing transforms,
constraints, and alpha. The timer appears to be a fallback for the coordinated
animation. An earlier static-analysis interpretation of it as a delayed
secondary animation was corrected after tracing the shared closure.


## Codec benchmark on the TV

A local hosted test rendered the repository's photographic Home screenshot into
opaque, standard-range fixtures at two poster sizes. Each encoder had two warmups
and ten timed iterations. These are median elapsed encoding times, not end-to-end
scrolling or disk-read times. JPEG quality was 0.8 for both APIs.

| Method | 400×600 | 600×900 | 600×900 output |
| --- | ---: | ---: | ---: |
| UIKit PNG | 13.42 ms | 25.68 ms | 670,065 bytes |
| UIKit JPEG | 1.75 ms | 3.39 ms | 91,101 bytes |
| ImageIO JPEG | 1.73 ms | 3.39 ms | 91,037 bytes |
| Matching cached JPEG, including validation | 0.15 ms | 0.14 ms | 91,101 bytes |

The result supports the standard UIKit API: ImageIO offered no meaningful speed
advantage. Reuse approved cached bytes first; encode opaque fallbacks as JPEG,
retain PNG for alpha, and composite resume artwork once into JPEG. The codec
fixture and raw logs remain in the local performance workspace rather than the
production test suite.

## Final navigation measurements

The final candidate was interleaved with reinstalls of the baseline app. All
included runs reached the bottom library-shortcut row and returned focus to Home.
The final candidate's third run ended Down on the adjacent library tile rather
than Collections, so these are full-row traversals, not identical focus paths.

| Build / run | Down hitches | Worst Down frame | Up hitches | Worst Up frame |
| --- | ---: | ---: | ---: | ---: |
| Baseline 5 | 25 | 440 ms | 24 | 220 ms |
| Baseline 6 | 28 | 342 ms | 31 | 112 ms |
| Final 1 | 24 | 324 ms | 22 | 250 ms |
| Final 2 | 27 | 246 ms | 28 | 266 ms |
| Final 3 | 20 | 291 ms | 30 | 253 ms |

Together with the initial baseline runs, Down hitch counts span 18–28 for the
baseline and 20–27 for the candidate. The measurements do **not** establish a
consistent immediate-scroll improvement. Return traversal counts overlap too.
The supported gains are cheaper export encoding, removed main-thread export work,
and avoiding repeated artwork preparation, not a claimed percentage gain in FPS.

Baseline run 4 was excluded because WDA could not verify its Down endpoint (404).
Earlier baseline Up counts crossed a different sampling boundary and are omitted
from the table. Input lateness in the included final runs stayed below 12 ms.
Raw phase samples and JSON summaries are retained in the local performance
workspace as `home-baseline-{5,6}-*.log*` and `home-general-{1,2,3}-*.log*`.

## Validation

- Physical TV: five final export tests passed (opaque JPEG, transparent PNG,
  cancellation, matching-byte reuse/dimension rejection, plain/resume files).
- Physical TV: eight native focus tests passed, including repeated-layout reuse,
  bitmap arrival, live overlays, intermediate animation frames, and focus ownership.
- Measurement app build/install, architecture guard, test hygiene, localization
  guard, catalog validation, and source snapshot check passed.

The image benchmarks use a photographic fixture and warm in-memory data, so they
do not measure every poster, cache hit rate, or disk latency. UIKit and ImageIO
JPEG timing was effectively equal. No private Infuse focus APIs were adopted.

## Upstream integration, 14 October 2026

The initial integration used upstream `00f72ecf`, incorporated into fork main by
a history-preserving merge. The optimized app and hosted-test target
built successfully on the full local Home stack. All 18 selected tests passed on
the physical TV: the five export and eight native-focus tests above, plus four
extended-artwork tests and one native-activity test from the unpublished follow-up.
Architecture, test hygiene and localization guards passed after integration.

The branches were then rebased onto upstream `a2270c65`, which changes Emby's
native-section request filters. Fork main's code matches that upstream revision.
The artwork, focus, export and selected hosted-test sources are unchanged from
the tested local stack, so their integration evidence is reused. This is focused
coverage; it is not a new full test sweep or a benchmark of the latest base.

The timing and traversal tables above describe the pre-rebase binaries, not the
new upstream base. The unpublished combined follow-up raised a first settled-pass
regression concern in repeated normal-speed measurements and is held locally
pending isolation. The epic tracks those results and remaining experiments.
