@preconcurrency import AetherEngine
import CoreModels
import FeaturePlayback
import Foundation

extension PlozzigenVideoEngine {
    /// Requests object rendering for audible on-demand playback, which upstream
    /// leaves off. The layout is the rendering bed, not detected speakers: Aether
    /// chooses PCM or APAC for the route and keeps ordinary channel audio for
    /// tracks it cannot render.
    nonisolated static func requestingHeightChannels(
        _ options: LoadOptions, outputPolicy: LiveChannelOutputPolicy,
        layout: HeightChannelLayout? = HeightChannelSettingsStore().renderingLayout()
    ) -> LoadOptions {
        var options = options
        #if os(tvOS) || os(iOS)
        if #available(tvOS 26.0, iOS 26.0, *), let layout,
           outputPolicy.isAudible, !outputPolicy.sharesAudioSession {
            options.objectAudioRendering = .render(speakerLayout(layout))
        }
        #endif
        return options
    }

    nonisolated static func speakerLayout(_ layout: HeightChannelLayout) -> SpatialSpeakerLayout {
        switch layout {
        case .fiveOneTwo: .l512
        case .fiveOneFour: .l514
        case .sevenOneTwo: .l712
        case .sevenOneFour: .l714
        case .nineOneSix: .l916
        }
    }
}
