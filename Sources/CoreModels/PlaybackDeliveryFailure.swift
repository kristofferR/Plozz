import Foundation

/// A loopback relay's typed failure, retained by its player before native playback
/// can replace an upstream refusal with a generic media-loading error.
public final class PlaybackDeliveryFailure: @unchecked Sendable {
    private final class Registry: @unchecked Sendable {
        let lock = NSLock()
        var entries: [URL: PlaybackDeliveryFailure] = [:]
    }

    private static let registry = Registry()
    private let lock = NSLock()
    private var failure: AppError?

    private init() {}

    public var error: AppError? { lock.withLock { failure } }

    public func record(_ error: AppError) {
        guard error != .cancelled else { return }
        lock.withLock { if failure == nil { failure = error } }
    }

    public static func register(loopbackURL: URL) -> PlaybackDeliveryFailure {
        let state = PlaybackDeliveryFailure()
        registry.lock.withLock { registry.entries[loopbackURL] = state }
        return state
    }

    public static func state(for url: URL) -> PlaybackDeliveryFailure? {
        registry.lock.withLock { registry.entries[url] }
    }

    public static func unregister(loopbackURL: URL) {
        registry.lock.withLock { _ = registry.entries.removeValue(forKey: loopbackURL) }
    }
}
