import FirebaseCore
import UIKit
import XCTest
@testable import Apropos

@MainActor
final class AppDelegateNotificationBadgeTests: XCTestCase {
    func testActualActiveCallbackClearsLocalBadgeWhileReaderStartupIsBlocked() {
        let startup = ReaderSDKStartupState(), identity = CanonicalSessionState()
        _ = identity.adopt(.init(uid: "A", email: "local@example.invalid", isEmailVerified: true))
        XCTAssertFalse(startup.permitsReaderServices(identity: identity))
        var clears = 0, providerReads = 0
        let delegate = AppDelegate(startup: startup, identity: identity, actualUserID: {
            providerReads += 1; return "A"
        }, badgeClear: { clears += 1 })
        XCTAssertNil(FirebaseApp.allApps)
        delegate.applicationDidBecomeActive(UIApplication.shared)
        XCTAssertEqual(clears, 1)
        XCTAssertEqual(providerReads, 0)
        XCTAssertEqual(startup.status, .idle)
        XCTAssertFalse(startup.permitsReaderServices(identity: identity))
        XCTAssertNil(FirebaseApp.allApps)
    }

    func testUnresolvedReaderDoesNotBlockInjectedLocalBadgeClear() {
        let startup = ReaderSDKStartupState(), identity = CanonicalSessionState()
        XCTAssertEqual(identity.snapshot.context, .unresolved)
        XCTAssertFalse(startup.permitsReaderServices(identity: identity))
        var clears = 0
        let delegate = AppDelegate(startup: startup, identity: identity, badgeClear: { clears += 1 })
        delegate.applicationDidBecomeActive(UIApplication.shared)
        XCTAssertEqual(clears, 1)
        XCTAssertEqual(identity.snapshot.context, .unresolved)
        XCTAssertEqual(startup.status, .idle)
        XCTAssertNil(FirebaseApp.allApps)
    }

    func testDefaultTestHostActiveCallbackRetainsServiceAndOSLookupGuard() {
        let startup = ReaderSDKStartupState(), identity = CanonicalSessionState()
        var providerReads = 0
        // No badge effect is injected: the test-host guard must return before
        // selecting the live NotificationInboxRuntime/UNUserNotificationCenter.
        let delegate = AppDelegate(startup: startup, identity: identity,
            actualUserID: { providerReads += 1; return nil })
        delegate.applicationDidBecomeActive(UIApplication.shared)
        XCTAssertEqual(providerReads, 0)
        XCTAssertEqual(startup.status, .idle)
        XCTAssertNil(FirebaseApp.allApps)
    }
}
