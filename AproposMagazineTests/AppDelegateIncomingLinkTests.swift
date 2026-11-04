import FirebaseCore
import UIKit
import XCTest
@testable import Apropos

/// Runs the actual UIApplicationDelegate methods with memory entry effects.
/// The remaining service lifecycle stays disabled in the XCTest host.
final class AppDelegateIncomingLinkTests: XCTestCase {
    @MainActor func testActualDelegateReturnsValidationResultAndPreservesTimestamp() {
        XCTAssertNil(FirebaseApp.allApps)
        var received: [DeepLink] = []
        let entry = IncomingLinkEntry(disabled: false, handleGoogle: { _ in false }, accept: { url in
            guard let link = DeepLink.parse(url) else { return false }
            received.append(link);return true
        })
        let delegate = AppDelegate(linkEntry: entry)
        XCTAssertTrue(delegate.application(UIApplication.shared, open: URL(string: "aproposmagazine://article/a?t=0")!))
        let activity = NSUserActivity(activityType: NSUserActivityTypeBrowsingWeb)
        activity.webpageURL = URL(string: "https://aproposmagazine.com/article/b?t=125")!
        XCTAssertTrue(delegate.application(UIApplication.shared, continue: activity, restorationHandler: { _ in XCTFail("No restoration effect expected") }))
        XCTAssertEqual(received, [.podcast(id: "a", startSeconds: 0), .podcast(id: "b", startSeconds: 125)])
        XCTAssertNil(FirebaseApp.allApps)
    }
    @MainActor func testActualDelegateRejectsUnrelatedActivityAndUnsupportedHost() {
        var accepted = 0
        let delegate = AppDelegate(linkEntry: .init(disabled: false, handleGoogle: { _ in false }, accept: { _ in accepted += 1;return true }))
        let activity = NSUserActivity(activityType: "unrelated-activity")
        activity.webpageURL = URL(string: "https://aproposmagazine.com/article/a")!
        XCTAssertFalse(delegate.application(UIApplication.shared, continue: activity, restorationHandler: { _ in }))
        let foreign = NSUserActivity(activityType: NSUserActivityTypeBrowsingWeb)
        foreign.webpageURL = URL(string: "https://example.com/article/a")!
        XCTAssertFalse(delegate.application(UIApplication.shared, continue: foreign, restorationHandler: { _ in }))
        XCTAssertFalse(delegate.application(UIApplication.shared, open: URL(string: "aproposmagazine://unknown/a")!))
        XCTAssertEqual(accepted, 0)
        XCTAssertNil(FirebaseApp.allApps)
    }
    @MainActor func testDefaultTestDelegateNeverActivatesNormalRuntime() {
        let delegate = AppDelegate()
        let activity = NSUserActivity(activityType: NSUserActivityTypeBrowsingWeb)
        activity.webpageURL = URL(string: "https://aproposmagazine.com/article/a")!
        XCTAssertFalse(delegate.application(UIApplication.shared, continue: activity, restorationHandler: { _ in }))
        XCTAssertFalse(delegate.application(UIApplication.shared, open: URL(string: "aproposmagazine://article/a")!))
        XCTAssertNil(FirebaseApp.allApps)
    }
}
