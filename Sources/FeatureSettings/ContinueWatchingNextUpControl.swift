#if canImport(SwiftUI)
import CoreModels
import CoreUI
import SwiftUI

public struct ContinueWatchingNextUpControl: View {
    public let visibility: HomeLibraryVisibilityModel

    public init(visibility: HomeLibraryVisibilityModel) {
        self.visibility = visibility
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle(
                "Merge Next Up rows",
                isOn: Binding(
                    get: { visibility.visibility.mergeNextUpIntoContinueWatching },
                    set: { visibility.setMergeNextUpIntoContinueWatching($0) }
                )
            )
            .toggleStyle(SettingsSwitchToggleStyle())
            .disabled(!visibility.isGlobalRowEnabled(.continueWatching))
            .accessibilityIdentifier("home-merge-next-up")

            if visibility.isGlobalRowEnabled(.continueWatching) {
                Text("Include next episodes in this section.")
                    .settingsHelperText()
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("Add Continue Watching to Home to include Next Up.")
                    .settingsHelperText()
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
#endif
