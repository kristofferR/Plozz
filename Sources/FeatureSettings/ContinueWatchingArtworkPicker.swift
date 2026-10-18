#if canImport(SwiftUI)
import SwiftUI
import CoreUI

/// Card picker for the Continue Watching card style, mirroring the spoiler,
/// theme and music-player pickers: a preview of each option with the active card
/// ringed.
///
/// A picker rather than a switch on purpose. Both options put artwork on the
/// card — the choice is only *which* artwork — so any on/off label ("display
/// artwork", "display logo and artwork") implied that turning it off left the
/// card empty. Two named previews say what actually happens.
struct ContinueWatchingArtworkPicker: View {
    @Binding var style: ContinueWatchingArtworkStyle
    @Environment(\.themePalette) private var palette

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            ForEach(ContinueWatchingArtworkStyle.allCases, id: \.self) { option in
                PreviewCard(
                    title: option.displayName,
                    detail: option.detail,
                    isSelected: style == option,
                    accent: palette.accent,
                    compact: true,
                    swatchHeight: 200,
                    swatchAspectRatio: swatchAspectRatio,
                    titleLineLimit: nil,
                    titleSizeGroup: ContinueWatchingArtworkStyle.allCases.map(\.displayName),
                    action: { style = option }
                ) {
                    ContinueWatchingArtworkSwatch(
                        style: option,
                        cornerRadius: PlozzTheme.Metrics.Radius.content
                    )
                }
                .accessibilityLabel(Text(option.displayName))
                .accessibilityAddTraits(style == option ? .isSelected : [])
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var swatchAspectRatio: CGFloat? {
        #if os(tvOS)
        nil
        #else
        6.0 / 5.0
        #endif
    }
}
#endif
