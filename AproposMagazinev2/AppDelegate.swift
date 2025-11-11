import FirebaseCore
import FirebaseMessaging
import UserNotifications
import GoogleSignIn
import UIKit
import OSLog
import SwiftUI
import AVFoundation

@objc final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate, MessagingDelegate {
    
    private let logger = Logger(subsystem: "com.aproposmagazine.app", category: "AppDelegate")
    
    // MARK: - UIApplicationDelegate Methods

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {

        // Configure audio session to mix with other audio (don't stop music)
        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.ambient, mode: .default, options: [.mixWithOthers])
            try audioSession.setActive(true)
        } catch {
            logger.error("Kunne ikke konfigurere audio session: \(error.localizedDescription, privacy: .public)")
        }
        
        // Ensure Firebase is configured
        if FirebaseApp.app() == nil {
            FirebaseApp.configure()
        }
        
        // Configure Firestore persistence BEFORE any Firestore operations
        // This must be done before any Firestore instance is used
        FirestoreService.shared.configurePersistenceIfNeeded()
        
        // Set up notification delegate
        UNUserNotificationCenter.current().delegate = self
        
        // Setup notification categories (including NEW_ARTICLE for rich notifications)
        SmartNotificationService.shared.setupNotificationCategories()
        
        // Request notification permissions with a longer delay to ensure app is fully loaded
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
            // First check current authorization status
            UNUserNotificationCenter.current().getNotificationSettings { settings in
                // Only request if not already authorized
                if settings.authorizationStatus == .notDetermined {
                    UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound, .provisional]) { granted, error in
                        DispatchQueue.main.async {
                            if granted {
                                application.registerForRemoteNotifications()
                            } else {
                                if let error {
                                    self.logger.error("Notifikationstilladelse afvist: \(error.localizedDescription, privacy: .public)")
                                }
                            }
                        }
                    }
                } else if settings.authorizationStatus == .authorized {
                    DispatchQueue.main.async {
                        application.registerForRemoteNotifications()
                    }
                } else if settings.authorizationStatus == .denied {
                    // Don't try to register for remote notifications if denied
                }
            }
        }

        // Set up FCM delegate
        Messaging.messaging().delegate = self
        
        // Configure Google Sign-In
        GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: "817066738308-q8pdk1q5b9t9ugopjh67i2n2lau9k3sm.apps.googleusercontent.com")

        return true
    }

    // APNs token -> FCM
    func application(_ application: UIApplication,
                     didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        Messaging.messaging().apnsToken = deviceToken
        
        // Now that we have APNS token, we can safely get FCM token
        Messaging.messaging().token { token, error in
            if let error = error {
                self.logger.error("Fejl ved hentning af FCM token: \(error.localizedDescription, privacy: .public)")
            } else if let token = token {
                UserDefaults.standard.set(token, forKey: "FCMRegistrationToken")
                
                // Update the NotificationService
                DispatchQueue.main.async {
                    NotificationService.shared.fcmToken = token
                    
                    // Update token on server if user is logged in
                    if UserManager.shared.currentUser != nil {
                        NotificationService.shared.updateFCMTokenOnServer(token)
                    }
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
            // Save token in UserDefaults
            UserDefaults.standard.set(token, forKey: "FCMRegistrationToken")
            
            // Update NotificationService
            DispatchQueue.main.async {
                NotificationService.shared.fcmToken = token
                
                // Update token on server if user is logged in
                if UserManager.shared.currentUser != nil {
                    NotificationService.shared.updateFCMTokenOnServer(token)
                }
            }
        }
    }

    // Handle notification when app is in foreground
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        logger.debug("Notifikation i forgrund: \(notification.request.content.title, privacy: .public)")
        logger.debug("Indhold: \(notification.request.content.body, privacy: .public)")
        logger.debug("userInfo: \(notification.request.content.userInfo, privacy: .public)")
        
        // Check if this is a duplicate notification for an already published article
        let userInfo = notification.request.content.userInfo
        
        // Try to get article_id from userInfo
        var articleId: String?
        if let id = userInfo["article_id"] as? String, !id.isEmpty {
            articleId = id
        } else if let slug = userInfo["article_slug"] as? String, !slug.isEmpty {
            articleId = slug
        }
        
        // If we have an article_id, check if article is already published
        if let articleId = articleId {
            if await isArticleAlreadyPublished(articleId: articleId) {
                logger.info("Ignorerer notifikation - artikel \(articleId, privacy: .public) er allerede udgivet")
                return [] // Don't show notification
            }
        }
        
        // Add haptic feedback for notifications
        let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
        impactFeedback.impactOccurred()
        
        return [.banner, .sound, .badge]
    }
    
    /// Check if an article is already published
    /// CRITICAL: If article exists in cache, it was already published before (republish)
    /// Cache only contains articles fetched from Webflow API, so if it's in cache, it's already been published
    private func isArticleAlreadyPublished(articleId: String) async -> Bool {
        // Try to get cached articles first (fast)
        if let cachedArticles = CacheManager.shared.getCachedArticles() {
            if cachedArticles.contains(where: { $0.id == articleId }) {
                // Article exists in cache - it was already published before, this is a republish
                return true
            }
        }
        
        // If not found in cache, assume it's a new article (show notification)
        return false
    }
    
    // Handle notification tap when app is in background
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse) async {
        // Handle notification actions
        let actionIdentifier = response.actionIdentifier
        let userInfo = response.notification.request.content.userInfo
        
        // Check if this is a notification action (not just a tap)
        switch actionIdentifier {
        case "READ_ACTION", "READ_BREAKING_NEWS":
            // "Læs nu" action - open article
            var articleId: String?
            
            // Try article_id first
            if let id = userInfo["article_id"] as? String, !id.isEmpty {
                articleId = id
            }
            // Fallback to article_slug if article_id is empty
            else if let slug = userInfo["article_slug"] as? String, !slug.isEmpty {
                articleId = slug
            }
            
            if let articleId = articleId {
                // Longer delay to ensure app is fully active and views are ready
                try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
                
                await MainActor.run {
                    NotificationCenter.default.post(
                        name: NSNotification.Name("OpenArticleFromNotification"),
                        object: nil,
                        userInfo: ["articleId": articleId]
                    )
                }
            } else {
                logger.warning("Action notifikation mangler article_id eller article_slug i userInfo. userInfo: \(userInfo, privacy: .public)")
            }
            
        case "VIEW_RECOMMENDATIONS":
            // "Se anbefalinger" action - navigate to recommendations
            logger.info("Åbner anbefalinger fra action")
            await MainActor.run {
                NotificationCenter.default.post(
                    name: NSNotification.Name("NavigateToRecommendations"),
                    object: nil
                )
            }
            
        case "VIEW_FESTIVAL_GUIDE":
            // "Se guide" action - navigate to festival guide
            if let festivalId = userInfo["festival_id"] as? String {
                logger.info("Åbner festival guide fra action: \(festivalId, privacy: .public)")
                await MainActor.run {
                    NotificationCenter.default.post(
                        name: NSNotification.Name("NavigateToFestivalGuide"),
                        object: nil,
                        userInfo: ["festivalId": festivalId]
                    )
                }
            }
            
        case UNNotificationDefaultActionIdentifier:
            // Default action - user tapped on notification itself
            // Check if this is an article notification (any type with article_id or article_slug)
            var articleId: String?
            
            // Try article_id first
            if let id = userInfo["article_id"] as? String, !id.isEmpty {
                articleId = id
            }
            // Fallback to article_slug if article_id is empty
            else if let slug = userInfo["article_slug"] as? String, !slug.isEmpty {
                articleId = slug
            }
            // Try article_name as last resort - we'll search by name
            else if let name = userInfo["article_name"] as? String, !name.isEmpty {
                // Longer delay to ensure app is fully active and views are ready
                try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
                
                await MainActor.run {
                    NotificationCenter.default.post(
                        name: NSNotification.Name("OpenArticleFromNotification"),
                        object: nil,
                        userInfo: ["articleName": name]
                    )
                }
                return
            }
            
            if let articleId = articleId {
                // Longer delay to ensure app is fully active and views are ready
                try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
                
                await MainActor.run {
                    NotificationCenter.default.post(
                        name: NSNotification.Name("OpenArticleFromNotification"),
                        object: nil,
                        userInfo: ["articleId": articleId]
                    )
                }
            } else {
                logger.warning("Notifikation mangler article_id, article_slug og article_name i userInfo. userInfo: \(userInfo, privacy: .public)")
            }
            
        default:
            // Other actions or dismissed
            logger.debug("Notifikation håndteret med action: \(actionIdentifier, privacy: .public)")
        }
    }
    
    // Handle Google Sign-In URL and Deep Links
    func application(_ app: UIApplication, open url: URL, options: [UIApplication.OpenURLOptionsKey : Any] = [:]) -> Bool {
        // Handle Google Sign-In URLs
        if GIDSignIn.sharedInstance.handle(url) {
            return true
        }
        
        // Handle deep links (aproposmagazine://)
        if url.scheme == "aproposmagazine" || url.host == "aproposmagazine.com" {
            logger.info("Deep link modtaget: \(url.absoluteString, privacy: .public)")
            
            // Post notification to handle deep link
            // NavigationCoordinator will pick this up in ContentView
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
        logger.debug("Background fetch startet")
        
        // Refresh articles in background
        WebflowService.shared.fetchArticles { [weak self] result in
            guard let self = self else {
                completionHandler(.failed)
                return
            }
            
            switch result {
            case .success(let articles):
                if !articles.isEmpty {
                    // Cache the articles
                    CacheManager.shared.cacheArticles(articles)
                    self.logger.debug("Background fetch: Opdateret \(articles.count) artikler")
                    completionHandler(.newData)
                } else {
                    self.logger.debug("Background fetch: Ingen nye artikler")
                    completionHandler(.noData)
                }
            case .failure(let error):
                self.logger.error("Background fetch fejlede: \(error.localizedDescription, privacy: .public)")
                completionHandler(.failed)
            }
        }
    }
    
    func application(_ application: UIApplication, handleEventsForBackgroundURLSession identifier: String, completionHandler: @escaping () -> Void) {
        logger.debug("Håndterer baggrunds-URL-session: \(identifier, privacy: .public)")
        completionHandler()
    }
}
