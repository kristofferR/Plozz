# TopShelfKit

Publishes the tvOS **Top Shelf** snapshot (the focused-row art strip on the
home screen) from the app's domain models into the shared App Group
container, where the Top Shelf extension reads it.

## Responsibility

- `TopShelfSnapshot` — the on-disk Codable snapshot shape (sections,
  display titles, item ids, artwork URLs). The **extension** depends only
  on this type (and `TopShelfStore`), keeping `CoreModels` out of the
  extension's memory budget.
- `TopShelfStore` — read/write helper around the shared App Group
  container. Used by both the app (to write) and the extension (to read).
- `TopShelfPublisher` — app-side mapping from `[MediaItem]`
  Continue-Watching + Latest rows onto a `TopShelfSnapshot`, with empty-row
  pruning. Always writes (even empty) so a freshly-signed-out state clears
  the shelf.

## Invariants

- **App Group container is the only side-channel.** No network, no
  keychain.
- **No secrets in the snapshot.** Item ids and artwork URLs only — tokens
  for token-protected art are scoped to a refresh strategy outside this
  module.
- **`CoreModels` only imported by the app, not the extension.** Don't add
  imports above `Foundation` to `TopShelfSnapshot` / `TopShelfStore`.
- **Idempotent.** Republishing the same snapshot is cheap and side-effect
  free.
- **Artwork export stays off the main actor.** Home resolves artwork with its active
  policy, then awaits `TopShelfPosterComposer.encodedArtwork` before publishing.
  Resolving an image on the main actor must not also encode it there.
- **Reuse before encoding.** Matching cached JPEG/PNG bytes pass through; opaque
  images use JPEG at quality 0.8 and alpha images retain PNG. Plain shelf posters
  copy those bytes directly. Resume artwork is composited once into opaque JPEG.
- **Visible artwork has priority.** Top Shelf uses the existing background lanes
  for metadata lookup and image decoding.

## Where to look first

- `TopShelfPublisher.swift` — domain → snapshot mapping.
- `TopShelfSnapshot.swift` — on-disk shape.
- `TopShelfStore.swift` — shared-container I/O.
