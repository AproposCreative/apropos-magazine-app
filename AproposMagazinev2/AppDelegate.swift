import SwiftUI
import FirebaseCore
import FirebaseMessaging
import UserNotifications
import GoogleSignIn
import UIKit

@objc final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate, MessagingDelegate {
    
    // MARK: - UIApplicationDelegate Methods

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {

        print("📱 AppDelegate: didFinishLaunchingWithOptions called")
        
        // Ensure Firebase is configured
        if FirebaseApp.app() == nil {
            FirebaseApp.configure()
            print("✅ AppDelegate: Firebase configured")
        } else {
            print("ℹ️ AppDelegate: Firebase already configured")
        }

        // Set up notification delegate
        UNUserNotificationCenter.current().delegate = self
        
        // Request notification permissions with a longer delay to ensure app is fully loaded
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
            print("📱 Requesting notification permissions...")
            
            // First check current authorization status
            UNUserNotificationCenter.current().getNotificationSettings { settings in
                print("📱 Current notification settings:")
                print("   - Authorization status: \(settings.authorizationStatus.rawValue)")
                print("   - Alert setting: \(settings.alertSetting.rawValue)")
                print("   - Badge setting: \(settings.badgeSetting.rawValue)")
                print("   - Sound setting: \(settings.soundSetting.rawValue)")
                
                // Only request if not already authorized
                if settings.authorizationStatus == .notDetermined {
                    print("📱 Authorization status is not determined, requesting permissions...")
                    UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound, .provisional]) { granted, error in
                        DispatchQueue.main.async {
                            if granted {
                                print("✅ Notification permission granted")
                                application.registerForRemoteNotifications()
                            } else {
                                print("❌ Notification permission denied: \(error?.localizedDescription ?? "Unknown error")")
                            }
                        }
                    }
                } else if settings.authorizationStatus == .authorized {
                    print("✅ Notification permissions already authorized")
                    DispatchQueue.main.async {
                        application.registerForRemoteNotifications()
                    }
                } else if settings.authorizationStatus == .denied {
                    print("⚠️ Notification permissions denied by user. Status: \(settings.authorizationStatus.rawValue)")
                    // Don't try to register for remote notifications if denied
                } else {
                    print("⚠️ Notification permissions not authorized, status: \(settings.authorizationStatus.rawValue)")
                }
            }
        }

        // Set up FCM delegate
        Messaging.messaging().delegate = self
        
        // Log existing FCM token if available
        if let existingToken = UserDefaults.standard.string(forKey: "FCMRegistrationToken") {
            print("📱 Existing FCM Token: \(existingToken)")
        }
        
        // Configure Google Sign-In
        GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: "817066738308-q8pdk1q5b9t9ugopjh67i2n2lau9k3sm.apps.googleusercontent.com")
        
        print("ℹ️ AppDelegate: Firebase AppDelegateProxy disabled via Info.plist")
        


        return true
    }

    // APNs token -> FCM
    func application(_ application: UIApplication,
                     didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        print("📱 APNS Device Token received: \(deviceToken.map { String(format: "%02.2hhx", $0) }.joined())")
        Messaging.messaging().apnsToken = deviceToken
        
        // Now that we have APNS token, we can safely get FCM token
        Messaging.messaging().token { token, error in
            if let error = error {
                print("❌ Error fetching FCM token: \(error)")
            } else if let token = token {
                print("✅ FCM Registration Token: \(token)")
                UserDefaults.standard.set(token, forKey: "FCMRegistrationToken")
                
                // Update the NotificationService
                DispatchQueue.main.async {
                    NotificationService.shared.fcmToken = token
                }
            }
        }
    }
    
    // Handle APNs registration failure
    func application(_ application: UIApplication,
                     didFailToRegisterForRemoteNotificationsWithError error: Error) {
        print("❌ Failed to register for remote notifications: \(error)")
    }

    // FCM token refresh
    func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        if let token = fcmToken {
            print("✅ FCM Registration Token refreshed: \(token)")
            print("📱 Token Length: \(token.count) characters")
            
            // Save token in UserDefaults
            UserDefaults.standard.set(token, forKey: "FCMRegistrationToken")
            
            // Update NotificationService
            DispatchQueue.main.async {
                NotificationService.shared.fcmToken = token
            }
            
            // Log token to console for easy copying
            print("📱 === FCM TOKEN START ===")
            print(token)
            print("📱 === FCM TOKEN END ===")
        } else {
            print("❌ FCM token is nil")
        }
    }

    // Handle notification when app is in foreground
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        print("📱 Received notification in foreground: \(notification.request.content.title)")
        print("📱 Notification content: \(notification.request.content.body)")
        print("📱 Notification userInfo: \(notification.request.content.userInfo)")
        
        // Add haptic feedback for notifications
        let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
        impactFeedback.impactOccurred()
        
        return [.banner, .sound, .badge]
    }
    
    // Handle notification tap when app is in background
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse) async {
        print("📱 User tapped notification: \(response.notification.request.content.title)")
        
        // Handle the notification tap here
        let userInfo = response.notification.request.content.userInfo
        print("📱 Notification userInfo: \(userInfo)")
        
        // Check if this is a new article notification
        if let type = userInfo["type"] as? String, type == "new_article",
           let articleId = userInfo["article_id"] as? String, !articleId.isEmpty {
            
            print("📱 Opening article with ID: \(articleId)")
            
            // Post notification to open the article
            DispatchQueue.main.async {
                NotificationCenter.default.post(
                    name: NSNotification.Name("OpenArticleFromNotification"),
                    object: nil,
                    userInfo: ["articleId": articleId]
                )
            }
        }
    }
    
    // Handle Google Sign-In URL
    func application(_ app: UIApplication, open url: URL, options: [UIApplication.OpenURLOptionsKey : Any] = [:]) -> Bool {
        return GIDSignIn.sharedInstance.handle(url)
    }
    
    // MARK: - Application Lifecycle
    func applicationDidEnterBackground(_ application: UIApplication) {
        print("📱 AppDelegate: Application entered background")
    }
    
    func applicationWillEnterForeground(_ application: UIApplication) {
        print("📱 AppDelegate: Application will enter foreground")
    }
    
    func applicationDidBecomeActive(_ application: UIApplication) {
        print("📱 AppDelegate: Application became active")
    }
    
    func applicationWillResignActive(_ application: UIApplication) {
        print("📱 AppDelegate: Application will resign active")
    }
    
    func applicationWillTerminate(_ application: UIApplication) {
        print("📱 AppDelegate: Application will terminate")
    }
}
