#if os(tvOS)
import CoreModels
import CoreNetworking
import os
import SwiftUI
import UIKit

private struct CompositedLibraryPostersKey: EnvironmentKey {
    static var defaultValue: Bool {
        #if DEBUG
        !ProcessInfo.processInfo.arguments.contains("--original-library-posters")
        #else
        true
        #endif
    }
}

extension EnvironmentValues {
    var compositedLibraryPosters: Bool {
        get { self[CompositedLibraryPostersKey.self] }
        set { self[CompositedLibraryPostersKey.self] = newValue }
    }
}

struct NativePosterArtworkBackground: Equatable {
    var dimming: CGFloat = 0
    var scrim: MediaArtworkChromeScrim?
}

enum NativePosterOverlayPlacement {
    case croppedCount, floating
}

struct NativePosterOverlay {
    let image: UIImage
    let placement: NativePosterOverlayPlacement
    let layoutDirection: LayoutDirection
}

@MainActor
enum NativePosterArtworkBitmap {
    struct IndicatorKey: Equatable {
        let inputs: NativePosterIndicators
        let metrics: PlozzMetrics
        let palette: ThemePalette
        let watchIndicator: WatchStatusIndicator
        let showsEpisodeCount: Bool
        let seerConnected: Bool
        let locale: Locale
        let layoutDirection: LayoutDirection
        let colorScheme: ColorScheme
        let contrast: ColorSchemeContrast
        let dynamicTypeSize: DynamicTypeSize
        let legibilityWeight: LegibilityWeight?
        let layer: NativePosterIndicatorLayer

        init(
            _ indicators: NativePosterIndicators, environment: EnvironmentValues,
            layer: NativePosterIndicatorLayer = .combined
        ) {
            inputs = indicators
            metrics = environment.plozzMetrics
            palette = environment.themePalette
            watchIndicator = environment.plozzWatchStatusIndicator
            showsEpisodeCount = environment.plozzShowsUnwatchedEpisodeCount
            seerConnected = environment.plozzSeerConnected
            locale = environment.locale
            layoutDirection = environment.layoutDirection
            colorScheme = environment.colorScheme
            contrast = environment.colorSchemeContrast
            dynamicTypeSize = environment.dynamicTypeSize
            legibilityWeight = environment.legibilityWeight
            self.layer = layer
        }

        var overlayPlacement: NativePosterOverlayPlacement? {
            guard case .playback(let inputs) = inputs, inputs.rendersStatus else { return nil }
            switch MediaPlaybackIndicatorPresentation.status(
                for: inputs.playback, hidesStatus: inputs.hidesStatus, indicator: watchIndicator,
                showsEpisodeCount: showsEpisodeCount, seerConnected: seerConnected
            ) {
            case .episodeCount:
                return watchIndicator == .unwatched ? .croppedCount : .floating
            case .library, .watched:
                return .floating
            case .unwatched, nil:
                return nil
            }
        }
    }

    static let placeholder = UIGraphicsImageRenderer(size: CGSize(width: 2, height: 3)).image {
        UIColor.darkGray.setFill()
        $0.fill(CGRect(x: 0, y: 0, width: 2, height: 3))
    }

    static func portraitFocusCrop(for size: CGSize) -> CGSize {
        guard size.width > 0, size.height > size.width else { return .zero }
        // Native rectangular focus trims about 2 source points horizontally.
        // Match the portrait aspect so top and trailing content keep equal clearance.
        return CGSize(width: 2, height: 2 * size.height / size.width)
    }

    private static let placeholders: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.countLimit = 8
        cache.totalCostLimit = 4 * 1024 * 1024
        return cache
    }()

    static func placeholder(size: CGSize, scale: CGFloat, clipsToArtwork: Bool = true) -> UIImage {
        let key = "\(size.width)x\(size.height)@\(scale):\(clipsToArtwork)" as NSString
        if let cached = placeholders.object(forKey: key) { return cached }
        guard let image = image(
            source: nil, size: size, scale: scale,
            backgroundColor: .darkGray, clipsToArtwork: clipsToArtwork
        ) else { return placeholder }
        if let pixels = image.cgImage {
            placeholders.setObject(image, forKey: key, cost: pixels.bytesPerRow * pixels.height)
        }
        return image
    }

    private struct IndicatorEntry {
        let key: IndicatorKey
        let size: CGSize
        let scale: CGFloat
        let image: UIImage
        let cost: Int
    }

    private static var indicatorCache: [IndicatorEntry] = []
    private(set) static var indicatorBytes = 0
    static let indicatorByteLimit = ArtworkMemoryBudget.current.indicatorBytes
    static let indicatorCountLimit = ArtworkMemoryBudget.current.compositeCount
    static var indicatorCount: Int { indicatorCache.count }
    private static let indicatorMemoryWarning = NotificationCenter.default.addObserver(
        forName: UIApplication.didReceiveMemoryWarningNotification, object: nil, queue: .main
    ) { _ in
        MainActor.assumeIsolated {
            indicatorCache.removeAll()
            indicatorBytes = 0
        }
    }

    static func indicatorImage(key: IndicatorKey, size: CGSize, scale: CGFloat, environment: EnvironmentValues) -> UIImage? {
        if let index = indicatorCache.firstIndex(where: { $0.key == key && $0.size == size && $0.scale == scale }) {
            let entry = indicatorCache.remove(at: index)
            indicatorCache.append(entry)
            return entry.image
        }
        let renderer = ImageRenderer(content: key.inputs
            .frame(width: size.width, height: size.height)
            .environment(\.nativePosterIndicatorLayer, key.layer)
            .environment(\.self, environment)
            .plozzChromeFocused(false))
        renderer.scale = scale
        // Cache concrete pixels, never a deferred RenderBox image or a view
        // graph retaining the caller's full environment.
        var rendered: UIImage?
        renderer.render(rasterizationScale: scale) { _, draw in
            rendered = image(
                source: nil, size: size, scale: scale, backgroundColor: .clear,
                clipsToArtwork: false, drawOverlay: draw
            )
        }
        guard let rendered, let pixels = rendered.cgImage else {
            PlozzLog.app.error("Unable to render native poster indicators")
            return nil
        }
        let (cost, overflow) = pixels.bytesPerRow.multipliedReportingOverflow(by: pixels.height)
        if !overflow, cost <= indicatorByteLimit {
            _ = indicatorMemoryWarning
            while !indicatorCache.isEmpty
                && (indicatorBytes + cost > indicatorByteLimit || indicatorCache.count >= indicatorCountLimit) {
                indicatorBytes -= indicatorCache.removeFirst().cost
            }
            indicatorCache.append(IndicatorEntry(key: key, size: size, scale: scale, image: rendered, cost: cost))
            indicatorBytes += cost
        }
        return rendered
    }

    static func image(
        source: UIImage?, overlay: UIImage? = nil, size: CGSize, scale: CGFloat,
        backgroundColor: UIColor? = nil, clipsToArtwork: Bool = true,
        artworkBackground: NativePosterArtworkBackground = .init(),
        drawOverlay: (CGContext) -> Void = { _ in }
    ) -> UIImage? {
        guard size.width.isFinite, size.height.isFinite, scale.isFinite,
              size.width > 0, size.height > 0, scale > 0,
              source.map({ $0.size.width > 0 && $0.size.height > 0 }) ?? true else {
            PlozzLog.app.error("Unable to prepare native poster artwork with invalid dimensions")
            return nil
        }
        let gradient: CGGradient?
        if let scrim = artworkBackground.scrim {
            let stops = scrim.stops
            guard let resolved = CGGradient(
                colorsSpace: CGColorSpaceCreateDeviceRGB(),
                colors: stops.map { UIColor($0.color).cgColor } as CFArray,
                locations: stops.map(\.location)
            ) else {
                PlozzLog.app.error("Unable to prepare native artwork legibility gradient")
                return nil
            }
            gradient = resolved
        } else {
            gradient = nil
        }
        return compose(
            source: source, overlay: overlay, size: size, scale: scale, backgroundColor: backgroundColor,
            clipsToArtwork: clipsToArtwork, dimming: artworkBackground.dimming, gradient: gradient,
            drawOverlay: drawOverlay
        )
    }

    /// Draws the pixels. Safe off the main actor; callers validate the dimensions.
    nonisolated static func compose(
        source: UIImage?, overlay: UIImage?, size: CGSize, scale: CGFloat,
        backgroundColor: UIColor?, clipsToArtwork: Bool, dimming: CGFloat = 0, gradient: CGGradient? = nil,
        drawOverlay: (CGContext) -> Void = { _ in }
    ) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        format.preferredRange = .standard
        format.opaque = !clipsToArtwork && backgroundColor?.cgColor.alpha == 1
        let bounds = CGRect(origin: .zero, size: size)
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            if let background = backgroundColor ?? (source == nil ? .darkGray : nil) {
                background.setFill()
                context.fill(bounds)
            }
            if let source {
                let ratio = max(size.width / source.size.width, size.height / source.size.height)
                let target = CGSize(width: source.size.width * ratio, height: source.size.height * ratio)
                source.draw(in: CGRect(
                    x: (size.width - target.width) / 2, y: (size.height - target.height) / 2,
                    width: target.width, height: target.height
                ))
            }
            if dimming > 0 {
                context.cgContext.setFillColor(UIColor.black.withAlphaComponent(dimming).cgColor)
                context.cgContext.fill(bounds)
            }
            if let gradient {
                context.cgContext.drawLinearGradient(
                    gradient, start: CGPoint(x: bounds.midX, y: bounds.minY),
                    end: CGPoint(x: bounds.midX, y: bounds.maxY), options: []
                )
            }
            overlay?.draw(in: bounds)
            context.cgContext.saveGState()
            context.cgContext.translateBy(x: 0, y: size.height)
            context.cgContext.scaleBy(x: 1, y: -1)
            drawOverlay(context.cgContext)
            context.cgContext.restoreGState()
            if clipsToArtwork {
                // Round the composed pixels once. Clipping each draw separately
                // exposes the artwork through the badge's antialiased edge.
                // Cover the full raster, including the extra pixel allocated for
                // fractional point sizes. An antialiased outer eraser edge leaves
                // a residual row/column that UIKit also treats as highlight alpha.
                let outside = UIBezierPath(rect: bounds.insetBy(dx: -1, dy: -1))
                outside.append(UIBezierPath(
                    roundedRect: bounds,
                    cornerRadius: PlozzTheme.Metrics.nativePosterArtworkCornerRadius
                ))
                outside.usesEvenOddFillRule = true
                context.cgContext.setBlendMode(.destinationOut)
                UIColor.black.setFill()
                outside.fill()
            }
        }
    }
}

/// Browse uses the same opaque native surface and aligned indicator foreground as poster rows.
@MainActor
enum NativeLibraryPosterBitmap {
    struct Presentation: Equatable {
        let playback: MediaPlaybackIndicatorState?
        let symbol: MediaArtworkPlaceholder.Symbol
        let title: String? // l10n:content — resolved provider title or spoiler-safe caption
        let hidesStatus: Bool
        let metrics: PlozzMetrics
        let palette: ThemePalette
        let watchIndicator: WatchStatusIndicator
        let showsEpisodeCount: Bool
        let seerConnected: Bool
        let locale: Locale
        let layoutDirection: LayoutDirection
        let colorScheme: ColorScheme
        let contrast: ColorSchemeContrast
        let dynamicTypeSize: DynamicTypeSize
        let legibilityWeight: LegibilityWeight?

        var indicators: MediaCardPlaybackIndicators? {
            playback.map {
                MediaCardPlaybackIndicators(
                    playback: $0, hidesStatus: hidesStatus,
                    showsProgressBar: true, badgeInset: 8,
                    progressHeight: metrics.progressBarHeight,
                    progressHorizontalInset: 16, progressBottomInset: 16,
                    artworkCornerRadius: PlozzTheme.Metrics.nativePosterArtworkCornerRadius
                )
            }
        }

        init(item: MediaItem?, spoilerSettings: SpoilerSettings, environment: EnvironmentValues) {
            playback = item.map(MediaPlaybackIndicatorState.init)
            symbol = item.map { .init(for: $0) } ?? .playback
            title = environment.plozzCardCaptionsHidden ? item.map {
                $0.posterCaptionTitle(spoilerSettings: spoilerSettings).resolve(locale: environment.locale)
            } : nil
            hidesStatus = item.map(spoilerSettings.shouldHideThumbnail(for:)) ?? false
            metrics = environment.plozzMetrics
            palette = environment.themePalette
            watchIndicator = environment.plozzWatchStatusIndicator
            showsEpisodeCount = environment.plozzShowsUnwatchedEpisodeCount
            seerConnected = environment.plozzSeerConnected
            locale = environment.locale
            layoutDirection = environment.layoutDirection
            colorScheme = environment.colorScheme
            contrast = environment.colorSchemeContrast
            dynamicTypeSize = environment.dynamicTypeSize
            legibilityWeight = environment.legibilityWeight
        }
    }

    final class Key: NSObject {
        let source: ObjectIdentifier?
        let presentation: Presentation
        let size: CGSize
        let scale: CGFloat

        init(image: UIImage?, presentation: Presentation, size: CGSize, scale: CGFloat) {
            source = image.map(ObjectIdentifier.init)
            self.presentation = presentation
            self.size = size
            self.scale = scale
        }

        override var hash: Int {
            var hasher = Hasher()
            hasher.combine(source)
            hasher.combine(size.width)
            hasher.combine(size.height)
            hasher.combine(scale)
            return hasher.finalize()
        }

        override func isEqual(_ object: Any?) -> Bool {
            guard let other = object as? Key else { return false }
            return source == other.source && size == other.size && scale == other.scale
                && presentation == other.presentation
        }
    }

    private final class Entry {
        weak var source: UIImage?
        let image: UIImage
        let cost: Int
        var access: UInt64

        init(source: UIImage?, image: UIImage, cost: Int, access: UInt64) {
            self.source = source
            self.image = image
            self.cost = cost
            self.access = access
        }
    }

    static let byteLimit = ArtworkMemoryBudget.current.compositeBytes
    static let countLimit = ArtworkMemoryBudget.current.compositeCount
    private(set) static var retainedBytes = 0
    private(set) static var renderCount = 0
    private static var cache: [Key: Entry] = [:]
    private static var clock: UInt64 = 0
    private static let memoryWarning = NotificationCenter.default.addObserver(
        forName: UIApplication.didReceiveMemoryWarningNotification, object: nil, queue: .main
    ) { _ in
        MainActor.assumeIsolated {
            cache.removeAll()
            retainedBytes = 0
            purges &+= 1
        }
    }
    /// Memory-warning purges so far; a draw that spans one shows its result but doesn't cache it.
    private static var purges = 0

    private struct Content: View {
        let presentation: Presentation
        let hasArtwork: Bool
        let size: CGSize
        let environment: EnvironmentValues

        var body: some View {
            NativeLibraryArtworkOverlay(
                symbol: presentation.symbol, hasArtwork: hasArtwork,
                isFolder: presentation.playback?.kind == .folder,
                isFocused: false,
                indicators: presentation.indicators,
                title: presentation.title.map { Text(verbatim: $0) }
            )
            .frame(width: size.width, height: size.height)
            .environment(\.nativePosterIndicatorLayer, .background)
            .environment(\.self, environment)
            .plozzChromeFocused(false)
        }
    }

    static func overlay(key: Key, environment: EnvironmentValues) -> NativePosterOverlay? {
        guard let indicators = key.presentation.indicators else { return nil }
        let indicatorKey = NativePosterArtworkBitmap.IndicatorKey(
            .media(indicators), environment: environment, layer: .foreground
        )
        guard let placement = indicatorKey.overlayPlacement,
              let image = NativePosterArtworkBitmap.indicatorImage(
                  key: indicatorKey, size: key.size, scale: key.scale, environment: environment
              ) else { return nil }
        return NativePosterOverlay(image: image, placement: placement, layoutDirection: indicatorKey.layoutDirection)
    }

    /// The composite for `key`, if it is still cached for this exact source image.
    static func cachedImage(source: UIImage?, key: Key) -> UIImage? {
        clock &+= 1
        guard let entry = cache[key], entry.source === source else { return nil }
        entry.access = clock
        return entry.image
    }

    static func image(source: UIImage?, key: Key, environment: EnvironmentValues) -> UIImage? {
        if let cached = cachedImage(source: source, key: key) { return cached }
        guard let overlay = indicatorLayer(source: source, key: key, environment: environment) else { return nil }
        let image = NativePosterArtworkBitmap.compose(
            source: source, overlay: overlay, size: key.size, scale: key.scale,
            backgroundColor: .darkGray, clipsToArtwork: false
        )
        store(image, source: source, key: key)
        return image
    }

    /// Renders the SwiftUI indicator layer here, which needs the main actor, and draws the
    /// full-size poster on a background thread. Concurrent misses for one key may both draw;
    /// a cancelled caller stores nothing.
    static func composite(source: UIImage?, key: Key, environment: EnvironmentValues) async -> UIImage? {
        if let cached = cachedImage(source: source, key: key) { return cached }
        // A cell that scrolled away cancels before its indicator layer is rendered.
        guard !Task.isCancelled,
              let overlay = indicatorLayer(source: source, key: key, environment: environment) else { return nil }
        _ = memoryWarning // observe purges from the first draw on
        let purgesBefore = purges
        // Awaited directly rather than detached, so a cell that scrolls away cancels the draw too.
        guard let image = await composeOffMain(source: source, overlay: overlay, size: key.size, scale: key.scale),
              !Task.isCancelled else { return nil }
        if purges == purgesBefore { store(image, source: source, key: key) }
        return image
    }

    /// Composites get their own bounded lane, like artwork decoding: CPU-bound pixel work on
    /// Swift's cooperative pool (2-3 threads on tvOS) would hold up unrelated async work.
    private nonisolated static let composeQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 2
        queue.qualityOfService = .userInitiated
        return queue
    }()

    private static func composeOffMain(
        source: UIImage?, overlay: UIImage, size: CGSize, scale: CGFloat
    ) async -> UIImage? {
        let cancelled = OSAllocatedUnfairLock(initialState: false)
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                composeQueue.addOperation {
                    // A queued draw for a cell that scrolled away is skipped, not drawn.
                    guard !cancelled.withLock({ $0 }) else { return continuation.resume(returning: nil) }
                    continuation.resume(returning: NativePosterArtworkBitmap.compose(
                        source: source, overlay: overlay, size: size, scale: scale,
                        backgroundColor: .darkGray, clipsToArtwork: false
                    ))
                }
            }
        } onCancel: {
            cancelled.withLock { $0 = true }
        }
    }

    private static func indicatorLayer(source: UIImage?, key: Key, environment: EnvironmentValues) -> UIImage? {
        let size = key.size
        guard size.width.isFinite, size.height.isFinite, key.scale.isFinite,
              size.width > 0, size.height > 0, key.scale > 0,
              source.map({ $0.size.width > 0 && $0.size.height > 0 }) ?? true else {
            PlozzLog.app.error("Unable to composite library artwork with invalid dimensions")
            return nil
        }
        // The full inherited environment can own library providers. Keep it out
        // of the shared cache and release the view graph after producing pixels.
        let active = ImageRenderer(content: Content(
            presentation: key.presentation, hasArtwork: source != nil, size: size, environment: environment
        ))
        active.scale = key.scale
        guard let overlay = active.uiImage else {
            PlozzLog.app.error("Unable to render composited library indicators")
            return nil
        }
        return overlay
    }

    private static func store(_ image: UIImage, source: UIImage?, key: Key) {
        renderCount += 1
        if let replaced = cache.removeValue(forKey: key) { retainedBytes -= replaced.cost }
        guard let pixels = image.cgImage else { return }
        let (cost, overflow) = pixels.bytesPerRow.multipliedReportingOverflow(by: pixels.height)
        guard !overflow, cost <= byteLimit else { return }
        _ = memoryWarning
        while !cache.isEmpty && (retainedBytes + cost > byteLimit || cache.count >= countLimit) {
            guard let oldest = cache.min(by: { $0.value.access < $1.value.access }) else { break }
            retainedBytes -= oldest.value.cost
            cache.removeValue(forKey: oldest.key)
        }
        clock &+= 1
        cache[key] = Entry(source: source, image: image, cost: cost, access: clock)
        retainedBytes += cost
    }
}
#endif
