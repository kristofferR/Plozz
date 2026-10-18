import CoreModels
import CoreNetworking
import Foundation
import Observation

/// A presentation-owned gate, shared by initial play and episode/playlist advance.
/// No stream or engine is opened while a choice is pending.
@MainActor
@Observable
public final class PlaybackVersionChoiceModel {
    public struct Prompt: Equatable {
        public let id: UUID
        public let item: MediaItem
        public let versions: [MediaVersion]
        public var needsIntroduction: Bool
    }

    public private(set) var prompt: Prompt?
    @ObservationIgnored private var continuation: CheckedContinuation<MediaItem, Error>?
    @ObservationIgnored private var owner: UUID?
    @ObservationIgnored private var settings: PlaybackSettingsModel?
    @ObservationIgnored private var preferences: (any VersionPreferenceStoring)?
    @ObservationIgnored private var isCurrent: () -> Bool = { false }

    public init() {}

    public var isPreparing: Bool { owner != nil }

    public func prepare(
        _ opened: MediaItem,
        provider: any MediaProvider,
        settings: PlaybackSettingsModel,
        preferences: any VersionPreferenceStoring,
        offlineResolver: (any OfflinePlaybackResolving)? = nil,
        isCurrent: @escaping () -> Bool = { true }
    ) async throws -> MediaItem {
        guard owner == nil else {
            PlozzLog.playback.error("A version choice is already pending.")
            throw AppError.invalidResponse
        }
        guard [.movie, .episode].contains(opened.kind), opened.youTubeTrailerVideoID == nil else {
            return opened
        }
        let id = UUID()
        owner = id
        defer { clear(owner: id) }
        try Task.checkCancellation()
        guard isCurrent() else { throw CancellationError() }
        var item = opened
        if opened.versions.isEmpty,
           PlayerVersionSelection.versions(for: opened).count <= 1 {
            let local = await offlineResolver?.localPlaybackURL(for: opened, versionID: opened.selectedVersionID)
            if local == nil {
                let resolved = try await provider.item(id: opened.id)
                guard resolved.id == opened.id, resolved.kind == opened.kind,
                      resolved.sourceAccountID == nil || resolved.sourceAccountID == opened.sourceAccountID else {
                    PlozzLog.playback.error("Version details did not match the requested title.")
                    throw AppError.invalidResponse
                }
                item = PlayerVersionSelection.item(opened: opened, resolved: resolved)
                if item.seriesID == nil { item.seriesID = resolved.seriesID }
            }
        }
        try Task.checkCancellation()
        guard owner == id, isCurrent() else { throw CancellationError() }
        let versions = PlayerVersionSelection.versions(for: item)
        guard !versions.isEmpty else { return item }
        if settings.settings.versionSelectionMode == .rememberChoice,
           let remembered = Self.rememberedVersion(in: versions, item: item, preferences: preferences),
           let selected = PlayerVersionSelection.selecting(remembered.id, in: item) {
            return selected
        }
        let key = DetailPlaybackSelection.versionPreferenceKey(for: item)
        let hasRememberedChoice = preferences.preferredVersionID(forTitle: key) != nil
            || preferences.preferredVersionDescriptor(forTitle: key) != nil
            || preferences.preferredVersionDescriptor(forTitle: item.seriesID ?? item.id) != nil
        guard versions.count > 1
            || (settings.settings.versionSelectionMode == .rememberChoice && hasRememberedChoice) else { return item }
        self.settings = settings
        self.preferences = preferences
        self.isCurrent = isCurrent
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                self.continuation = continuation
                prompt = Prompt(
                    id: id, item: item, versions: versions,
                    needsIntroduction: settings.settings.versionSelectionMode == nil
                )
            }
        } onCancel: {
            Task { @MainActor [weak self] in self?.cancel(owner: id) }
        }
    }

    public func chooseMode(_ mode: PlaybackVersionSelectionMode, promptID: UUID) {
        guard let prompt, prompt.id == promptID, prompt.needsIntroduction else { return }
        guard isCurrent() else { cancel(); return }
        settings?.settings.versionSelectionMode = mode
        self.prompt?.needsIntroduction = false
    }

    public func chooseVersion(_ versionID: String, promptID: UUID) {
        guard let prompt, prompt.id == promptID, !prompt.needsIntroduction else { return }
        guard isCurrent() else { cancel(); return }
        guard let version = prompt.versions.first(where: { $0.id == versionID }),
              let item = PlayerVersionSelection.selecting(versionID, in: prompt.item) else {
            PlozzLog.playback.error("The requested playback version is no longer available.")
            return
        }
        preferences?.rememberVersion(version, forTitle: DetailPlaybackSelection.versionPreferenceKey(for: prompt.item))
        if DetailPlaybackSelection.versionPreferenceKey(for: item)
            != DetailPlaybackSelection.versionPreferenceKey(for: prompt.item) {
            preferences?.rememberVersion(version, forTitle: DetailPlaybackSelection.versionPreferenceKey(for: item))
        }
        let continuation = self.continuation
        clear(owner: prompt.id)
        continuation?.resume(returning: item)
    }

    public func cancel() {
        guard let owner else { return }
        cancel(owner: owner)
    }

    private func cancel(owner id: UUID) {
        guard owner == id else { return }
        let continuation = self.continuation
        clear(owner: id)
        continuation?.resume(throwing: CancellationError())
    }

    private func clear(owner id: UUID) {
        guard owner == id else { return }
        prompt = nil
        continuation = nil
        settings = nil
        preferences = nil
        isCurrent = { false }
        owner = nil
    }

    public static func rememberedVersion(
        in versions: [MediaVersion], item: MediaItem, preferences: any VersionPreferenceStoring
    ) -> MediaVersion? {
        let key = DetailPlaybackSelection.versionPreferenceKey(for: item)
        if item.seriesID == nil, let id = preferences.preferredVersionID(forTitle: key),
           let exact = versions.first(where: { version in
               version.id == id || (item.sourceAccountID.map { account in
                   version.qualified(accountID: account, itemID: version.sourceItemID ?? item.id).id == id
               } ?? false)
           }) {
            return exact
        }
        let descriptor = preferences.preferredVersionDescriptor(forTitle: key)
            ?? preferences.preferredVersionDescriptor(forTitle: item.seriesID ?? item.id)
        guard let descriptor else { return nil }
        return versions.filter { descriptor.matchesForAutomaticSelection($0) }.bestMatch(for: descriptor)
    }
}
