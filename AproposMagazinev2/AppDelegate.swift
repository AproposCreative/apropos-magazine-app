import FirebaseCore
import FirebaseMessaging
import UserNotifications
import GoogleSignIn
import UIKit
import OSLog
import SwiftUI
import SDWebImage

@objc final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate, MessagingDelegate {
    
    private let logger = Logger(subsystem: "com.aproposmagazine.app", category: "AppDelegate")
    
    // MARK: - UIApplicationDelegate Methods

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {

        FirebaseConfiguration.shared.setLoggerLevel(.min)
        FirebaseApp.configure()
        // Must be configured before any Firestore usage in the process.
        FirestoreService.shared.configurePersistenceIfNeeded()
        FeatureFlags.registerDefaults()
        configureGlobalImageCaching()
        application.beginReceivingRemoteControlEvents()
        AppDiagnostics.breadcrumb("app_launch")

        // Set up notification delegate
        UNUserNotificationCenter.current().delegate = self

        // Configure Google Sign-In
        GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: "817066738308-q8pdk1q5b9t9ugopjh67i2n2lau9k3sm.apps.googleusercontent.com")

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            SmartNotificationService.shared.setupNotificationCategories()
            Messaging.messaging().isAutoInitEnabled = true
            Messaging.messaging().delegate = self
        }

        // Register only if the user has already granted permission. The prompt is shown from Settings.
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
            UNUserNotificationCenter.current().getNotificationSettings { settings in
                let authorized = settings.authorizationStatus == .authorized
                    || settings.authorizationStatus == .provisional
                guard authorized else { return }
                
                DispatchQueue.main.async {
                    application.registerForRemoteNotifications()
                    Task { @MainActor in
                        await NotificationService.shared.bootstrapPushNotifications()
                    }
                }
            }
        }

        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-TriggerTestNotification") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 4.0) {
                Task { @MainActor in
                    await NotificationService.shared.sendTestLocalNotificationAfterAuthorization(delay: 2)
                }
            }
        }
        #endif

        return true
    }

    private func configureGlobalImageCaching() {
        let cacheConfig = SDImageCache.shared.config
        cacheConfig.maxMemoryCost = 60 * 1024 * 1024
        cacheConfig.maxDiskSize = 350 * 1024 * 1024
        cacheConfig.maxDiskAge = 30 * 24 * 60 * 60
        cacheConfig.shouldUseWeakMemoryCache = true

        let downloaderConfig = SDWebImageDownloader.shared.config
        downloaderConfig.maxConcurrentDownloads = 4
        downloaderConfig.executionOrder = .lifoExecutionOrder
        downloaderConfig.downloadTimeout = 15
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
                    NotificationService.shared.syncPersistedArticleNotificationSubscriptions()
                    
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
                NotificationService.shared.syncPersistedArticleNotificationSubscriptions()
                
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
            }
            
        case "VIEW_RECOMMENDATIONS":
            // "Se anbefalinger" action - navigate to recommendations
            await MainActor.run {
                NotificationCenter.default.post(
                    name: NSNotification.Name("NavigateToRecommendations"),
                    object: nil
                )
            }
            
        case "VIEW_FESTIVAL_GUIDE":
            // "Se guide" action - navigate to festival guide
            if let festivalId = userInfo["festival_id"] as? String {
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
            }
            
        default:
            // Other actions or dismissed
            break
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
        AppDiagnostics.breadcrumb("app_background")
    }
    
    func applicationWillEnterForeground(_ application: UIApplication) {
        AppDiagnostics.breadcrumb("app_foreground")
        Task { @MainActor in
            await NotificationService.shared.bootstrapPushNotifications()
            await PodcastRepository.shared.refreshManifest()
        }
    }
    
    func applicationDidBecomeActive(_ application: UIApplication) {
    }
    
    func applicationWillResignActive(_ application: UIApplication) {
    }
    
    func applicationWillTerminate(_ application: UIApplication) {
    }
    
    // MARK: - Additional UIApplicationDelegate Methods for Full Conformance
    
    func application(_ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession, options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        return UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
    }
    
    func application(_ application: UIApplication, didDiscardSceneSessions sceneSessions: Set<UISceneSession>) {
    }
    
    func application(_ application: UIApplication, performActionFor shortcutItem: UIApplicationShortcutItem, completionHandler: @escaping (Bool) -> Void) {
        completionHandler(true)
    }
    
    func application(_ application: UIApplication, continue userActivity: NSUserActivity, restorationHandler: @escaping ([UIUserActivityRestoring]?) -> Void) -> Bool {
        return true
    }
    
    func application(_ application: UIApplication, didUpdate userActivity: NSUserActivity) {
    }
    
    func application(_ application: UIApplication, didFailToContinueUserActivityWithType userActivityType: String, error: Error) {
        logger.error("Fejl ved fortsættelse af user activity \(userActivityType, privacy: .public): \(error.localizedDescription, privacy: .public)")
    }
    
    func application(_ application: UIApplication, performFetchWithCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
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
                    completionHandler(.newData)
                } else {
                    completionHandler(.noData)
                }
            case .failure(let error):
                self.logger.error("Background fetch fejlede: \(error.localizedDescription, privacy: .public)")
                completionHandler(.failed)
            }
        }
    }
    
    func application(_ application: UIApplication, handleEventsForBackgroundURLSession identifier: String, completionHandler: @escaping () -> Void) {
        completionHandler()
    }
}
