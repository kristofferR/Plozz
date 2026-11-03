#if os(tvOS)
import CoreNetworking
import SwiftUI
import UIKit

/// Keeps fresh-launch focus out of the native sidebar, so `.sidebarAdaptable`
/// starts collapsed. tvOS gives the sidebar first focus, the sidebar expands
/// whenever it holds focus, and SwiftUI's default-focus preferences cannot
/// outrank it.
///
/// Place it behind Home inside a ``NavigationRailFocusHost``. It treats every list
/// as the sidebar, so it suits only a page without lists, which Home is. The
/// moment the sidebar takes launch focus, the anchor takes it back, holding it
/// itself while the page loads, then hands focus to the page's entry. It settles
/// when focus reaches the page, the viewer moves focus, or the viewer presses Back.
struct NativeSidebarLaunchFocusAnchor: UIViewRepresentable {
    let isRequested: Bool
    let onSettled: () -> Void

    func makeUIView(context: Context) -> AnchorView {
        AnchorView()
    }

    func updateUIView(_ view: AnchorView, context: Context) {
        view.isRightToLeft = context.environment.layoutDirection == .rightToLeft
        view.onSettled = onSettled
        view.isRequested = isRequested
    }

    static func dismantleUIView(_ view: AnchorView, coordinator: ()) {
        view.onSettled = nil
        view.isRequested = false
    }

    final class AnchorView: UIView {
        /// Covers a slow Home load; each attempt is one entry search.
        static let attemptInterval = Duration.milliseconds(100)
        static let maximumAttempts = 150

        var isRightToLeft = false
        var onSettled: (() -> Void)?
        var isRequested = false {
            didSet { if isRequested != oldValue { update() } }
        }
        private var attempts: Task<Void, Never>?
        private var focusObserver: (any NSObjectProtocol)?
        private weak var owner: NavigationRailFocusHostController?
        /// Focusable only while it stands in for the page at launch.
        private var holdsFocus = false

        override var canBecomeFocused: Bool { holdsFocus }

        override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
            // Back opens the sidebar without a focus heading; let it rather than take focus back.
            if presses.contains(where: { $0.type == .menu }) { settle() }
            super.pressesBegan(presses, with: event)
        }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            update()
        }

        private func update() {
            guard isRequested, let window, let owner = NavigationRailFocusHostController.containing(self) else {
                stop()
                return
            }
            guard attempts == nil else { return }
            self.owner = owner
            holdsFocus = true
            focusObserver = NotificationCenter.default.addObserver(
                forName: UIFocusSystem.didUpdateNotification, object: nil, queue: .main
            ) { [weak self] notification in
                let context = notification.userInfo?[UIFocusSystem.focusUpdateContextUserInfoKey]
                    as? UIFocusUpdateContext
                guard let context else { return }
                MainActor.assumeIsolated {
                    // Programmatic updates have no heading; a remote swipe does.
                    if !context.focusHeading.isEmpty {
                        self?.settle()
                    } else if let next = context.nextFocusedItem, Self.enclosingList(of: next) != nil {
                        // tvOS focuses the sidebar once the app is active, ignoring
                        // earlier requests; take focus back as soon as this update ends.
                        DispatchQueue.main.async { self?.attempt() }
                    }
                }
            }
            attempts = Task { @MainActor [weak self] in
                for _ in 0..<Self.maximumAttempts {
                    guard !Task.isCancelled, let self else { return }
                    if self.attempt() { return }
                    try? await Task.sleep(for: Self.attemptInterval)
                }
                PlozzLog.app.debug("Native sidebar launch page never accepted focus")
                self?.settle()
            }
        }

        /// Returns `true` once settled.
        @discardableResult
        private func attempt() -> Bool {
            guard attempts != nil, let window else { return true }
            guard focusPage(in: window) else { return false }
            settle()
            return true
        }

        /// Returns `true` once focus is on the page itself.
        private func focusPage(in window: UIWindow) -> Bool {
            guard let system = UIFocusSystem.focusSystem(for: window), let owner else { return false }
            // The native sidebar is a list, and the launch page (Home) has none.
            if let focused = system.focusedItem, focused !== self, Self.enclosingList(of: focused) == nil {
                return true
            }
            let selection = NavigationContentFocusRequester.entrySelection(
                in: window, relativeTo: self, isRightToLeft: isRightToLeft,
                excludesNavigationItem: { [weak self] item in
                    item === self || Self.enclosingList(of: item) != nil
                }
            )
            if let target = selection.target {
                return owner.requestFocus(to: target, using: system)
            }
            // Nothing to focus yet: hold focus here so the sidebar stays collapsed.
            if system.focusedItem !== self {
                _ = owner.requestFocus(to: self, using: system)
            }
            return false
        }

        private static func enclosingList(of item: any UIFocusItem) -> UICollectionView? {
            var current: (any UIFocusEnvironment)? = item
            while let environment = current {
                if let list = environment as? UICollectionView { return list }
                current = environment.parentFocusEnvironment
            }
            return nil
        }

        private func settle() {
            guard attempts != nil else { return }
            stop()
            onSettled?()
        }

        private func stop() {
            attempts?.cancel()
            attempts = nil
            if holdsFocus {
                holdsFocus = false
                if isFocused { owner?.setNeedsFocusUpdate() }
            }
            owner = nil
            if let focusObserver { NotificationCenter.default.removeObserver(focusObserver) }
            focusObserver = nil
        }
    }
}
#endif
