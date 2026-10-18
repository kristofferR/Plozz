@testable import FeatureSettings
import CoreUI
import Observation
import SwiftUI
import UIKit
import XCTest

@MainActor
final class SettingsDetailNavigationHostedTests: XCTestCase {
    func testDialogDismissDoesNotPopItsPresentingSettingsPage() async throws {
        let deadline = ContinuousClock.now + .seconds(5)
        while !UIApplication.shared.connectedScenes.contains(where: { $0.activationState == .foregroundActive }),
              ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive })
        let previous = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        let navigation = SettingsPageNavigation<Int>()
        let probe = SettingsDialogProbe()
        window.rootViewController = UIHostingController(rootView:
            SettingsPageStack(navigation: navigation, pageWidth: 1920, onRootBack: {}) {
                Text("Categories")
            } destination: { _ in
                Text("Settings page")
                    .plozzSheet(isPresented: Binding(get: { probe.isPresented }, set: { probe.isPresented = $0 })) {
                        SettingsDialogDismissProbe(probe: probe)
                    }
            }
        )
        window.makeKeyAndVisible()
        defer {
            window.rootViewController?.dismiss(animated: false)
            window.isHidden = true
            window.rootViewController = nil
            previous?.makeKeyAndVisible()
        }
        navigation.push(1)
        try await Task.sleep(for: .milliseconds(600))
        probe.isPresented = true
        let presented = ContinuousClock.now + .seconds(5)
        while probe.dismiss == nil, ContinuousClock.now < presented {
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertEqual(probe.inheritsSettingsPage, false)
        try await Task.sleep(for: .milliseconds(350))
        try XCTUnwrap(probe.dismiss)()
        let dismissed = ContinuousClock.now + .seconds(5)
        while probe.isPresented, ContinuousClock.now < dismissed {
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertFalse(probe.isPresented)
        XCTAssertEqual(navigation.routes, [1], "Closing a dialog must not pop the underlying page.")
    }

    func testSharedStackMovesAndFadesRetainsParentsAndMirrorsInRightToLeftLayout() async throws {
        let deadline = ContinuousClock.now + .seconds(5)
        while !UIApplication.shared.connectedScenes.contains(where: { $0.activationState == .foregroundActive }),
              ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive })
        let previous = scene.windows.first(where: \.isKeyWindow)
        for direction in [LayoutDirection.leftToRight, .rightToLeft] {
            let window = UIWindow(windowScene: scene)
            window.frame = CGRect(x: 0, y: 0, width: 960, height: 540)
            let navigation = SettingsPageNavigation<Int>()
            let probes = PageMotionProbes()
            window.rootViewController = UIHostingController(rootView:
                SettingsPageStack(navigation: navigation, pageWidth: 960, onRootBack: {}) {
                    PageMotionProbe(id: "root", probes: probes)
                } destination: { route in
                    PageMotionProbe(id: route == 1 ? "detail" : "nested", probes: probes)
                }
                .environment(\.layoutDirection, direction)
                .ignoresSafeArea()
            )
            window.makeKeyAndVisible()
            defer {
                window.isHidden = true
                window.rootViewController = nil
                previous?.makeKeyAndVisible()
            }
            try await Task.sleep(for: .milliseconds(200))
            let sampler = PageMotionSampler(probes: probes, window: window)
            sampler.start()
            defer { sampler.stop() }
            navigation.push(1)
            try await Task.sleep(for: .milliseconds(600))
            let sign: CGFloat = direction == .leftToRight ? 1 : -1
            if !UIAccessibility.isReduceMotionEnabled {
                assertIntermediatePages(sampler.samples, width: 960, sign: sign)
            }
            navigation.push(2)
            try await Task.sleep(for: .milliseconds(600))
            navigation.pop()
            try await Task.sleep(for: .milliseconds(600))
            XCTAssertEqual(probes.creations["root"], 1)
            XCTAssertEqual(probes.creations["detail"], 1)
            XCTAssertEqual(try XCTUnwrap(probes.frame("detail", in: window)).minX, 0, accuracy: 2)
            sampler.samples.removeAll()
            navigation.pop()
            try await Task.sleep(for: .milliseconds(600))
            if !UIAccessibility.isReduceMotionEnabled {
                assertIntermediatePages(sampler.samples, width: 960, sign: sign)
            }
            XCTAssertEqual(try XCTUnwrap(probes.frame("root", in: window)).minX, 0, accuracy: 2)
            XCTAssertEqual(navigation.returnGeneration, 2)
        }
    }

    func testWorkspaceStyleDestinationsStayFullWidthDuringEntryAndReturn() async throws {
        try await verifyWorkspaceStyleWidth()
    }

    func testCategoriesAndNestedPagesKeepOneCenteredWidthThroughoutMotion() async throws {
        let deadline = ContinuousClock.now + .seconds(5)
        while !UIApplication.shared.connectedScenes.contains(where: { $0.activationState == .foregroundActive }),
              ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive })
        let previous = scene.windows.first(where: \.isKeyWindow)
        for direction in [LayoutDirection.leftToRight, .rightToLeft] {
            for reducedMotion in [false, true] {
                let window = UIWindow(windowScene: scene)
                window.frame = CGRect(x: 0, y: 0, width: 1920, height: 1080)
                let navigation = SettingsNavigationModel()
                let probes = PageMotionProbes()
                window.rootViewController = UIHostingController(rootView:
                    SettingsWorkspace(navigation: navigation) {
                        PageMotionProbe(id: "root", probes: probes)
                    } detail: { route in
                        PageMotionProbe(id: route == .playback ? "detail" : "nested", probes: probes)
                    }
                    .padding(.horizontal, 80)
                    .environment(\.layoutDirection, direction)
                    .ignoresSafeArea()
                )
                window.makeKeyAndVisible()
                defer {
                    window.isHidden = true
                    window.rootViewController = nil
                    previous?.makeKeyAndVisible()
                }
                try await Task.sleep(for: .milliseconds(200))
                navigation.pages.animationsEnabled = !reducedMotion && !UIAccessibility.isReduceMotionEnabled
                XCTAssertNil(probes.frame("detail", in: window), "The category list must not preload a second pane.")
                let root = try XCTUnwrap(probes.frame("root", in: window))
                XCTAssertEqual(root.width, SettingsFormMetrics.pageWidth, accuracy: 1)
                XCTAssertEqual(root.midX, window.bounds.midX, accuracy: 1)
                let sampler = PageMotionSampler(probes: probes, window: window)
                sampler.start()
                defer { sampler.stop() }
                navigation.enterDetail()
                try await Task.sleep(for: .milliseconds(600))
                let detail = try XCTUnwrap(probes.frame("detail", in: window))
                XCTAssertEqual(detail, root)
                if navigation.pages.animationsEnabled {
                    XCTAssertGreaterThan(sampler.samples.filter {
                        abs($0.rootX - root.minX) > 5 && abs($0.detailX - detail.minX) > 5
                    }.count, 1, "Both centered pages must move, not switch abruptly.")
                }
                for sample in sampler.samples {
                    XCTAssertEqual(sample.rootWidth, SettingsFormMetrics.pageWidth, accuracy: 1)
                    XCTAssertEqual(sample.detailWidth, SettingsFormMetrics.pageWidth, accuracy: 1)
                }
                navigation.pages.push(.artwork)
                try await Task.sleep(for: .milliseconds(600))
                XCTAssertEqual(try XCTUnwrap(probes.frame("nested", in: window)), root)
                navigation.pages.pop()
                try await Task.sleep(for: .milliseconds(600))
                XCTAssertEqual(try XCTUnwrap(probes.frame("detail", in: window)), root)
                navigation.pages.pop()
                try await Task.sleep(for: .milliseconds(600))
                XCTAssertEqual(try XCTUnwrap(probes.frame("root", in: window)), root)
                XCTAssertEqual(probes.creations["root"], 1, "Returning must retain the category list and its scroll.")
                XCTAssertFalse(navigation.isCategoryOpen)
            }
        }
    }

    private func verifyWorkspaceStyleWidth() async throws {
        let deadline = ContinuousClock.now + .seconds(5)
        while !UIApplication.shared.connectedScenes.contains(where: { $0.activationState == .foregroundActive }),
              ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive })
        let previous = scene.windows.first(where: \.isKeyWindow)
        let reduceMotion = UIAccessibility.isReduceMotionEnabled
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        let navigation = SettingsNavigationModel()
        navigation.select(.subtitles)
        navigation.enterDetail()
        let probes = PageMotionProbes()
        let host = UIHostingController(rootView:
            SettingsWorkspace(navigation: navigation) {
                Button("Subtitles") {}
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } detail: { route in
                Button(route.usesFullScreenDetail ? "Style control" : "Open style") {}
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background {
                        PageMotionProbe(id: route.usesFullScreenDetail ? "detail" : "root", probes: probes)
                    }
            }
            .padding(.horizontal, 80)
            .ignoresSafeArea()
        )
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer {
            window.isHidden = true
            window.rootViewController = nil
            previous?.makeKeyAndVisible()
        }
        try await Task.sleep(for: .milliseconds(200))
        let sampler = PageMotionSampler(probes: probes, window: window)
        sampler.start()
        defer { sampler.stop() }
        let expectedWidth = window.bounds.width - 160
        for liveTV in [false, true] {
            for opening in [true, false] {
                sampler.samples.removeAll()
                navigation.path = opening ? [.subtitles, .subtitleStyle(liveTV: liveTV)] : [.subtitles]
                try await Task.sleep(for: .milliseconds(650))
                if opening {
                    XCTAssertEqual(try XCTUnwrap(probes.frame("detail", in: window)).width,
                                   expectedWidth, accuracy: 1)
                }
                if !reduceMotion {
                    XCTAssertGreaterThanOrEqual(sampler.samples.count, 2,
                                               "Sample the actual animated overlap, not only the settled layout.")
                }
                for sample in sampler.samples {
                    XCTAssertEqual(sample.detailWidth, expectedWidth, accuracy: 1,
                                   "The style editor must not grow from or shrink to the two-column width.")
                }
                let attachment = XCTAttachment(string: String(describing: sampler.samples))
                attachment.name = "workspace-style-width-live-\(liveTV)-opening-\(opening)-reduced-\(reduceMotion)"
                attachment.lifetime = .keepAlways
                add(attachment)
            }
        }
    }

    func testBothPagesMoveAndFadeInBothDirectionsAndRetainTheRoot() async throws {
        try await verifySlides(direction: .leftToRight)
    }

    func testBothPagesMirrorTheirMovementInRightToLeftLayout() async throws {
        try await verifySlides(direction: .rightToLeft)
    }

    func testUnanimatedNavigationAndCancelledReturnsDoNotReleaseANewerTransition() async throws {
        try await withPages { navigation, probes, window in
            navigation.push(animated: false)
            try await Task.sleep(for: .milliseconds(100))
            let hiddenX: CGFloat = UIAccessibility.isReduceMotionEnabled ? 0 : -SettingsPageMotion.travelDistance
            XCTAssertEqual(try XCTUnwrap(probes.frame("root", in: window)).minX, hiddenX, accuracy: 2)
            XCTAssertEqual(try XCTUnwrap(probes.opacity("root")), 0, accuracy: 0.01)
            navigation.pop(animated: false)
            try await Task.sleep(for: .milliseconds(100))
            XCTAssertEqual(try XCTUnwrap(probes.frame("root", in: window)).minX, 0, accuracy: 2)
            XCTAssertEqual(navigation.returnFocusGeneration, 1)
            navigation.push(animated: false)
            try await Task.sleep(for: .milliseconds(100))
            navigation.pop(animated: true)
            navigation.reset()
            navigation.push(animated: false)
            try await Task.sleep(for: .milliseconds(600))
            XCTAssertTrue(navigation.isPresented)
            XCTAssertTrue(navigation.awaitingFocus)
            XCTAssertEqual(navigation.returnFocusGeneration, 0)
        }
    }

    func testSlideViewportPreservesVerticalSafeAreaWithoutHorizontalBleed() async throws {
        try await withPages(verticalSafeArea: 40, horizontalInset: 80) { navigation, probes, window in
            for isDetail in [false, true, false] {
                if isDetail {
                    navigation.push(animated: true)
                } else if navigation.isPresented {
                    navigation.focusArrived()
                    navigation.pop(animated: true)
                }
                try await Task.sleep(for: .milliseconds(600))
                window.layoutIfNeeded()
                let frame = try XCTUnwrap(probes.frame(isDetail ? "detail" : "root", in: window))
                XCTAssertGreaterThan(frame.minY, 8)
                XCTAssertLessThan(frame.maxY + 8, window.bounds.maxY)
                let format = UIGraphicsImageRendererFormat()
                format.scale = 1
                let image = UIGraphicsImageRenderer(bounds: window.bounds, format: format).image { _ in
                    XCTAssertTrue(window.drawHierarchy(in: window.bounds, afterScreenUpdates: true))
                }
                let attachment = XCTAttachment(image: image)
                attachment.name = isDetail ? "detail-safe-area" : "root-safe-area"
                attachment.lifetime = .keepAlways
                self.add(attachment)
                let expected = try self.pixel(image, at: CGPoint(x: frame.midX, y: frame.midY))
                let background = try self.pixel(image, at: CGPoint(x: 8, y: frame.midY))
                for y in [frame.minY - 8, frame.maxY + 8] {
                    XCTAssertEqual(
                        try self.pixel(image, at: CGPoint(x: frame.midX, y: y)), expected,
                        "The slide mask must not cut off content at the vertical safe-area boundary."
                    )
                }
                for x in [frame.minX - 8, frame.maxX + 8] {
                    let outside = try self.pixel(image, at: CGPoint(x: x, y: frame.midY))
                    XCTAssertEqual(outside, background,
                                   "Pages must remain clipped horizontally to preserve the slide.")
                }
            }
        }
    }

    private func pixel(_ image: UIImage, at point: CGPoint) throws -> [UInt8] {
        let source = try XCTUnwrap(image.cgImage)
        let crop = try XCTUnwrap(source.cropping(to: CGRect(x: point.x, y: point.y, width: 1, height: 1)))
        var bytes = [UInt8](repeating: 0, count: 4)
        try bytes.withUnsafeMutableBytes {
            let context = try XCTUnwrap(CGContext(
                data: $0.baseAddress, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ))
            context.draw(crop, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        }
        return bytes
    }

    private func verifySlides(direction: LayoutDirection) async throws {
        try await withPages(direction: direction) { navigation, probes, window in
            let width = window.bounds.width
            let sign: CGFloat = direction == .leftToRight ? 1 : -1
            let sampler = PageMotionSampler(probes: probes, window: window)
            sampler.start()
            defer { sampler.stop() }
            navigation.push(animated: true)
            try await Task.sleep(for: .milliseconds(600))
            self.assertIntermediatePages(sampler.samples, width: width, sign: sign)
            let hiddenX: CGFloat = UIAccessibility.isReduceMotionEnabled ? 0 : -sign * SettingsPageMotion.travelDistance
            XCTAssertEqual(try XCTUnwrap(probes.frame("root", in: window)).minX, hiddenX, accuracy: 2)
            navigation.focusArrived()
            sampler.samples.removeAll()
            navigation.pop(animated: true)
            try await Task.sleep(for: .milliseconds(600))
            self.assertIntermediatePages(sampler.samples, width: width, sign: sign)
            XCTAssertEqual(try XCTUnwrap(probes.frame("root", in: window)).minX, 0, accuracy: 2)
            XCTAssertEqual(probes.creations["root"], 1, "The parent page must retain its view/state during navigation.")
            XCTAssertEqual(navigation.returnFocusGeneration, 1)
        }
    }

    private func assertIntermediatePages(_ samples: [PageMotionSampler.Sample], width: CGFloat, sign: CGFloat) {
        let distance = SettingsPageMotion.travelDistance
        let moving = samples.filter {
            let root = $0.rootX * sign
            let detail = $0.detailX * sign
            return root < -distance * 0.05 && root > -distance * 0.95
                && detail > distance * 0.05 && detail < distance * 0.95
        }
        XCTAssertGreaterThanOrEqual(moving.count, 3, "Both pages must move gently between endpoints: \(samples)")
        if let first = moving.first, let last = moving.last {
            XCTAssertGreaterThan(last.time - first.time, 0.18, "The transition must not rush through its movement.")
        }
        for sample in samples {
            XCTAssertLessThanOrEqual(abs(sample.rootX), distance + 1)
            XCTAssertLessThanOrEqual(abs(sample.detailX), distance + 1)
            XCTAssertEqual(sample.rootWidth, width, accuracy: 1)
            XCTAssertEqual(sample.detailWidth, width, accuracy: 1)
        }
        for sample in moving {
            XCTAssertEqual((sample.detailX - sample.rootX) * sign, distance, accuracy: 2)
        }
        XCTAssertGreaterThanOrEqual(moving.filter {
            $0.rootOpacity > 0.01 && $0.rootOpacity < 0.99
                && $0.detailOpacity > 0.01 && $0.detailOpacity < 0.99
        }.count, 3, "Both pages must fade, not just move.")
        let attachment = XCTAttachment(string: String(describing: samples))
        attachment.name = "settings-page-motion"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func withPages(
        direction: LayoutDirection = .leftToRight,
        verticalSafeArea: CGFloat = 0,
        horizontalInset: CGFloat = 0,
        inspect: (SettingsDetailNavigation, PageMotionProbes, UIWindow) async throws -> Void
    ) async throws {
        let deadline = ContinuousClock.now + .seconds(5)
        while !UIApplication.shared.connectedScenes.contains(where: { $0.activationState == .foregroundActive }),
              ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive })
        let previous = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 960, height: 540)
        let navigation = SettingsDetailNavigation()
        let probes = PageMotionProbes()
        let host = UIHostingController(rootView:
            SettingsDetailPages(navigation: navigation) {
                PageMotionProbe(id: "root", probes: probes)
                    .background {
                        Color.blue
                            .ignoresSafeArea(.container, edges: .vertical)
                            .padding(.horizontal, -24)
                    }
            } detail: {
                PageMotionProbe(id: "detail", probes: probes)
                    .background {
                        Color.orange
                            .ignoresSafeArea(.container, edges: .vertical)
                            .padding(.horizontal, -24)
                    }
            }
            .padding(.horizontal, horizontalInset)
            .background { Color.red.ignoresSafeArea() }
            .environment(\.layoutDirection, direction)
            .ignoresSafeArea(edges: verticalSafeArea > 0 ? .horizontal : .all)
        )
        host.additionalSafeAreaInsets = UIEdgeInsets(
            top: verticalSafeArea, left: 0, bottom: verticalSafeArea, right: 0
        )
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer {
            window.isHidden = true
            window.rootViewController = nil
            previous?.makeKeyAndVisible()
        }
        try await Task.sleep(for: .milliseconds(200))
        try await inspect(navigation, probes, window)
    }
}

@MainActor
@Observable
private final class SettingsDialogProbe {
    var isPresented = false
    var inheritsSettingsPage: Bool?
    var dismiss: (() -> Void)?
}

private struct SettingsDialogDismissProbe: View {
    let probe: SettingsDialogProbe
    @SettingsPageDismiss private var dismiss
    @Environment(\.settingsPageContext) private var context

    var body: some View {
        Button("Close", action: dismiss)
            .onAppear {
                probe.inheritsSettingsPage = context != nil
                probe.dismiss = dismiss
            }
    }
}

@MainActor
private final class PageMotionProbes {
    var views: [String: UIView] = [:]
    var creations: [String: Int] = [:]

    func frame(_ id: String, in window: UIWindow) -> CGRect? {
        guard let view = views[id], view.window === window else { return nil }
        let layer = view.layer.presentation() ?? view.layer
        return layer.convert(layer.bounds, to: window.layer.presentation() ?? window.layer)
    }

    func opacity(_ id: String) -> Float? {
        guard let view = views[id], view.window != nil else { return nil }
        var opacity: Float = 1
        var layer: CALayer? = view.layer
        while let current = layer {
            opacity *= (current.presentation() ?? current).opacity
            layer = current.superlayer
        }
        return opacity
    }
}

private struct PageMotionProbe: UIViewRepresentable {
    let id: String
    let probes: PageMotionProbes

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.isUserInteractionEnabled = false
        probes.views[id] = view
        probes.creations[id, default: 0] += 1
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {}
}

@MainActor
private final class PageMotionSampler: NSObject {
    struct Sample: CustomStringConvertible {
        let time: CFTimeInterval
        let rootX: CGFloat
        let rootWidth: CGFloat
        let rootOpacity: Float
        let detailX: CGFloat
        let detailWidth: CGFloat
        let detailOpacity: Float
        var description: String {
            "time=\(time), root=\(rootX)/\(rootOpacity), detail=\(detailX)/\(detailOpacity), width=\(detailWidth)"
        }
    }

    var samples: [Sample] = []
    private let probes: PageMotionProbes
    private let window: UIWindow
    private var displayLink: CADisplayLink?

    init(probes: PageMotionProbes, window: UIWindow) {
        self.probes = probes
        self.window = window
    }

    func start() {
        let link = CADisplayLink(target: self, selector: #selector(sample))
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    func stop() {
        displayLink?.invalidate()
        displayLink = nil
    }

    @objc private func sample() {
        guard let root = probes.frame("root", in: window),
              let detail = probes.frame("detail", in: window),
              let rootOpacity = probes.opacity("root"),
              let detailOpacity = probes.opacity("detail") else { return }
        samples.append(Sample(time: CACurrentMediaTime(), rootX: root.minX, rootWidth: root.width,
                              rootOpacity: rootOpacity, detailX: detail.minX, detailWidth: detail.width,
                              detailOpacity: detailOpacity))
    }
}
