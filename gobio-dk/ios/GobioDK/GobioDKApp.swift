import FirebaseCore
import OSLog
import SwiftUI

@main
struct GobioDKApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    private static let logger = Logger(subsystem: "dk.gobio.app", category: "GobioDKApp")
    
    init() {
        FirebaseApp.configure()
    }
    
    var body: some Scene {
        WindowGroup {
            SplashView()
        }
    }
}
