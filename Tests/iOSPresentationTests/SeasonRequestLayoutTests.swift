#if os(iOS)
import CoreModels
import CoreUI
import FeatureHomeCore
import SwiftUI
import UIKit
import Vision
import XCTest
@testable import AppShelliOS

@MainActor
final class SeasonRequestLayoutTests: XCTestCase {
    private let item = MediaItem(id: "unreleased-series", title: "Phony", kind: .series)
    private var availability: MediaRequestAvailability {
        .init(status: .processing, seasons: [
            .init(number: 1, title: "Season 1", status: .processing,
                  premiereDate: MediaItem.calendarDayReleaseDate(from: "2099-10-20"))
        ])
    }

    private var request: PlozziOSHeroRequest {
        .init(
            cta: .requested, isRequesting: false, actingName: nil, onRequest: { _ in },
            seasonAvailability: availability, onRequestSeasons: { _ in },
            onOpenSeasonRequests: {}
        )
    }

    func testActualDetailHeroUsesOverflowBeforeStackingAndKeepsButtonsTheSameHeight() throws {
        let app = PlozziOSAppModel()
        let button = PlozziOSHeroRequestButton(item: item, request: request)
            .environment(\.dynamicTypeSize, .large)
        let primary = size(button, width: 2_000)
        XCTAssertEqual(primary.height, 48, accuracy: 0.5,
                       "The complete request status must remain a normal single-line button, not a subtitle card.")
        let overflowSpacingAndWidth: CGFloat = 12 + 48
        for width in [primary.width + overflowSpacingAndWidth - 2,
                      primary.width + overflowSpacingAndWidth + 2, 500, 720] {
            let baseline = foreground(app: app, extras: false)
            let actual = foreground(app: app, extras: true)
            let baselineSize = size(baseline, width: width)
            let actualSize = size(actual, width: width)
            XCTAssertLessThanOrEqual(actualSize.width, width + 0.5)
            if width >= primary.width + overflowSpacingAndWidth {
                XCTAssertEqual(actualSize.height, baselineSize.height, accuracy: 1,
                               "Secondary actions must enter the real overflow menu before the row grows taller.")
            } else {
                XCTAssertEqual(actualSize.height, baselineSize.height + overflowSpacingAndWidth, accuracy: 1,
                               "The secondary icons must share one row below the primary request.")
            }
            let image = try capture(actual, width: width, name: "actual-detail-overflow-\(Int(width))pt")
            if width < primary.width + overflowSpacingAndWidth {
                try assertBottomIconCount(2, in: image)
            }
            let recognition = VNRecognizeTextRequest()
            recognition.recognitionLevel = .accurate
            recognition.recognitionLanguages = ["en-US"]
            try VNImageRequestHandler(cgImage: XCTUnwrap(image.cgImage)).perform([recognition])
            let lines = (recognition.results ?? []).compactMap { $0.topCandidates(1).first?.string }
            XCTAssertTrue(lines.contains { $0.contains("Requested") && $0.contains("Unreleased") },
                          "Both facts must appear together on one line: \(lines)")
            if width < 500 {
                XCTAssertFalse(lines.contains { $0 == "Trailer" },
                               "Trailer must use its icon or overflow rather than forcing a taller request button.")
            }
        }
    }

    func testStackedIconsRetainSeparateSourceSelectionWithoutHidingActions() throws {
        let app = PlozziOSAppModel()
        let view = foreground(app: app, extras: true, sources: [
            .init(accountID: "jellyfin", itemID: "show-jellyfin", kind: .series, providerKind: .jellyfin),
            .init(accountID: "plex", itemID: "show-plex", kind: .series, providerKind: .plex)
        ])
        let image = try capture(view, width: 276, name: "stacked-icons-with-source-menu")
        try assertBottomIconCount(3, in: image)
        let narrowWidth: CGFloat = 156
        let baseline = size(foreground(app: app, extras: false), width: narrowWidth)
        XCTAssertEqual(size(view, width: narrowWidth).height, baseline.height + 120, accuracy: 1,
                       "All three controls must wrap into two icon rows rather than disappearing into overflow.")
        _ = try capture(view, width: narrowWidth, name: "stacked-icons-wrapping-with-source-menu")
    }

    func testActualDetailHeroPreservesTheCompleteStatusAtPhoneTabletAndLargeTextSizes() throws {
        let app = PlozziOSAppModel()
        for width in [CGFloat(276), 331, 386, 720] {
            for typeSize in [DynamicTypeSize.large, .xxxLarge, .accessibility3] {
                let view = foreground(app: app, extras: true, typeSize: typeSize)
                XCTAssertLessThanOrEqual(size(view, width: width).width, width + 0.5)
                _ = try capture(view, width: width, name: "actual-detail-\(Int(width))pt-\(typeSize)")
            }
        }
    }

    func testCircularHeroIconsStayInsetAtAccessibilityTextSizes() throws {
        for typeSize in [DynamicTypeSize.large, .xxxLarge, .accessibility3, .accessibility5] {
            for symbol in ["film.fill", "bookmark", "ellipsis"] {
                let button = Button {} label: {
                    Image(systemName: symbol).font(.headline.weight(.bold))
                }
                .buttonStyle(TouchHeroActionButtonStyle(kind: .secondary, circular: true))
                .environment(\.dynamicTypeSize, typeSize)
                .environment(\.themePalette, ThemePalette.dark)
                .environment(\.colorScheme, .dark)
                XCTAssertEqual(size(button, width: 48), CGSize(width: 48, height: 48))
                let image = try capture(button, width: 48, name: "circular-\(symbol)-\(typeSize)")
                let glyph = try brightPixelBounds(image)
                let inset: CGFloat = 16 + 8
                XCTAssertGreaterThanOrEqual(glyph.minX, inset)
                XCTAssertGreaterThanOrEqual(glyph.minY, inset)
                XCTAssertLessThanOrEqual(glyph.maxX, 16 + 48 - 8)
                XCTAssertLessThanOrEqual(glyph.maxY, 16 + 48 - 8)
            }
        }
    }

    private func foreground(
        app: PlozziOSAppModel, extras: Bool, typeSize: DynamicTypeSize = .large,
        sources: [MediaSourceRef] = []
    ) -> some View {
        let presentation = HeroPresentation(item: item, artworkStyle: .compactPortrait, surface: .detail)
        return PlozziOSDetailHeroForeground(
            item: item, rootItem: item, playableItem: nil,
            sources: sources, selectedSourceAccountID: sources.first?.accountID,
            versions: [], selectedVersionID: nil,
            onSelectSource: { _ in }, onSelectVersion: { _ in },
            presentation: presentation, fallbackPresentation: presentation,
            style: .compactPortrait,
            actionHandler: RequestLayoutActions(showsWatchlist: extras),
            onPlay: { _, _ in }, trailerItem: extras ? item : nil,
            onPlayTrailer: extras ? { _ in } : nil, heroRequest: request
        )
        .environment(app)
        .environment(\.dynamicTypeSize, typeSize)
        .environment(\.locale, Locale(identifier: "en"))
        .environment(\.themePalette, ThemePalette.dark)
        .environment(\.colorScheme, .dark)
    }

    private func size(_ view: some View, width: CGFloat) -> CGSize {
        UIHostingController(rootView: view).sizeThatFits(in: CGSize(width: width, height: 3_000))
    }

    private func assertBottomIconCount(
        _ expected: Int, in image: UIImage, file: StaticString = #filePath, line: UInt = #line
    ) throws {
        let cgImage = try XCTUnwrap(image.cgImage)
        // The capture has 16pt padding; sample the centers of the bottom 48pt controls.
        let row = try XCTUnwrap(cgImage.cropping(to: CGRect(
            x: 0, y: cgImage.height - Int(40 * image.scale), width: cgImage.width, height: 1
        )))
        var bytes = [UInt8](repeating: 0, count: row.width * 4)
        try bytes.withUnsafeMutableBytes { buffer in
            let context = try XCTUnwrap(CGContext(
                data: buffer.baseAddress, width: row.width, height: 1, bitsPerComponent: 8,
                bytesPerRow: row.width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ))
            context.draw(row, in: CGRect(x: 0, y: 0, width: row.width, height: 1))
        }
        var widths: [Int] = []
        var currentWidth = 0
        for x in 0..<row.width {
            if bytes[x * 4] > 8 || bytes[x * 4 + 1] > 8 || bytes[x * 4 + 2] > 8 {
                currentWidth += 1
            } else if currentWidth > 0 {
                widths.append(currentWidth)
                currentWidth = 0
            }
        }
        if currentWidth > 0 { widths.append(currentWidth) }
        XCTAssertEqual(widths.count, expected, "Expected direct secondary icon buttons.", file: file, line: line)
        for width in widths {
            XCTAssertEqual(CGFloat(width) / image.scale, 48, accuracy: 2, file: file, line: line)
        }
    }

    private func brightPixelBounds(_ image: UIImage) throws -> CGRect {
        let cgImage = try XCTUnwrap(image.cgImage)
        var bytes = [UInt8](repeating: 0, count: cgImage.width * cgImage.height * 4)
        try bytes.withUnsafeMutableBytes { buffer in
            let context = try XCTUnwrap(CGContext(
                data: buffer.baseAddress, width: cgImage.width, height: cgImage.height, bitsPerComponent: 8,
                bytesPerRow: cgImage.width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ))
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: cgImage.width, height: cgImage.height))
        }
        var bounds = CGRect.null
        for y in 0..<cgImage.height {
            for x in 0..<cgImage.width {
                let offset = (y * cgImage.width + x) * 4
                if bytes[offset] > 200, bytes[offset + 1] > 200, bytes[offset + 2] > 200 {
                    bounds = bounds.union(CGRect(
                        x: CGFloat(x) / image.scale, y: CGFloat(y) / image.scale,
                        width: 1 / image.scale, height: 1 / image.scale
                    ))
                }
            }
        }
        XCTAssertFalse(bounds.isNull, "The icon must be visible, not clipped away.")
        return bounds
    }

    private func capture(_ view: some View, width: CGFloat, name: String) throws -> UIImage {
        let renderer = ImageRenderer(content: view.frame(width: width).padding(16).background(.black))
        renderer.scale = 2
        let image = try XCTUnwrap(renderer.uiImage)
        let attachment = XCTAttachment(image: image)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        return image
    }
}

@MainActor
private final class RequestLayoutActions: MediaItemActionHandling {
    let showsWatchlist: Bool
    init(showsWatchlist: Bool) { self.showsWatchlist = showsWatchlist }
    func actions(for item: MediaItem, context: MediaItemActionContext) -> [MediaItemAction] {
        showsWatchlist ? [.addToWatchlist] : []
    }
    func perform(_ action: MediaItemAction, on item: MediaItem, context: MediaItemActionContext) {}
}
#endif
