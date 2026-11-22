import Foundation

/// The speaker bed that TrueHD Atmos and DTS:X height channels are rendered to.
public enum HeightChannelLayout: String, CaseIterable, Sendable {
    case fiveOneTwo = "5.1.2"
    case fiveOneFour = "5.1.4"
    case sevenOneTwo = "7.1.2"
    case sevenOneFour = "7.1.4"
    case nineOneSix = "9.1.6"

    public static let `default`: Self = .nineOneSix
}

/// Height-channel rendering belongs to this device's audio setup, not a profile.
public struct HeightChannelSettingsStore {
    public static let enabledKey = "com.plozz.heightChannelsEnabled"
    /// The key builds used before upstream removed the feature, so a saved layout survives.
    public static let layoutKey = "com.plozz.spatialAudioLayout"
    public static let defaultEnabled = true
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// The bed to render, or `nil` while height-channel rendering is off.
    public func renderingLayout() -> HeightChannelLayout? {
        guard defaults.object(forKey: Self.enabledKey) as? Bool ?? Self.defaultEnabled else { return nil }
        return defaults.string(forKey: Self.layoutKey).flatMap(HeightChannelLayout.init) ?? .default
    }
}
