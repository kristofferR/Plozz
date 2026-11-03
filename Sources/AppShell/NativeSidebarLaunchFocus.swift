#if os(tvOS)
import CoreNetworking
import SwiftUI
import UIKit

/// Moves fresh-launch focus from the native sidebar into the selected page, so
/// `.sidebarAdaptable` starts collapsed. tvOS gives the sidebar first focus, the
/// sidebar expands whenever it holds focus, and SwiftUI's default-focus
/// preferences cannot outrank it.
///
/// Place it behind the selected page inside a ``NavigationRailFocusHost``. It
/// retries briefly while the page is loading or has nothing focusable yet, and
/// settles as soon as focus leaves the sidebar or the viewer moves focus.
struct NativeSidebarLaunchFocusAnchor: UIViewRepresentable {
    let isRequested: Bool
    let onSettled: () -> Void

    func makeUIView(context: Context) -> AnchorView {
        let view = AnchorView()
        view.isUserInteractionEnabled = false
        view.isAccessibilityElement = false
        return view
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
        /// Covers a cold Home load; each attempt is one entry search.
        static let attemptInterval = Duration.milliseconds(100)
        static let maximumAttempts = 50

        var isRightToLeft = false
        var onSettled: (() -> Void)?
        var isRequested = false {
            didSet { if isRequested != oldValue { update() } }
        }
        private var attempts: Task<Void, Never>?
        private var focusObserver: (any NSObjectProtocol)?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            update()
        }

        private func update() {
            guard isRequested, let window else {
                stop()
                return
            }
            guard attempts == nil else { return }
            focusObserver = NotificationCenter.default.addObserver(
                forName: UIFocusSystem.didUpdateNotification, object: nil, queue: .main
            ) { [weak self] notification in
                let context = notification.userInfo?[UIFocusSystem.focusUpdateContextUserInfoKey]
                    as? UIFocusUpdateContext
                // Programmatic updates have no heading; a remote swipe does.
                guard let context, !context.focusHeading.isEmpty else { return }
                MainActor.assumeIsolated { self?.settle() }
            }
            attempts = Task { @MainActor [weak self, weak window] in
                for _ in 0..<Self.maximumAttempts {
                    try? await Task.sleep(for: Self.attemptInterval)
                    guard !Task.isCancelled, let self, let window, self.window === window else { return }
                    if self.focusPage(in: window) {
                        self.settle()
                        return
                    }
                }
                PlozzLog.app.debug("Native sidebar launch page never accepted focus")
                self?.settle()
            }
        }

        /// Returns `true` once focus is outside the sidebar.
        private func focusPage(in window: UIWindow) -> Bool {
            guard let system = UIFocusSystem.focusSystem(for: window),
                  let focused = system.focusedItem else { return false }
            // The native sidebar is a list; launch focus starts on one of its rows.
            guard let sidebar = Self.enclosingList(of: focused) else { return true }
            let selection = NavigationContentFocusRequester.entrySelection(
                in: window, relativeTo: self, isRightToLeft: isRightToLeft,
                excludesNavigationItem: { Self.environment(sidebar, contains: $0) }
            )
            guard let target = selection.target,
                  let owner = NavigationRailFocusHostController.containing(self) else { return false }
            return owner.requestFocus(to: target, using: system)
        }

        private static func enclosingList(of item: any UIFocusItem) -> UICollectionView? {
            var current: (any UIFocusEnvironment)? = item
            while let environment = current {
                if let list = environment as? UICollectionView { return list }
                current = environment.parentFocusEnvironment
            }
            return nil
        }

        private static func environment(_ environment: any UIFocusEnvironment, contains item: any UIFocusItem) -> Bool {
            var current: (any UIFocusEnvironment)? = item
            while let candidate = current {
                if candidate === environment { return true }
                current = candidate.parentFocusEnvironment
            }
            return false
        }

        private func settle() {
            guard attempts != nil else { return }
            stop()
            onSettled?()
        }

        private func stop() {
            attempts?.cancel()
            attempts = nil
            if let focusObserver { NotificationCenter.default.removeObserver(focusObserver) }
            focusObserver = nil
        }
    }
}
#endif
