#if os(iOS)
@testable import AppShelliOS
import CoreUI
import FeaturePlayback
import SwiftUI
import UIKit
import XCTest

@MainActor
final class PlayerTimelineClockPresentationTests: XCTestCase {
    func testClockLabelsDoNotMoveTheScrubberWhenScrubbingStartsOrEnds() throws {
        for width in [320, 393, 852, 1024] {
            for locale in ["en_US", "en_GB", "de_DE", "ar"] {
                let model = PlayerControlsModel()
                model.duration = 7_200
                model.currentSeconds = 600
                model.bufferedSeconds = 900
                let normal = try render(model, width: width, scrubbing: false, locale: locale)
                model.timelineClock.isEnabled = true
                let clock = try render(model, width: width, scrubbing: false, locale: locale)
                let scrub = try render(model, width: width, scrubbing: true, locale: locale)
                XCTAssertEqual(try trackRange(clock), try trackRange(scrub),
                               "Showing the seek target must not change drag geometry: \(width) \(locale)")
                XCTAssertGreaterThan(try trackRange(clock).count, 40,
                                     "Clock labels must leave a usable scrubber on narrow phones.")
                model.controlsVisible = false
                let reset = try render(model, width: width, scrubbing: false, locale: locale)
                XCTAssertEqual(try trackRange(normal), try trackRange(reset))
                if locale == "en_US" {
                    let attachment = XCTAttachment(image: UIImage(cgImage: clock))
                    attachment.name = "Player clock timeline \(width)pt"
                    attachment.lifetime = .keepAlways
                    add(attachment)
                }
            }
        }
    }

    private func render(
        _ model: PlayerControlsModel, width: Int, scrubbing: Bool, locale: String
    ) throws -> CGImage {
        let renderer = ImageRenderer(content:
            PlozziOSPlayerTimeline(
                model: model, displayedSeconds: scrubbing ? 1_200 : 600, isScrubbing: scrubbing,
                onScrubChanged: { _ in XCTFail("Rendering must not seek.") },
                onScrubEditingChanged: { _ in XCTFail("Rendering must not change scrub state.") },
                onInteraction: { XCTFail("Rendering must not toggle clock mode.") }
            )
            .frame(width: CGFloat(width), height: 44)
            .environment(\.locale, Locale(identifier: locale))
            .environment(\.timeZone, .gmt)
            .environment(\.plozzReducePanelGlass, true)
            .background(Color(red: 0, green: 1, blue: 1))
        )
        renderer.scale = 1
        return try XCTUnwrap(renderer.cgImage)
    }

    private func trackRange(_ image: CGImage) throws -> Range<Int> {
        var pixels = [UInt8](repeating: 0, count: image.width * image.height * 4)
        try pixels.withUnsafeMutableBytes { buffer in
            let context = try XCTUnwrap(CGContext(
                data: buffer.baseAddress, width: image.width, height: image.height,
                bitsPerComponent: 8, bytesPerRow: image.width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
            ))
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        }
        func background(_ x: Int) -> Bool {
            let offset = (22 * image.width + x) * 4
            return pixels[offset] == 0 && pixels[offset + 1] == 255 && pixels[offset + 2] == 255
        }
        let center = image.width / 2
        XCTAssertFalse(background(center), "The center must remain inside the scrubber.")
        var lower = center
        var upper = center
        while lower > 0, !background(lower - 1) { lower -= 1 }
        while upper < image.width, !background(upper) { upper += 1 }
        return lower..<upper
    }
}
#endif
