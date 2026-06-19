import FirebaseCore
import FirebaseMessaging
import UserNotifications
import GoogleSignIn
import UIKit
import OSLog
import SwiftUI
import SDWebImage
import WidgetKit

@objc final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate, MessagingDelegate {
    
    private let logger = Logger(subsystem: "com.aproposmagazine.app", category: "AppDelegate")
    
    // MARK: - UIApplicationDelegate Methods

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {

        FirebaseConfiguration.shared.setLoggerLevel(.min)
        FirebaseApp.configure()
        AnalyticsService.shared.configure()
        // Must be configured before any Firestore usage in the process.
        FirestoreService.shared.configurePersistenceIfNeeded()
        FeatureFlags.registerDefaults()
        configureGlobalImageCaching()
        application.beginReceivingRemoteControlEvents()
        AppDiagnostics.breadcrumb("app_launch")
        Task { @MainActor in
            PodcastLiveActivityService.shared.dismissUnsupportedActivitiesIfNeeded()
            SubscriptionManager.shared.start()
        }

        // Set up notification delegate
        UNUserNotificationCenter.current().delegate = self

        // Configure Google Sign-In from Firebase / GoogleService-Info.plist
        if let clientID = FirebaseApp.app()?.options.clientID {
            GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: clientID)
        } else {
            logger.error("Google Sign-In: CLIENT_ID mangler i Firebase-konfiguration")
        }

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

        if let remoteNotification = launchOptions?[.remoteNotification] as? [AnyHashable: Any],
           let payload = NotificationNavigation.payload(from: remoteNotification) {
            UserDefaults.standard.set(true, forKey: NotificationNavigation.skipBootloaderKey)
            Task { @MainActor in
                NavigationCoordinator.shared.scheduleNotificationNavigation(payload)
            }
        }

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
                AppDiagnostics.recordError(error, context: "fcm_token")
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
        AppDiagnostics.recordError(error, context: "apns_register")
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
        if notification.request.trigger is UNPushNotificationTrigger == false {
            NotificationDeliveryPolicy.recordLocalNotificationDelivered()
        }
        let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
        impactFeedback.impactOccurred()
        return [.banner, .sound, .badge]
    }
    
    // Handle notification tap when app is in background
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse) async {
        let actionIdentifier = response.actionIdentifier
        let userInfo = response.notification.request.content.userInfo
        let payload = NotificationNavigation.payload(from: userInfo)

        if let payload {
            let notificationType = payload.type
            AnalyticsService.shared.trackNotificationOpen(articleId: payload.articleIdentifier, type: notificationType)
        } else if let articleId = legacyNotificationArticleId(from: userInfo) {
            AnalyticsService.shared.trackNotificationOpen(articleId: articleId, type: legacyNotificationType(from: userInfo))
        }
        
        switch actionIdentifier {
        case "READ_ACTION", "READ_BREAKING_NEWS":
            await openArticleFromNotification(userInfo: userInfo, payload: payload)
            
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
            if let name = legacyNotificationArticleName(from: userInfo), payload == nil {
                await AppReadiness.waitUntilUIReady()
                await MainActor.run {
                    NotificationCenter.default.post(
                        name: NSNotification.Name("OpenArticleFromNotification"),
                        object: nil,
                        userInfo: ["articleName": name]
                    )
                }
                return
            }

            await openArticleFromNotification(userInfo: userInfo, payload: payload)
            
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
            Task { @MainActor in
                NavigationCoordinator.shared.handleDeepLink(url)
            }
            return true
        }
        
        return false
    }
    
    // MARK: - Application Lifecycle
    func applicationDidEnterBackground(_ application: UIApplication) {
        AppDiagnostics.breadcrumb("app_background")
        Task { @MainActor in
            PodcastPlayerManager.shared.persistPlaybackProgress(force: true)
        }
    }
    
    func applicationWillEnterForeground(_ application: UIApplication) {
        AppDiagnostics.breadcrumb("app_foreground")
        Task { @MainActor in
            let categoryIds = NotificationService.shared.loadPersistedAllCategoryIds()
            await NotificationService.shared.bootstrapPushNotifications(allCategoryIds: categoryIds)
            await PodcastRepository.shared.refreshManifest()
            syncWidgetFeedIfNeeded()
        }
    }

    func applicationDidBecomeActive(_ application: UIApplication) {
        Task { @MainActor in
            syncWidgetFeedIfNeeded()
            WidgetCenter.shared.reloadAllTimelines()
        }
    }

    @MainActor
    private func syncWidgetFeedIfNeeded() {
        if let cached = CacheManager.shared.getCachedArticles(), !cached.isEmpty {
            CacheManager.shared.syncWidgetFeed(from: cached)
        }
    }
    
    func applicationWillResignActive(_ application: UIApplication) {
    }
    
    func applicationWillTerminate(_ application: UIApplication) {
    }

    private func legacyNotificationArticleId(from userInfo: [AnyHashable: Any]) -> String? {
        NotificationNavigation.payload(from: userInfo)?.articleIdentifier
    }

    private func legacyNotificationType(from userInfo: [AnyHashable: Any]) -> String {
        NotificationNavigation.payload(from: userInfo)?.type ?? "general"
    }

    private func legacyNotificationArticleName(from userInfo: [AnyHashable: Any]) -> String? {
        let normalized = NotificationNavigation.normalize(userInfo)
        if let name = normalized["article_name"] as? String, !name.isEmpty {
            return name
        }
        return nil
    }

    private func openArticleFromNotification(
        userInfo: [AnyHashable: Any],
        payload: NotificationNavigation.Payload?
    ) async {
        guard let payload else { return }

        if payload.isPodcastNotification {
            await PodcastRepository.shared.refreshManifest(force: true)
        }

        await MainActor.run {
            NavigationCoordinator.shared.scheduleNotificationNavigation(payload)
        }
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
                AppDiagnostics.recordError(error, context: "background_fetch")
                completionHandler(.failed)
            }
        }
    }
    
    func application(_ application: UIApplication, handleEventsForBackgroundURLSession identifier: String, completionHandler: @escaping () -> Void) {
        completionHandler()
    }
}
