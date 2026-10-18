# CoreUI

Shared, **focusable** UI primitives, the app theme, and the artwork image
cache that every feature module reuses on tvOS and iOS/iPadOS — guarded behind
`#if canImport(SwiftUI)` so the package still compiles on Linux for tests.

## Responsibility

- **Reorder-only lists** — `LiftableReorderList(allowsHiding: false)` presents
  enabled entries only and keeps them enabled through native dragging, remote
  lift-and-move and context-menu movement. It has no Hidden divider or Hide/Show
  actions. Existing callers keep the reorder-and-hide behavior by default.

- **Playback failures** — `PlaybackFailureView` owns the full-screen TV/mobile
  error layout, bounded symbol inline with the heading, readable summary, adaptive
  native actions and optional Details sheet. Hosts own retry and dismissal; the error surface owns
  its dark palette without changing browsing themes. Its opaque themed surface
  stays legible over video without depending on glass or motion.
  `PlaybackDiagnosticDetailsView` is shared by on-demand playback, Live TV and
  IPTV setup. It renders and shares only the structured `PlaybackDiagnosticReport`,
  including app/OS identity; it is not the continuously sampled diagnostics HUD.

- **Touch hero actions** — `HeroActionRow` preserves readable intrinsic widths
  before falling back to a vertical arrangement. `TouchHeroActionButtonStyle`
  lets labels wrap and uses bounded 24pt corners so tall accessibility-size
  content stays inside the button surface. Circular actions retain their 48pt
  touch targets and cap glyph scaling at XXX Large; text buttons continue to
  honor the full accessibility text size.

- **Setup presentation** — `ConnectionCodeView` shares the readable monospaced
  code panel across server sign-in and device pairing. `SetupCodeComparisonView`
  keeps both devices' confirmation copy and code treatment consistent while
  callers retain confirmation and cancellation ownership. `SetupSectionCard`
  groups methods and counted summaries without styling native controls.
  `SetupSummaryView` scrolls the heading, full server names, and supplied profile
  grid while keeping Done/Continue reachable. TV rows and profile tiles provide
  native focus targets so the remote can reach long summaries. TV summaries scroll
  to the page's top edge, with initial header spacing inside the scroll content
  rather than an inset clipping boundary. `VerticalEdgeFadeMask` softens only the
  bottom above the fixed action while more content remains; the final rows stay
  undimmed at the end.

- **Reduce Motion** — `ReducedMotion` suppresses explicit and implicit SwiftUI
  animations at the TV app root without removing layout offsets or replacing
  view identity. Native hero artwork uses a crossfade instead of a parallax wipe;
  changing the system preference finishes an in-flight wipe. Timeline-driven
  liquid backgrounds and player-menu marquees also stop their decorative motion.
  Native focus feedback and meaningful playback/countdown progress remain available.

- **First-use choices** — `FirstUseChoiceView` shares the Live TV preview and
  playback-version introduction heading, native actions, and Settings reminder.
  Hosts own persistence and cancellation; dismissing a version prompt never
  records a mode. Mobile uses a vertically stacked, scrolling adaptation.

- **Settings row typography** — `SettingsRowMetrics.titleFont` is the shared
  body-size label for navigation rows, TV switch variants, and labeled controls.
  Keep headings separate; do not give toggles a larger headline font or add
  per-screen compensating font overrides. Native iOS/iPadOS switches retain
  system sizing. TV option/segmented pickers use the same body-sized labels;
  `settingsHelperText()` uses the smaller caption size for explanatory copy
  (tvOS footnote and body render at the same size).
- **Settings form geometry** — `settingsFormRowLayout()` gives links, On/Off
  rows, and compact inline steppers the same content padding and minimum height.
  TV form groups use a uniform 16pt focus inset. The contained focus radius is
  the 28pt group radius minus that inset (12pt), including illustrated groups.
  Headings, compact labels, helper copy and ordinary dividers share the control
  text keyline: 16pt group inset plus 12pt row padding. Groups provide
  `settingsFormTextInset`; `settingsFormTextLayout()` consumes it for static
  content, while padded focus-row labels reset it to prevent double insets.
  Outside a grouped form the text helpers add no padding. Legacy uncontained
  checkmark groups retain their separate focus-bleed geometry.
  Standalone page links use the `.navigation` row role: idle and focused surfaces
  both read the same 28pt radius, with no focus bleed or corner tightening.
  Adjacent page links have an 8pt gap; separate control sections keep their larger gap.
  Page titles and Back belong inside the scrolling content, not in a fixed
  header strip that shortens the viewport. `SettingsPageHeader` supplies their
  horizontal Back/title layout, not a separate pinned container. `SettingsBackButton`
  selects the shared native bordered capsule while callers retain navigation and
  focus ownership. The full-width header is a native focus section, so Up from
  right-aligned controls can reach the leading Back button. The full-screen subtitle editor is
  an explicit exception: its stationary heading sits above a scrolling tool pane.
  TV Settings categories and descendants share the centered
  `SettingsFormMetrics.pageWidth`. `SettingsPageStack` keeps that width throughout
  navigation; only explicitly full-width destinations use the whole viewport.
- **Settings page navigation** — the TV workspace uses `SettingsPageStack` for
  the retained category list and its equally sized child pages. Only the current page owns input,
  accessibility and Back; a pop restores the originating link's focus after the
  shared 420ms eased fade with 64pt directional travel, rather than crossing the
  screen. Retained parents and inserted children use the same motion and keep
  their final layout sizes throughout. Input and native entry/return focus transfer
  only after the fade completes, so overlapping pages cannot steal focus.
  `SettingsPageLink`, `SettingsPageDismiss` and
  boolean destinations retain native navigation outside this workspace,
  including iOS/iPadOS. `SettingsPageMotion` is also used by nested form and
  subtitle panels, with Reduce Motion respected by their hosts.
- **Native action controls** — `plozzActionButton` only selects the system
  glass/glass-prominent styles, or bordered styles on older systems. It adds no
  font, padding, capsule, border, focus effect or press scaling. Setup, profile/PIN,
  source/import, retry and sync actions share this native selection rather than
  the retired `PlozzActionButtonStyle`. Keep label sizing native; do not add wide
  minimum widths just to manufacture a large page-action pill. Text colors belong
  on text, not screen containers that also contain native controls.
  iOS primary actions pair the palette's monochrome `accent` with `onAccent`:
  native prominent buttons otherwise retain white text on a white tint. This
  theme-color pairing does not replace native geometry, material or interaction.
  Playback uses `PlayerControlButton` for icon-only transport actions. Multiview
  keeps visible title-and-icon labels and uses the same `playerGlassButton`
  treatment, including native menus. Only the existing reduced-transparency
  playback path draws the shared frosted fallback.
- **Settings steppers** — TV makes the whole labeled row one focus target using
  the existing `SettingsFormButtonStyle`, including its helper, persistent minus/plus cues and
  `SettingsRowMetrics.titleFont` value. Labels must be supplied to the shared
  stepper, not placed outside its focus target. Left/Right adjusts,
  Select increments, and Up/Down remains native focus navigation. Bounds clamp
  unless a caller explicitly requests wrapping. Width reserves the longest value.
  `SettingsAdjustmentFocusScope` shares the player's horizontal input ownership,
  held-press cancellation, and navigation-rail protection. VoiceOver adjustment
  uses the same stepping operation. Mobile retains separate buttons.
- **Grouped Settings rows** — `SettingsControlRows` inserts palette separators
  between tvOS rows sharing a container, never after the last visible row. Keep
  a control and its helper in one child view; the divider belongs after both.
  Conditional rows keep their SwiftUI identity, and separators add no focus or
  accessibility stops. Focus fills stay within row bounds, with the shared
  8pt `dividerFocusClearance` on each side of the line. Icon-led category lists
  start their dividers at `SettingsRowMetrics.iconTitleInset`, sharing the actual
  row icon width, gap and content padding; leading alignment also follows RTL.
  Illustrated Settings groups instead use a 16pt gap and 16pt padding without
  internal dividers. Grouped steppers inherit
  the same leading inset as their neighboring rows, with no extra resting chip.
  Mobile keeps its existing stack/native-list presentation.
- **Long Settings labels** — `LabeledSettingRow` preserves the aligned horizontal
  layout when it fits. On tvOS, longer copy switches to a wrapping label above
  its control rather than overlapping it or reducing the shared body font.
  Mobile retains its existing layout.
- **Grouped settings navigation** — `SettingsDisclosureLabel` supplies a
  direction-aware disclosure indicator and optional value without adding row
  padding. `SettingsSectionGroup` owns those insets; do not nest a separately
  padded `SettingsRowLabel` in it. Inline actions use `plozzActionButton`, not
  the group's full-width row-button style. Place a standalone native action in
  a layout container so its accessibility bounds do not include the row's
  noninteractive space.
- **Unwatched episode counts** — a default-on profile preference replaces the
  top-right watch-status mark with a number on series/season cards.
  Episode counts use charcoal tiles with white digits so they stay quieter than
  the light watch-status marks. Watched mode uses an inset count tile and a white
  completed circle with a dark check. Unwatched mode uses a white triangle for
  unnumbered titles and a flush count tile with a curved bottom-left corner.
  The count tile's top-right corner stays square; only the artwork clips its
  outer corner and shadow. Native poster and library-card overlay hosts apply
  that clipping at the full artwork bounds, not at the badge's own bounds.
  Both count styles use bold system digits. At standard TV size the curved
  tile has 12pt side padding and is 52pt tall; floating-tile spacing is unchanged.
  Floating marks have density-scaled clearance (16pt at standard TV size).
  Touch sizes and artwork radii remain proportionate. Episode cards and the
  watch-indicator Settings swatches reuse the same light check badge and flag.
  Positive exact library counts take priority; unknown counts retain the
  existing watched/unwatched style. Completed containers retain its completion
  behavior. Movies, episodes, ownership/request marks and spoiler protection
  are unchanged. Native and SwiftUI cards share the renderer and preference,
  including native hosting and accessibility.
  Counts use Plex leaf/viewed-leaf fields, Jellyfin/Emby unplayed-item counts,
  and existing local Share episode rollups. They never query episodes per card,
  use online episode totals, or sum duplicate servers. Cross-server counts
  follow the same source as watch state. Child mutations invalidate snapshots
  until the next batched refresh instead of guessing a decrement. Movie actions
  never invalidate unrelated episode counts. Count-only refreshes wait for
  confirmed server delivery so they cannot undo an optimistic watched action.
- **Discovery marks** — the requestable plus, requested clock, and unowned
  binoculars fit the same density-scaled square and corner clearance as the
  watched badge: 21pt on standard touch cards, 42pt on standard TV cards.
  Symbol bounds, not font point sizes, determine their footprint; mobile marks
  never inherit TV's 36pt minimum. Their existing grey/white treatment and
  ownership/request meanings are unchanged. In-player credits use the same
  renderer with their card-width-scaled size.
- **Theme** — `Theme`, `ThemeOption` (System / Dark / Pure Black / Light) and
  the per-profile theme model, observed at the app root.
  Gradient Backgrounds is a separate default-on profile preference, transferred
  with that profile. Turning it off restores the existing flat page/settings
  fills without changing the selected theme or music-player appearance.
  The static mesh layout is adapted from tresby's
  [Ambient proposal (#75)](https://github.com/brandomoore/Plozz/pull/75), with
  separate light, dark, and near-black treatments rather than another theme.
  Home and movie/show detail pages own their tint/cache locally on both platforms.
  They use the artwork actually displayed by their own hero; covered pages cannot
  replace another page's colours. Home sources publish only while frontmost.
  Palette extraction reuses cached artwork, runs
  off the main actor, waits 180ms for navigation to settle, and retains at most
  24 artwork-identity-keyed palettes. Replaced/cancelled sources cannot publish
  stale colours or clear another source. Only the background leaf observes the
  colour array; no full-screen clock, blur, or per-frame page invalidation runs.
  Reduce Motion disables the palette crossfade. Dark uses a softer wash and Black
  retains more visible colour while staying darker; Light's palette is unchanged.
  Fullscreen Hero Home uses half the artwork tint's saturation on both platforms,
  retaining its hue and brightness without desaturating the hero image. Showcase,
  detail pages, and untinted stock gradients retain their existing treatment.
  Tint saturation is page-scoped and shared with native card fills/textures.
  Settings panels, detail information cards, and PIN digit/delete keys share a
  5%-white wash in Dark and Black, or a 5%-black wash in Light, so they remain
  distinct without replacing the gradient's colour. SwiftUI surfaces keep their
  shadow and a matching hairline edge. Gradient Off or Reduce Transparency restores the original solid
  surface and border; unrelated raised cards remain unchanged.
  PIN keys retain their existing focus, press, and hover treatment. Their resting
  gradient fill and edge also apply on systems before Liquid Glass.
  The detail information band retains its darker 40%-opaque surface.
  Compact mobile detail metadata and actions reveal the page gradient instead
  of covering it with a solid rectangle; Gradient Off and Reduce Transparency
  retain the original opaque base. The artwork's existing readability fade stays.
  Native tvOS cards display their local portion of a shared page-mesh texture,
  with the information band and wash precomposed because TVUIKit replaces fill
  alpha. The texture is created only when a card needs it, its longest edge is
  capped at 480 pixels, and it is rebuilt only for palette or viewport size
  changes. Scrolling updates each background's sampling rectangle, not its
  texture or foreground content. `settingsPageBackground()` provides the same
  page-aligned texture to Settings' focusable information cards, without the
  detail page's darker information band. Nested workspace pages inherit that
  background instead of painting another gradient. Native focus,
  clipping and text remain TVUIKit-owned.
  Text stays opaque and native focus geometry is unchanged. Gradient Off or
  Reduce Transparency restores both the solid band and solid card fills.
- **App-owned dialogs** — `plozzSheet` owns one opaque, theme-aware surface:
  the native presentation background on iPhone/iPad, and the existing rounded
  overlay card over `PlozzDialogBackdrop` on tvOS. TV uses a clear native
  full-screen presentation because its glass sheet leaves refracted edge strips
  around custom backgrounds. The shared surface honors Gradient Backgrounds in
  Dark, Black, and Light without adding blur, including with Reduce Transparency.
  `AppBackground` and `SettingsPageBackground` defer to that surface inside a
  dialog rather than repainting smaller rectangles over it. Use `.floatingCard`
  only for content already owning its dimmer and `.overlay` card.
  `plozzFullScreenCover` resets background ownership for nested page flows;
  bindings, dismissal callbacks, and explicit preferred color schemes remain
  caller-owned. Native alerts and confirmation dialogs remain system-styled.
- **Focusable building blocks** — focus-aware buttons, cards, tab bars,
  parallax containers, brand QR code rendering, code-font numerals.
  Native card focus observation is separate from explicit focus requests.
  Caption, overlay and transition-anchor readers update without rebuilding
  the poster's artwork loader or context menu.
- **QR images** — `QRCodeView` renders on a worker actor, including Core Image
  initialization. Settings, account authorization and device pairing share it.
  Payload/correction/mask changes replace the request; cancelled work cannot
  publish an old code. Theme tint is applied to a transparent mask without
  rerendering. The memory-only cache retains at most 8 images and 16 MiB of
  pixels; payloads are never persisted or included in error logs.
- **Mobile content tabs** — `PlozzContentTabs` owns the touch-sized horizontal
  navigation shared by library modes and series seasons. Selected tabs use the
  existing glass capsule style; inactive tabs are secondary text without a
  capsule. Typography, spacing, 44pt minimum targets, selected accessibility
  traits, long-label fitting, and selected-tab reveal live in one component.
  It respects Reduce Motion when revealing a new selection and re-reveals after
  viewport, text-size, or option changes. Callers supply localized or verbatim
  labels and page keylines; native app tabs and tvOS focus controls are separate.
- **Mobile media corners** — posters and Continue Watching share a 12pt artwork
  radius at every display size and responsive width. Borderless cards use that
  radius directly; glass frames add their inset to remain concentric. Loaded
  artwork, missing-art placeholders, and skeletons agree. TV rounding is unchanged.
  Regular mobile artwork progress bars use an 8pt minimum height, leaving their
  length and the separate Continue Watching, hero, and TV bars unchanged.
  Mobile library, episode, and download artwork uses the same metric, keeping
  its caption clearance consistent with its actual corners. Mobile captions use
  a shared 4pt horizontal inset from the artwork edge, independently of their
  unchanged bottom corner clearance. Poster, landscape, music, download, and
  episode captions and skeletons share it; TV caption layout is unchanged.
  Home library names
  and server names share one leading-aligned text column beside the provider mark.
- **Provider marks** — IPTV uses coral-red while Media Share keeps teal.
  `ProviderBrandMark` owns their shared icon and badge tints, including deeper
  colors on white focus cards and brighter colors on black focus cards.
- **Media-row focus** — a dedicated modifier owns the row's `FocusState`
  and supplies its binding to tracked cards. Focus callbacks and prefetch
  bookkeeping must not invalidate the row that constructs all card inputs.
  Entry-gate state remains observable for episode rows; ordinary Home rows
  retain native column-aligned entry and cover/return behavior.
- **Grouped settings interactions** — `SettingsSectionGroup` uses explicit
  native switch toggles and menu pickers on iOS/iPadOS. Standalone mobile
  settings/Live TV controls and the shared `SettingsSwitchToggleStyle` also
  use the system switch; do not draw a replacement track or knob, wrap the
  toggle in a button, or override its native animation/accessibility.
  The switch alone clears inherited tint so monochrome page accents do not
  hide its thumb against the enabled track; neighboring controls keep their tint.
  tvOS uses native On/Off toggles with shared settings row typography, not drawn
  switch tracks. Focus-gated and side-effectful action rows retain their owned
  buttons and show the same On/Off text.
  Custom value menus use `SettingsMenuLabel` to show
  the selected value with up/down chevrons, matching editable pickers rather
  than read-only `LabeledContent`. Navigation keeps its right-facing chevron.
  Unavailable settings use a natively disabled control with a short explanation.
  Share-only streaming quality shows a disabled **Original quality** picker with
  **Unavailable for network shares.** beneath it; saved server-quality preferences
  are left untouched. Compatible-server quality menus remain enabled.
  A visual group occupies one native List cell; automatic
  pickers can promote their menu to that whole cell and intercept neighboring
  navigation links or controls. Keep picker activation local without replacing
  the shared group surface, separators, or tvOS control styles.
- **Detail-opening feedback** — `detailOpenFeedback()` provides one soft haptic
  when a mobile media, person, downloaded-show, or music detail page first
  appears. The page owns the one-shot state, outside loading content, so data
  refreshes, returning from playback, and popping a nested detail do not repeat
  it. Opening a new page emits again; tvOS and devices without haptics are silent.
- **Touch action feedback** — `TouchFeedback` gives mobile skip actions a light
  impact and committed scrubs / explicit reorder moves a selection tick. Native
  List drag reordering retains system feedback without a second app vibration.
  Watchlist actions acknowledge the press immediately with a light tap and stay
  silent on success; an error haptic accompanies a failed save and rollback.
  Manual watched actions retain the immediate tap and separate confirmation of
  durable outbox acceptance, not eventual server synchronization.
  Favorites confirm successful writes. Capture asynchronous completion haptics
  at the user action: they are one-shot and cancelled when the app deactivates
  or the profile changes, rather than expiring during a slow foreground save.
  Scrolling, menu opening, automatic playback and background persistence/retry
  events do not trigger action feedback.
- **Async artwork** — `FallbackAsyncImage` and `ArtworkImageCache`: an
  on-disk + in-memory image cache shared with `MetadataKit`'s URL cache,
  with profile-scoped source choices in Appearance > Artwork. Recommended uses
  metadata providers first for Home and library Showcase heroes, movie/show detail
  backgrounds and logos, and textless Continue Watching artwork. Ordinary rows,
  related-title posters, and episode thumbnails remain library-first. Detail hero
  placement is carried through resolution, cache identity, prewarming, and mobile
  reflections without changing the surrounding page's card policy.
  Shared hero/reflection first-paint results are qualified by source and provider
  policy so changing those settings cannot reuse a previous provider's winner.
  Library-first and metadata-provider-first
  presets initialize source choices for Home, Continue Watching, Browse,
  Search, Watchlist, Details, Episodes, Playback, Music, Top Shelf, and Downloads
  where available. Editing a view enters Custom mode; choosing any preset
  replaces the whole configuration. The shared editing and presentation contract
  lives in [FeatureSettings](../FeatureSettings/README.md#invariants). Cards retains
  card presentation controls, not app-wide artwork policy. Missing artwork can
  fall back to the other source. Provider-first waits for lookup and image decoding
  to finish, including time queued behind other requests; a short first-paint
  budget must not permanently select cached library artwork instead. Existing
  network/image-load deadlines still bound failures, and cancellation releases
  the view without painting a fallback for a cancelled request.
  Provider enablement/order is household-wide in Metadata Providers; changing
  appearance never enables a provider. The old library-artwork choice migrates to each profile,
  and the new preference transfers/syncs with that profile.
  Metadata Providers links directly to the active profile's Artwork preferences.
  Reciprocal links return to an existing page instead of stacking duplicate pages.
  Library-first heroes honor the server-selected backdrop or primary share
  sidecar rather than choosing a different image for Details or avoiding artwork
  on the focused card. Recommended retains varied library Details backgrounds as fallbacks;
  metadata-provider-first retains provider lookup and artwork variation. The
  choice applies equally to first paint, prewarming, mobile reflections, and
  later visits; alternative images remain fallbacks if the selected one fails.
  Continue Watching's recommended textless lookup is separate from source
  preference: explicit library-first uses supplied artwork without checking it
  online. A selected textless backdrop has priority over both ordinary provider
  and library images, including synchronous cache seeding. If that image fails,
  the normal source preference still orders the fallbacks. When textless artwork
  is unavailable, Recommended keeps a library background ahead of a metadata
  poster with baked-in lettering; episodes use only their series background.
  An explicit metadata-provider choice still gives providers priority. Missing
  or unreadable library backgrounds retain the metadata-poster fallback.
  Native tvOS and SwiftUI cards both settle cold textless lookups before
  selecting a background;
  the native poster and its focus owner remain mounted while waiting.
  `ContinueWatchingArtworkSource` is shared by rendering and lookahead on TV and
  mobile. It prepares the selected backdrop and processed logo, including
  metadata-provider fallbacks and SMB references, in the existing bounded caches.
  `ArtworkPrefetchWindow` retains only the current nine-card window, cancels work
  that leaves it, and reuses overlapping completed requests. Source or policy
  changes replace those requests; leaving the row cancels them. Background
  metadata has a separate one-request gate and image decoding uses the background
  lane. Neither focus callbacks nor touch scrolling await any preparation.
  Textless lookups coalesce per title; cancelling speculative work cannot cancel
  a visible consumer or turn an unfinished lookup into a cached miss.
  `TextlessBackdropIndex` keeps synchronous first-frame reads, but JSON encoding
  and atomic persistence run on a utility serial queue, never the main actor.
  One in-flight snapshot and coalesced pending changes preserve newest-answer
  ordering without a write backlog. Failed writes retain dirty state for a later
  save and log a numeric error code; they do not spin on automatic retries.
  The existing 400-entry budget and 14-day read expiry still apply.
  SMB selections retain local and online candidates in the shared
  catalog, including typed network-file references and their access gate.
  SwiftUI, native Browse cells, detached hosts, and prewarmers use the same
  effective policy. Cache identities include source and provider policy; a
  settings change replaces the image selection, not ordinary focus movement.
  A fallback is stable for that appearance, not a promise that an online source
  has no image. Playback system art receives an explicit snapshot.
  Top Shelf exports resolved images into its shared container. Downloads capture
  the selected artwork when queued; existing offline artwork is not re-fetched
  after a settings change. Clip-specific extra thumbnails, people, channel
  branding, and spoiler protection retain their separate semantics.
  When card captions are hidden, folder and missing-art placeholders carry the
  existing spoiler-safe title inside the artwork slot. Loaded art remains
  label-free, visible captions are not duplicated, and loading/failure never
  changes card height. Spoiler blur applies to images, not fallback names.
- **Content state** — `ContentStateView` renders the `LoadState`
  loading / loaded / empty / failed states identically across features.
- **Mobile settings surfaces** — `SettingsPageSurface` keeps the native scroll
  viewport full-width so the title's scroll-edge blur reaches both navigation
  edges. Horizontal safe-area padding insets the content without narrowing that
  viewport; both list rows and grouped scrolling panels retain their spacing.
  Settings subpages default to the system's centered inline navigation title on
  both iPhone and iPad, including the iPad detail column. Root destinations keep
  their leading large titles; only the Settings root overrides the shared surface
  title mode. Modal utility pages also use inline titles without custom fonts.
  The compact Settings drawer keeps its title leading beside a native close
  button at the top, switching to a centered inline title only after scrolling.
  Both Settings roots use a 16pt content inset matching the native leading title;
  subpages retain 24pt insets. Alignment never narrows the scroll viewport.
  Its first section uses a tighter 8pt content margin.
  Profile/PIN resealing observes the page, not a zero-height row that adds spacing.
- **Subtitle appearance** — editing the live subtitle look now happens in
  the player (`FeaturePlayback`'s in-player Style screen), not via a shared
  Settings card.
- **Cast & metadata cards** — `CastRowView` and friends, used by Home /
  detail. Common Sense marks keep a transparent background in every theme;
  the palette selects dark checkmark ink in Light and white ink in dark themes,
  preserving the green ring and the existing optical size.
- **Detail information focus** — the tvOS About/Ratings/Information band uses
  native focus with at most 2% growth and 6pt of expansion per edge, leaving
  clearance in its 18pt gutters. Focused read-only cards and card buttons draw
  above their peers. This policy does not change ordinary media-card growth,
  custom focus styles, or touch layouts.
- **Native artwork focus comparison** — launch the separate tvOS focus host
  with `--native-artwork-focus-comparison`. It compares the current poster,
  a single-image poster, a content-masked poster with separate overlays, and a
  plain native card. The goal is to preserve outer enlargement and the native
  highlight without extra zoom/cropping inside the artwork, not disable growth.
  The single-image case prepares rounded transparent artwork and overlays once,
  then enables `masksFocusEffectToContents`; no custom focus transform is used.
  Geometry checks on tvOS 26.5 found preserved composition and overlay insets
  while enlarging 400×225 artwork to 440×247.5. Those checks did not validate
  the highlight bounds: subsequent physical testing exposed an offset highlight
  mask on the single-image `TVPosterView`. Content masking alone also leaves
  separate native overlays floating at a different depth. Neither is an
  accepted production replacement.
  `NativeArtworkFocusComparisonHostedTests` checks real focus, enlargement,
  baked-in image landmarks, overlay-marker pixels, visible highlight, and action
  delivery. Run it with
  `tools/run-focus-tests.sh -only-testing:PlozzFocusTests/NativeArtworkFocusComparisonHostedTests`.
  This fixture does not change production style. Its composited chrome is
  deliberately static: live content updates and image replacement during focus
  need separate coverage before adoption. Alpha masking also has a documented
  rendering cost; these geometry checks do not establish physical frame pacing
  or full Siri Remote motion behavior.
- **Native library artwork layout** — `NativeTVLibraryCell` leaves UIKit's
  `contentView` at the full cell size and owns the artwork as a separate direct
  child. Resizing `contentView` to exclude captions caused every repeated
  layout pass to grow then shrink its hosted artwork, invalidating SwiftUI
  geometry even when the final size was unchanged. The artwork remains directly
  under the focused cell for TVUIKit projection, with captions outside it and
  detail transitions referencing the artwork rather than the full cell.
- **Native poster focus** — the shared `NativeTVPoster` uses a
  `NativePosterButton`, not `TVPosterView` or a `TVCardView` ancestor. Its
  `UIImageView` retains native enlargement, remote motion and the moving
  specular highlight. Portrait rows and native Browse cells share
  `NativePosterImageView` and UIKit's rectangular focus mask:
  the small native internal crop (about 1-2% in hosted measurements) is an
  intentional tradeoff for retaining that native surface.
  The alpha-derived highlight mask produced an offset crescent at extreme tilt.
  Continue Watching, landscape/square artwork, transparent landscape library
  covers keep their no-internal-zoom alpha-masked path.
  Alpha-masked images arm native enlargement only on actual focus and release
  it after the native defocus animation. This keeps newly mounted episode
  previews at their 480pt artwork width with 40pt gaps, rather than painting
  every preview at its enlarged focus width. Portraits keep UIKit's mask active
  at rest so opaque artwork retains its native rounded corners.
  Portrait artwork and placeholders are opaque rectangles; UIKit alone rounds
  the visible surface. Pre-rounded alpha pixels beneath that native mask create
  a second corner silhouette that can separate from the highlight. Transparent
  portrait sources receive the same dark backing as missing artwork.
  Alpha-masked landscape/square artwork remains rounded in the bitmap.
  Native loading cards bake their neutral fill into that same artwork plane.
  Only the spinner belongs on the nearer overlay plane; a full rounded fill
  there scales independently and exposes the underlying image as an extra rim.
  Corner flags, count-tile backgrounds and legibility washes are composited into
  the artwork itself. Portrait count digits and floating status/library marks
  use a cached foreground on `overlayContentView`. That surface receives a nearer
  native depth projection; its badge alone is aligned to the public artwork
  viewport so it does not drift outside the image.
  Async logos, focus-reactive progress and animated content remain live in
  `overlayContentView`; edge backgrounds and full-card legibility washes do not. Continue Watching
  keeps its established size, reflection, logo position and resume chrome without
  top-corner watch marks, including when series artwork is disabled. This uses
  the Continue Watching presentation area, not instant-play or resume-chip flags:
  extras and other playable cards retain the profile's watched/unwatched marks
  independently of their resume chrome. Spoiler-hidden cards still suppress marks.
  Its adaptive logo dimming and the shared bottom scrim
  are drawn into the artwork; projecting those backgrounds with the live overlay
  creates a dark rim outside the focused image. Captions stay outside it. Transparent
  landscape artwork retains its alpha, and protected/extended artwork is prepared before
  normalization. Portrait count tiles stay flush. Their digits center inside the
  visible tile using the native crop allowance (2pt horizontally, aspect-scaled
  vertically). Badge destination geometry updates in UIKit's focus coordinator
  at the focus event, not in a completion callback. The poster and foreground
  images remain identical across focus changes: no late bitmap replacement,
  delayed number repositioning, custom poster scale, spring, duration or timer.
  Background/foreground indicator layers share the existing bounded bitmap cache;
  foreground identity uses the visible status and badge geometry, not unrelated
  playback progress or download state. Different posters with identical badges
  reuse the same concrete pixels; status/count, environment, size and scale
  changes still invalidate them. Background and combined layers retain all
  progress, download and scrim inputs. Mobile and
  landscape cards keep their combined indicator rendering.
  The button keeps the existing artwork slot and committed-bounds bitmap
  preparation, preserving row pitch and captions.
  SwiftUI measurement is side-effect-free: candidate widths never resize the
  native image or trigger artwork/status rendering. A mounted poster prepares
  its latest inputs at the committed UIKit size, with a per-poster autorelease
  pool for temporary raster surfaces. Creation uses shared loading surfaces
  (bounded to 8 entries, 4 MiB), not per-item composition.
  Cold source-image conversion runs on the same two-operation worker lane as
  Browse, never synchronously inside native poster layout. The existing native
  image view receives the finished pixels without replacing its focus owner.
  Identical pending requests coalesce; replacement, detachment and dismantling
  cancel work, and generation checks reject stale completions. A replacement
  shows a safe placeholder rather than the previous title or unprotected artwork.
  SwiftUI indicator and protected/extended treatment preparation still requires
  the main actor. Final Home and Browse bitmaps share one memory-budgeted cache;
  warm returning artwork paints immediately, and a memory warning prevents
  in-flight work from repopulating a purged cache.
  Ordinary artwork uses one final normalized/composited surface rather than
  retaining an additional unmarked full-size copy per card. Identical status
  presentations share concrete pixels in a separate 24 MiB/64-entry cache;
  cached images do not retain a SwiftUI renderer or its environment.
  Status-cache pixels remain unrounded until the final composite. Rounded alpha
  is applied once to alpha-masked artwork after washes and marks are combined; clipping the
  individual draws exposes pale artwork through an antialiased count-tile edge.
  The inverse mask's outer eraser extends beyond the allocated raster, including
  the extra row/column at fractional sizes. Artwork uses committed view bounds;
  Browse aligns its view and bitmap to the same physical pixels at 1x and 2x.
  Ordinary watch flags/check badges use opaque white; episode-count tiles keep
  their dark fill and white text.
  This keeps lazy-row estimation out of the expensive rendering path without
  adding another observable loading state to the row.
  Portrait television rows fit six full cards and a quarter of the seventh at
  standard display size. `PlozzMetrics.portraitRowSlotWidth` uses the actual
  navigation-safe viewport and visible card margins, shared by loaded cards,
  placeholders and pinned-sidebar scroll parking. Only viewport-width changes
  update sizing; scrolling does not invalidate the row. Showcase's row viewport
  reaches the trailing screen edge with native navigation as well as pinned
  navigation. Showcase's nested motion surfaces expand their leading viewport
  with matching safe-area padding so SwiftUI does not cull native cards while
  they are still visible in the overscan gutter. The trailing viewport is not
  expanded, preserving row density and pinned slot parking. Hosted loaded-artwork
  checks cover both screen edges in both scroll directions and navigation styles.
  Display-size preferences still adjust density; library Browse
  grids, landscape/episode card widths and mobile sizing are unchanged.
  Native Browse uses the correction for both borderless and framed system-focus
  cells. Debug's `--original-library-posters` opts out of Browse only.
  The collection cell remains the focus and selection owner,
  with the same opaque artwork, native ancestor-focus adjustment, and immediate
  foreground alignment as row posters. Reuse clears both image layers.
  Collections, playlists and folders have no watch/progress indicators. A series
  or season with zero known unwatched episodes never falls back to an unwatched
  flag when its aggregate played boolean is absent or false.
  Captions and detail transitions retain their existing owners. Custom focus,
  SwiftUI content inside native framed cards, and mobile retain their existing
  rendering paths; none uses the replaced poster control.
  The shared cache is bounded to 24 MiB and 64 entries, keyed by source identity,
  size, scale, and visible presentation settings. These limits exclude images
  retained by visible cells and are not a process-memory budget. Content changes
  invalidate composition; focus movement alone does not. Full SwiftUI
  environments and providers are not retained in the shared cache.
  `NativeLibraryCardHostedTests` covers live episode-count/artwork replacement,
  focus retention, unchanged-configuration reuse, and cache accounting. Shared
  poster regressions compare painted landmarks with native enlargement for
  portrait, landscape, square and Continue Watching artwork, alongside live
  overlays, focus requests, captions and transparent library covers. Portrait
  coverage bounds the approved crop, verifies UIKit rounds opaque portrait pixels
  at rest/focus/defocus, and samples fixed motion-effect offsets with moving
  highlights on gray artwork. Those offsets do not simulate continuous remote
  touch or its focus-movement-hint transform; actual corner tilt needs a user check.
  Focused counts check actual visible digit padding, not just layout bounds. Corner-flag
  regressions count painted pixels outside the artwork's actual top/right edges,
  and real Home cards cover count/watch/preference updates without focus replacement.
  Earlier real TV Shows comparisons recorded more native hitch counts with this
  renderer; a performance improvement has not been established. It is enabled
  for the requested zoom correction, not to claim better scrolling. See the
  [actual-library measurement protocol](../../docs/performance-debugging.md#actual-library-poster-comparisons)
  for the workload, numbers and transport limitations.
  Physical comparisons must use the actual populated library, repeated fresh
  launches, matched startup/settling times and input cadence, and separate idle
  measurements. Preserve the profile's servers, filters and sorting; retain
  background-activity evidence rather than assuming a quiet app from its age.
- **Continue Watching logo contrast** — logo-overlay cards use a 40% base
  artwork dim, reduced for dark artwork and increased by up to 25 percentage
  points when the logo blends into its background (65% maximum). The dim sits
  behind the logo. Their logo subtree always uses the on-dark-artwork treatment,
  independent of the page theme; coloured logos retain their palette. Home/detail
  and Spotlight heroes still adapt monochrome ink to their own background, so
  Light keeps dark hero logos.
  Continue Watching cards and focus-driven hero titles keep their text fallback
  invisible during logo lookup and decoding, preserving its layout space.
  Text appears only after resolution finds no usable logo (or there are no logo
  sources); cached logos still paint immediately. Completion is request-scoped,
  so a cancelled or missing logo for one title cannot reveal text for the next.
- **Series artwork identity** — episode-backed cards normalize through
  `MetadataQuery.seriesScoped` before creating a series artwork subject. Child
  IDs and Plex episode GUIDs must not become show IDs. Explicit series IDs,
  show-scoped anime IDs, account scope, and title-matching restrictions survive.
  Corrected logo queries share the series metadata-cache key and do not reuse
  misses stored under an episode ID; the image/memo caches remain shared.
  The textless-backdrop index also qualifies its account and series lookup, so
  a legacy ID-only miss cannot keep suppressing a newly resolvable logo.
  Providers applying parent enrichment to episodes/seasons must publish the
  inherited identifiers under `Series*` namespaces; unqualified IDs may identify
  the child. Share catalog read projection adds these scopes before an episode's
  local NFO overlays its own IDs, so persisted enrichment needs no rescan.
- **Circadian Mode** — profile-scoped warmth/dimming still uses the window-wide
  multiply tint while active. Disabled, daytime, and zero-strength states remove
  the view and its filter rather than leave an opaque white layer above video.
  Fading back to neutral removes it on completion; reactivation or a profile
  change invalidates the old completion. The observer remains alive so schedules
  and previews can reinstall the tint. Hosted tests cover both off and active
  behavior; layer removal alone is not proof of HDR10+ HDMI passthrough.

## Invariants

- **No Jellyfin/Plex specifics.** Components take `CoreModels` value
  types only.
- **No persistence other than caches.** Settings live in feature modules
  (`FeatureSettings`, `CoreModels.ProfileStore`).
- **Compiles without UI.** Files are guarded by `#if canImport(SwiftUI)`
  / `#if canImport(UIKit)` so the package still builds on Linux.

## Where to look first

- `ContentStateView.swift` — the unified load-state renderer.
- `ArtworkImageCache.swift` + `FallbackAsyncImage` — shared image cache &
  the server-first / fallback rendering pattern.
- `Theme.swift` — color/themes used everywhere.
