import XCTest
import UIKit
@testable import Apropos

final class ArticleBackGestureTests: XCTestCase {
    @MainActor private final class Prior: NSObject, UIGestureRecognizerDelegate {
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool { true }
    }
    @MainActor private func fixture() -> (UINavigationController, UIViewController, ArticleNativeBackGestureEnabler.Controller, UIGestureRecognizer, Prior) {
        let root = UIViewController(), host = UIViewController()
        let nav = UINavigationController(rootViewController: root)
        nav.loadViewIfNeeded(); nav.setViewControllers([root, host], animated: false)
        let controller = ArticleNativeBackGestureEnabler.Controller()
        host.addChild(controller); host.view.addSubview(controller.view); controller.didMove(toParent: host)
        let gesture = nav.interactivePopGestureRecognizer!
        let prior = Prior(); gesture.delegate = prior; gesture.isEnabled = false
        controller.viewDidAppear(false)
        return (nav, host, controller, gesture, prior)
    }
    @MainActor func testActualNavigationOwnerEnablesAndRestoresOriginalState() {
        let (nav, host, controller, gesture, prior) = fixture()
        XCTAssertTrue(nav.topViewController === host)
        XCTAssertTrue(gesture.delegate === controller); XCTAssertTrue(gesture.isEnabled)
        XCTAssertTrue(controller.gestureRecognizerShouldBegin(gesture))
        XCTAssertTrue(controller.gestureRecognizer(gesture, shouldRecognizeSimultaneouslyWith: UIPanGestureRecognizer()))
        controller.viewDidDisappear(false)
        XCTAssertTrue(gesture.delegate === prior); XCTAssertFalse(gesture.isEnabled)
        XCTAssertFalse(controller.gestureRecognizerShouldBegin(gesture))
    }
    @MainActor func testWillDisappearAloneDoesNotReleaseGestureOwnership() {
        let (_, _, controller, gesture, _) = fixture()
        controller.viewWillDisappear(true)
        XCTAssertTrue(gesture.delegate === controller)
        controller.viewDidAppear(true)
        XCTAssertTrue(gesture.delegate === controller)
        XCTAssertTrue(controller.gestureRecognizerShouldBegin(gesture))
        controller.deactivate()
    }
    @MainActor func testForeignDelegateAndDisabledStateAreNotClobbered() {
        let (_, _, controller, gesture, _) = fixture()
        let foreign = Prior(); gesture.delegate = foreign; gesture.isEnabled = false
        controller.viewDidDisappear(false)
        XCTAssertTrue(gesture.delegate === foreign); XCTAssertFalse(gesture.isEnabled)
        controller.viewDidAppear(false)
        XCTAssertTrue(gesture.delegate === controller); XCTAssertTrue(gesture.isEnabled)
        controller.deactivate()
        XCTAssertTrue(gesture.delegate === foreign); XCTAssertFalse(gesture.isEnabled)
    }
    @MainActor func testRootOtherTopAndUnrelatedRecognizerCannotBegin() {
        let (nav, _, controller, gesture, _) = fixture()
        XCTAssertFalse(controller.gestureRecognizerShouldBegin(UIPanGestureRecognizer()))
        nav.pushViewController(UIViewController(), animated: false)
        XCTAssertFalse(controller.gestureRecognizerShouldBegin(gesture))
        nav.popToRootViewController(animated: false)
        XCTAssertFalse(controller.gestureRecognizerShouldBegin(gesture))
        controller.deactivate()
    }
    @MainActor func testNewerArticleOwnershipSurvivesOlderTeardownAndReturns() {
        let (nav, _, older, gesture, _) = fixture()
        let secondHost = UIViewController()
        nav.pushViewController(secondHost, animated: false)
        let newer = ArticleNativeBackGestureEnabler.Controller()
        secondHost.addChild(newer); secondHost.view.addSubview(newer.view); newer.didMove(toParent: secondHost)
        newer.viewDidAppear(false)
        XCTAssertTrue(gesture.delegate === newer)
        older.viewDidDisappear(false)
        XCTAssertTrue(gesture.delegate === newer)
        XCTAssertTrue(newer.gestureRecognizerShouldBegin(gesture))
        nav.popViewController(animated: false)
        newer.viewDidDisappear(false)
        older.viewDidAppear(false)
        XCTAssertTrue(gesture.delegate === older)
        XCTAssertTrue(older.gestureRecognizerShouldBegin(gesture))
        older.deactivate()
    }
    @MainActor func testRetainedRemovedOlderArticleRestoresBaselineForNonArticleTop() {
        let f = fixture()
        defer { withExtendedLifetime(f) {} }
        let nav = f.0, olderHost = f.1, older = f.2, gesture = f.3, prior = f.4
        let newerHost = UIViewController()
        nav.pushViewController(newerHost, animated: false)
        let newer = ArticleNativeBackGestureEnabler.Controller()
        newerHost.addChild(newer); newerHost.view.addSubview(newer.view); newer.didMove(toParent: newerHost)
        newer.viewDidAppear(false)
        older.viewDidDisappear(false)
        XCTAssertTrue(gesture.delegate === newer)
        let other = UIViewController()
        nav.setViewControllers([nav.viewControllers[0], other, newerHost], animated: false)
        XCTAssertFalse(nav.viewControllers.contains(where: { $0 === olderHost }))
        nav.popViewController(animated: false)
        newer.viewDidDisappear(false)
        XCTAssertTrue(nav.topViewController === other)
        XCTAssertTrue(gesture.delegate === prior)
        XCTAssertFalse(gesture.isEnabled)
        older.deactivate()
    }

}
