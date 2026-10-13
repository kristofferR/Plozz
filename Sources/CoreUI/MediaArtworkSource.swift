import CoreModels
import Foundation
import MetadataKit

public struct MediaArtworkSource: Sendable {
    public let references: [ArtworkReference]
    public let fallbackURL: (@Sendable () async -> URL?)?
    public let policy: ArtworkPresentationPolicy
    public let itemIdentity: String
    private let background: Bool

    public init(
        item: MediaItem, placement: ArtworkPlacement, policy: ArtworkPresentationPolicy,
        background: Bool = false
    ) {
        self.init(item: item, placements: [placement], policy: policy, background: background)
    }

    public init(
        item: MediaItem, placements: [ArtworkPlacement], policy: ArtworkPresentationPolicy,
        router: ArtworkRouter = .shared, background: Bool = false
    ) {
        self.background = background
        self.policy = policy.forPlacement(placements.first)
        itemIdentity = CardArtworkPolicy.standard.pinIdentity(for: item)
        var seen = Set<ArtworkReference>()
        references = placements.flatMap { policy.references(for: item, placement: $0) }
            .filter { seen.insert($0).inserted }
        guard item.supportsExternalArtworkLookup else {
            fallbackURL = nil
            return
        }
        fallbackURL = {
            await ArtworkSession.resolveArtwork(background: background) {
                return await router.artworkURL(for: item, placements: placements)
            }
        }
    }

    #if canImport(UIKit)
    @MainActor
    public func resolve(
        variant: ArtworkImageVariant,
        maxAspectRatio: CGFloat? = nil
    ) async -> FirstPaintArtwork? {
        await ArtworkFirstPaintResolver.resolve(
            references: references,
            variant: variant,
            maxAspectRatio: maxAspectRatio,
            asyncOnlineURL: fallbackURL,
            prefersOnlineArtwork: policy.prefersOnlineArtwork,
            background: background
        )
    }
    #endif
}
