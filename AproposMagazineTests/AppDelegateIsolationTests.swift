import XCTest
import UIKit
import FirebaseCore
@testable import Apropos

final class AppDelegateIsolationTests: XCTestCase {
    @MainActor
    func testLifecycleAndBackgroundCallbacksCannotStartServicesInTestHost() {
        let delegate = AppDelegate()
        let application = UIApplication.shared
        XCTAssertNil(FirebaseApp.allApps)
        XCTAssertTrue(delegate.application(application, didFinishLaunchingWithOptions: nil))
        delegate.applicationDidBecomeActive(application)
        delegate.applicationWillEnterForeground(application)
        delegate.applicationDidEnterBackground(application)
        delegate.applicationDidReceiveMemoryWarning(application)
        delegate.application(application, didRegisterForRemoteNotificationsWithDeviceToken: Data([1]))
        delegate.application(application, didFailToRegisterForRemoteNotificationsWithError: URLError(.notConnectedToInternet))
        XCTAssertFalse(delegate.application(application, open: URL(string: "aproposmagazine://article/test")!))

        var callbacks = 0
        delegate.application(application, performFetchWithCompletionHandler: { result in
            XCTAssertEqual(result, .noData)
            callbacks += 1
        })
        delegate.application(application, didReceiveRemoteNotification: [:], fetchCompletionHandler: { result in
            XCTAssertEqual(result, .noData)
            callbacks += 1
        })
        XCTAssertEqual(callbacks, 2)
        XCTAssertNil(FirebaseApp.allApps)
    }
}
