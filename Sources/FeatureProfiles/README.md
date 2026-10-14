# FeatureProfiles

The "Who's watching?" launch picker and the profile editor — Plozz's
household multi-user UI on top of `CoreModels.ProfileStore`.

## Responsibility

- `ProfilePickerView` — the launch / "Switch Profile" picker. Shows the
  household's profile tiles (avatar + name), focusable, with an "add
  profile" tile that opens the editor. `AppShell.ProfileSelectionView`
  hosts this for both the launch flow and Settings → Switch Profile.
- `ProfileEditorView` — create / rename / restyle a profile (name,
  `avatarSymbol` SF Symbol, color from `ProfileTileColor` palette,
  account subset, Plex Home-user mapping).
- `ProfileAvatarView` — renders a profile's photo, emoji, or SF Symbol.
  Native navigation labels use `rendersAsImage` so the circular crop, point
  size, and original colors survive native image extraction. This includes
  iOS toolbar buttons when the iPad app runs on Mac; framing a resizable photo
  alone does not constrain the extracted image. Keep the native button style
  and hit target. Palette resolution lives here, not in Foundation-only `CoreModels`.
- `ProfileTileColor` — the colour palette and the deterministic
  `colorIndex → Color` resolution used by avatar / tile / picker.
- `ProfilePhotoCandidate` — value type for profile photos borrowed from
  connected accounts and Plex Home users.

## Invariants

- **Non-secret only.** Profiles are non-secret metadata; tokens belong
  to `FeatureAuth.AccountStore`.
- **Default profile is special.** Stable id
  `ProfileStore.defaultProfileID` (`com.plozz.profile.default`); `nil`
  settings namespace; cannot be removed. Don't break the upgrade path.
- **Photo fallback.** Borrowed photos fall back to the profile's emoji or
  symbol if loading fails; preserve symbol-only profiles on both platforms.
- **Profile-aware everywhere.** Any feature reading per-user state
  (settings, watched, recommendations) must scope through the active
  profile id from `CoreModels.ProfilesModel`.

## Where to look first

- `ProfilePickerView.swift` + `ProfileEditorView.swift` — the two UI
  surfaces.
- `ProfileTileColor.swift` — color palette resolution.
- `CoreModels/ProfileStore.swift` — the persistence layer this UI edits.
