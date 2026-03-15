import FirebaseCore
import FirebaseMessaging
import UserNotifications
import GoogleSignIn
import UIKit
import OSLog
import SwiftUI

@objc final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate, MessagingDelegate {
    
    private let logger = Logger(subsystem: "dk.gobio.app", category: "AppDelegate")
    
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        
        if FirebaseApp.app() == nil {
            FirebaseApp.configure()
        }
        
        FirestoreService.shared.configurePersistenceIfNeeded()
        
        UNUserNotificationCenter.current().delegate = self
        
        NotificationService.shared.setupNotificationCategories()
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
            UNUserNotificationCenter.current().getNotificationSettings { settings in
                if settings.authorizationStatus == .notDetermined {
                    UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound, .provisional]) { granted, error in
                        DispatchQueue.main.async {
                            if granted {
                                application.registerForRemoteNotifications()
                            } else if let error {
                                self.logger.error("Notifikationstilladelse afvist: \(error.localizedDescription, privacy: .public)")
                            }
                        }
                    }
                } else if settings.authorizationStatus == .authorized {
                    DispatchQueue.main.async {
                        application.registerForRemoteNotifications()
                    }
                }
            }
        }
        
        Messaging.messaging().delegate = self
        
        if let clientID = FirebaseApp.app()?.options.clientID {
            GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: clientID)
        }
        
        return true
    }
    
    func application(_ application: UIApplication,
                     didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        Messaging.messaging().apnsToken = deviceToken
        
        Messaging.messaging().token { token, error in
            if let error = error {
                self.logger.error("Fejl ved hentning af FCM token: \(error.localizedDescription, privacy: .public)")
            } else if let token = token {
                UserDefaults.standard.set(token, forKey: "FCMRegistrationToken")
                
                DispatchQueue.main.async {
                    NotificationService.shared.fcmToken = token
                    
                    if UserManager.shared.currentUser != nil {
                        NotificationService.shared.updateFCMTokenOnServer(token)
                    }
                }
            }
        }
    }
    
    func application(_ application: UIApplication,
                     didFailToRegisterForRemoteNotificationsWithError error: Error) {
        logger.error("Fejl ved registrering af fjernnotifikationer: \(error.localizedDescription, privacy: .public)")
    }
    
    func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        if let token = fcmToken {
            UserDefaults.standard.set(token, forKey: "FCMRegistrationToken")
            
            DispatchQueue.main.async {
                NotificationService.shared.fcmToken = token
                
                if UserManager.shared.currentUser != nil {
                    NotificationService.shared.updateFCMTokenOnServer(token)
                }
            }
        }
    }
    
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
        impactFeedback.impactOccurred()
        
        return [.banner, .sound, .badge]
    }
    
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse) async {
        let userInfo = response.notification.request.content.userInfo
        
        if let movieIdString = userInfo["movie_id"] as? String,
           let movieId = Int(movieIdString) {
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            
            await MainActor.run {
                NotificationCenter.default.post(
                    name: NSNotification.Name("OpenMovieFromNotification"),
                    object: nil,
                    userInfo: ["movieId": movieId]
                )
            }
        }
    }
    
    func application(_ app: UIApplication, open url: URL, options: [UIApplication.OpenURLOptionsKey : Any] = [:]) -> Bool {
        if GIDSignIn.sharedInstance.handle(url) {
            return true
        }
        
        if url.scheme == "gobio" || url.host == "gobio.dk" {
            DispatchQueue.main.async {
                NotificationCenter.default.post(
                    name: NSNotification.Name("HandleDeepLink"),
                    object: nil,
                    userInfo: ["url": url]
                )
            }
            return true
        }
        
        return false
    }
    
    func application(_ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession, options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        return UISceneConfiguration(name: "Default Configuration", sessionRole: connectingSceneSession.role)
    }
    
    func application(_ application: UIApplication, continue userActivity: NSUserActivity, restorationHandler: @escaping ([UIUserActivityRestoring]?) -> Void) -> Bool {
        return true
    }
}
