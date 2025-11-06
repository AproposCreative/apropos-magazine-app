import FirebaseCore
import FirebaseMessaging
import UserNotifications
import GoogleSignIn
import UIKit
import OSLog
import SwiftUI

@objc final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate, MessagingDelegate {
    
    private let logger = Logger(subsystem: "com.aproposmagazine.app", category: "AppDelegate")
    
    // MARK: - UIApplicationDelegate Methods

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {

        logger.info("didFinishLaunchingWithOptions")
        
        // Ensure Firebase is configured
        if FirebaseApp.app() == nil {
            FirebaseApp.configure()
            logger.info("Firebase konfigureret.")
        } else {
            logger.debug("Firebase allerede konfigureret.")
        }

        // Set up notification delegate
        UNUserNotificationCenter.current().delegate = self
        
        // Request notification permissions with a longer delay to ensure app is fully loaded
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
            self.logger.info("Anmoder om notifikations-tilladelser.")
            
            // First check current authorization status
            UNUserNotificationCenter.current().getNotificationSettings { settings in
                self.logger.debug("Notification settings: authorization=\(settings.authorizationStatus.rawValue, privacy: .public), alert=\(settings.alertSetting.rawValue, privacy: .public), badge=\(settings.badgeSetting.rawValue, privacy: .public), sound=\(settings.soundSetting.rawValue, privacy: .public)")
                
                // Only request if not already authorized
                if settings.authorizationStatus == .notDetermined {
                    self.logger.info("Notifikationsstatus ukendt – anmoder nu.")
                    UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound, .provisional]) { granted, error in
                        DispatchQueue.main.async {
                            if granted {
                                self.logger.info("Notifikationstilladelse givet.")
                                application.registerForRemoteNotifications()
                            } else {
                                if let error {
                                    self.logger.error("Notifikationstilladelse afvist: \(error.localizedDescription, privacy: .public)")
                                } else {
                                    self.logger.warning("Notifikationstilladelse afvist uden fejl.")
                                }
                            }
                        }
                    }
                } else if settings.authorizationStatus == .authorized {
                    self.logger.debug("Notifikationstilladelse allerede givet.")
                    DispatchQueue.main.async {
                        application.registerForRemoteNotifications()
                    }
                } else if settings.authorizationStatus == .denied {
                    self.logger.warning("Notifikations-tilladelse afvist af bruger.")
                    // Don't try to register for remote notifications if denied
                } else {
                    self.logger.warning("Notifikationstilladelse ikke givet. Status=\(settings.authorizationStatus.rawValue, privacy: .public)")
                }
            }
        }

        // Set up FCM delegate
        Messaging.messaging().delegate = self
        
        // Log existing FCM token if available
        if UserDefaults.standard.string(forKey: "FCMRegistrationToken") != nil {
            logger.debug("Eksisterende FCM token fundet.")
        }
        
        // Configure Google Sign-In
        GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: "817066738308-q8pdk1q5b9t9ugopjh67i2n2lau9k3sm.apps.googleusercontent.com")
        
        logger.debug("Firebase AppDelegateProxy er deaktiveret via Info.plist.")
        


        return true
    }

    // APNs token -> FCM
    func application(_ application: UIApplication,
                     didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        logger.debug("APNS token modtaget.")
        Messaging.messaging().apnsToken = deviceToken
        
        // Now that we have APNS token, we can safely get FCM token
        Messaging.messaging().token { token, error in
            if let error = error {
                self.logger.error("Fejl ved hentning af FCM token: \(error.localizedDescription, privacy: .public)")
            } else if let token = token {
                self.logger.info("FCM token hentet.")
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
        logger.error("Fejl ved registrering af fjernnotifikationer: \(error.localizedDescription, privacy: .public)")
    }

    // FCM token refresh
    func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        if let token = fcmToken {
            logger.info("FCM token fornyet.")
            logger.debug("FCM token længde: \(token.count, privacy: .public)")
            
            // Save token in UserDefaults
            UserDefaults.standard.set(token, forKey: "FCMRegistrationToken")
            
            // Update NotificationService
            DispatchQueue.main.async {
                NotificationService.shared.fcmToken = token
            }
            
            logger.debug("FCM token gemt lokalt.")
        } else {
            logger.warning("Fik null FCM token.")
        }
    }

    // Handle notification when app is in foreground
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        logger.debug("Notifikation i forgrund: \(notification.request.content.title, privacy: .public)")
        logger.debug("Indhold: \(notification.request.content.body, privacy: .public)")
        logger.debug("userInfo: \(notification.request.content.userInfo, privacy: .public)")
        
        // Add haptic feedback for notifications
        let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
        impactFeedback.impactOccurred()
        
        return [.banner, .sound, .badge]
    }
    
    // Handle notification tap when app is in background
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse) async {
        logger.debug("Bruger tappede notifikation: \(response.notification.request.content.title, privacy: .public)")
        
        // Handle the notification tap here
        let userInfo = response.notification.request.content.userInfo
        logger.debug("userInfo: \(userInfo, privacy: .public)")
        
        // Check if this is a new article notification
        if let type = userInfo["type"] as? String, type == "new_article",
           let articleId = userInfo["article_id"] as? String, !articleId.isEmpty {
            
            logger.info("Åbner artikel fra push: \(articleId, privacy: .public)")
            
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
        logger.debug("App entered background.")
    }
    
    func applicationWillEnterForeground(_ application: UIApplication) {
        logger.debug("App will enter foreground.")
    }
    
    func applicationDidBecomeActive(_ application: UIApplication) {
        logger.debug("App blev aktiv.")
    }
    
    func applicationWillResignActive(_ application: UIApplication) {
        logger.debug("App vil blive inaktiv.")
    }
    
    func applicationWillTerminate(_ application: UIApplication) {
        logger.debug("App terminerer.")
    }
    
    // MARK: - Additional UIApplicationDelegate Methods for Full Conformance
    
    func application(_ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession, options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        logger.debug("Konfigurerer ny scene session.")
        return UISceneConfiguration(name: "Default Configuration", sessionRole: connectingSceneSession.role)
    }
    
    func application(_ application: UIApplication, didDiscardSceneSessions sceneSessions: Set<UISceneSession>) {
        logger.debug("Scene session kasseret.")
    }
    
    func application(_ application: UIApplication, performActionFor shortcutItem: UIApplicationShortcutItem, completionHandler: @escaping (Bool) -> Void) {
        logger.debug("Udfører genvejs-handling: \(shortcutItem.type, privacy: .public)")
        completionHandler(true)
    }
    
    func application(_ application: UIApplication, continue userActivity: NSUserActivity, restorationHandler: @escaping ([UIUserActivityRestoring]?) -> Void) -> Bool {
        logger.debug("Fortsætter user activity: \(userActivity.activityType, privacy: .public)")
        return true
    }
    
    func application(_ application: UIApplication, didUpdate userActivity: NSUserActivity) {
        logger.debug("Opdaterede user activity: \(userActivity.activityType, privacy: .public)")
    }
    
    func application(_ application: UIApplication, didFailToContinueUserActivityWithType userActivityType: String, error: Error) {
        logger.error("Fejl ved fortsættelse af user activity \(userActivityType, privacy: .public): \(error.localizedDescription, privacy: .public)")
    }
    
    func application(_ application: UIApplication, performFetchWithCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
        logger.debug("Baggrundsfetch udført.")
        completionHandler(.newData)
    }
    
    func application(_ application: UIApplication, handleEventsForBackgroundURLSession identifier: String, completionHandler: @escaping () -> Void) {
        logger.debug("Håndterer baggrunds-URL-session: \(identifier, privacy: .public)")
        completionHandler()
    }
}
