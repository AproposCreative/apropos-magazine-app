import SwiftUI
import UIKit

/// Restores only the native edge-pop gesture belonging to this pushed article.
/// It does not create a drag recognizer, dismiss action or navigation authority.
struct ArticleNativeBackGestureEnabler: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> Controller { Controller() }
    func updateUIViewController(_ controller: Controller, context: Context) { controller.refreshIfVisible() }
    static func dismantleUIViewController(_ controller: Controller, coordinator: Void) { controller.deactivate() }

    final class Controller: UIViewController, UIGestureRecognizerDelegate {
        private weak var ownedNavigation: UINavigationController?
        private weak var ownedHost: UIViewController?
        private weak var ownedGesture: UIGestureRecognizer?
        private weak var previousDelegate: UIGestureRecognizerDelegate?
        private var previousEnabled = false
        // A nested article can temporarily replace this owner. Keep the original
        // UIKit delegate as a weak fallback if an older article is removed first.
        private weak var baselineDelegate: UIGestureRecognizerDelegate?
        private var baselineEnabled = false
        private var visible = false

        override func loadView() {
            view = UIView(frame: .zero)
            view.isUserInteractionEnabled = false
            view.isAccessibilityElement = false
        }
        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            visible = true
            refreshIfVisible()
        }
        override func viewDidDisappear(_ animated: Bool) {
            super.viewDidDisappear(animated)
            deactivate()
        }
        override func viewDidLayoutSubviews() {
            super.viewDidLayoutSubviews()
            refreshIfVisible()
        }
        override func didMove(toParent parent: UIViewController?) {
            super.didMove(toParent: parent)
            refreshIfVisible()
        }

        func refreshIfVisible() {
            guard visible, let navigation = navigationController,
                  let gesture = navigation.interactivePopGestureRecognizer else { return }
            // Resolve only this controller's ancestry, never a global window or
            // another tab's navigation stack. The host must be the pushed top.
            var candidate: UIViewController? = self
            var host: UIViewController?
            while let current = candidate, current !== navigation {
                if navigation.viewControllers.contains(where: { $0 === current }) { host = current; break }
                candidate = current.parent
            }
            guard let host, navigation.topViewController === host,
                  navigation.viewControllers.count > 1 else { return }
            if ownedGesture === gesture {
                // Another owner may deliberately have replaced us. Do not steal
                // its delegate or re-enable a gesture it disabled.
                if gesture.delegate === self { gesture.isEnabled = true }
                return
            }
            releaseIfOwned()
            ownedNavigation = navigation
            ownedHost = host
            ownedGesture = gesture
            previousDelegate = gesture.delegate
            previousEnabled = gesture.isEnabled
            if let olderArticle = gesture.delegate as? Controller {
                baselineDelegate = olderArticle.baselineDelegate
                baselineEnabled = olderArticle.baselineEnabled
            } else {
                baselineDelegate = gesture.delegate
                baselineEnabled = gesture.isEnabled
            }
            gesture.delegate = self
            gesture.isEnabled = true
        }

        func deactivate() {
            visible = false
            releaseIfOwned()
        }
        private func releaseIfOwned() {
            guard let gesture = ownedGesture else { clearOwnership(); return }
            guard gesture.delegate === self else {
                // A newer article can still restore this older owner. Keep its
                // weak chain until then; unrelated owners remain untouched and
                // do not prevent a fresh acquisition on a later appearance.
                if !(gesture.delegate is Controller) { clearOwnership() }
                return
            }
            let previous = validPreviousDelegate(requiresTopHost: true)
            gesture.delegate = previous ?? canonicalBaselineDelegate
            gesture.isEnabled = previous != nil ? previousEnabled : baselineEnabled
            clearOwnership()
        }

        /// An older article may be alive but removed from the navigation path.
        /// Only a still-current host may resume edge-pop ownership. Visibility
        /// is deliberately not required: UIKit can restore the older delegate
        /// immediately before delivering that host's viewDidAppear.
        private func validPreviousDelegate(requiresTopHost: Bool) -> UIGestureRecognizerDelegate? {
            guard let previous = previousDelegate else { return nil }
            if let olderArticle = previous as? Controller {
                guard let navigation = ownedNavigation, let gesture = ownedGesture,
                      olderArticle.ownsContext(gesture: gesture, navigation: navigation,
                                              requiresTopHost: requiresTopHost) else { return nil }
            }
            return previous
        }
        private func ownsContext(gesture: UIGestureRecognizer, navigation: UINavigationController,
                                 requiresTopHost: Bool) -> Bool {
            guard ownedGesture === gesture, ownedNavigation === navigation,
                  let host = ownedHost,
                  navigation.viewControllers.contains(where: { $0 === host }) else { return false }
            return !requiresTopHost || (navigation.topViewController === host && navigation.viewControllers.count > 1)
        }
        private var canonicalBaselineDelegate: UIGestureRecognizerDelegate? {
            // Baseline comes from the original non-article owner. Never revive
            // another article through a fallback if a nested chain is obsolete.
            baselineDelegate is Controller ? nil : baselineDelegate
        }
        private var inheritedDelegate: UIGestureRecognizerDelegate? {
            // While this article is top, the older article is not. Its optional
            // callbacks are usable only while its host remains in the same stack.
            validPreviousDelegate(requiresTopHost: false) ?? canonicalBaselineDelegate
        }

        private func clearOwnership() {
            ownedGesture = nil
            ownedHost = nil
            ownedNavigation = nil
            previousDelegate = nil
            baselineDelegate = nil
            previousEnabled = false
            baselineEnabled = false
        }

        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard visible, gestureRecognizer === ownedGesture,
                  let navigation = ownedNavigation, let host = ownedHost,
                  navigation.topViewController === host,
                  navigation.viewControllers.count > 1,
                  navigation.transitionCoordinator == nil,
                  !navigation.isBeingDismissed,
                  navigation.presentedViewController == nil,
                  host.presentedViewController == nil else { return false }
            return true
        }

        // Preserve UIKit's existing touch/competition policy. Only shouldBegin
        // substitutes the hidden-back guard with explicit owner/depth checks.
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            inheritedDelegate?.gestureRecognizer?(gestureRecognizer, shouldRecognizeSimultaneouslyWith: otherGestureRecognizer) ?? false
        }
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRequireFailureOf otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            inheritedDelegate?.gestureRecognizer?(gestureRecognizer, shouldRequireFailureOf: otherGestureRecognizer) ?? false
        }
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldBeRequiredToFailBy otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            inheritedDelegate?.gestureRecognizer?(gestureRecognizer, shouldBeRequiredToFailBy: otherGestureRecognizer) ?? false
        }
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            inheritedDelegate?.gestureRecognizer?(gestureRecognizer, shouldReceive: touch) ?? true
        }
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive press: UIPress) -> Bool {
            inheritedDelegate?.gestureRecognizer?(gestureRecognizer, shouldReceive: press) ?? true
        }
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive event: UIEvent) -> Bool {
            inheritedDelegate?.gestureRecognizer?(gestureRecognizer, shouldReceive: event) ?? true
        }
    }
}

extension View {
    /// Keep this modifier on the stable article host, outside availability and
    /// renderer branches. UIKit owns progress, completion and cancellation.
    func articleNativeBackNavigation() -> some View {
        navigationBarBackButtonHidden(true)
            .background(ArticleNativeBackGestureEnabler())
    }
}
