#if canImport(SwiftUI)
import CoreModels
import CoreUI
import SwiftUI

/// Height-channel rendering and its speaker bed for this device's audio setup.
struct HeightChannelControl: View {
    @AppStorage private var isEnabled: Bool
    @AppStorage private var layout: HeightChannelLayout

    init(defaults: UserDefaults = .standard) {
        _isEnabled = AppStorage(
            wrappedValue: HeightChannelSettingsStore.defaultEnabled,
            HeightChannelSettingsStore.enabledKey, store: defaults
        )
        _layout = AppStorage(wrappedValue: .default, HeightChannelSettingsStore.layoutKey, store: defaults)
    }

    /// The Advanced page row on Apple TV; empty where the engine cannot render.
    static var advancedRows: [SettingsSplitRow] {
        guard #available(tvOS 26.0, iOS 26.0, *) else { return [] }
        return [SettingsSplitRow(id: "height-channels", title: "Audio") { HeightChannelControl() }]
    }

    var body: some View {
        SettingsControlRows {
            SettingsDescribedControl {
                Toggle("Spatial audio (height channel support)", isOn: $isEnabled)
                    .accessibilityIdentifier("height-channels-toggle")
            } description: {
                Text("Uses PCM for supported TrueHD Atmos and DTS:X tracks; lossy audio over AirPlay.")
            }
            if isEnabled {
                SettingsMenuRow(
                    title: "Rendering layout", value: Text(verbatim: layout.rawValue),
                    subtitle: "DTS:X heights require 7.1.4 or 9.1.6."
                ) {
                    Picker("Rendering layout", selection: $layout) {
                        ForEach(HeightChannelLayout.allCases, id: \.self) { option in
                            optionTitle(option).tag(option)
                        }
                    }
                }
                .accessibilityIdentifier("height-channels-layout")
            }
        }
    }

    private func optionTitle(_ option: HeightChannelLayout) -> Text {
        if option == .default { return Text("\(option.rawValue) (Default)") }
        return Text(verbatim: option.rawValue)
    }
}
#endif
