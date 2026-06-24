import FirebaseFirestore
import FirebaseMessaging
import OSLog
import SwiftUI
import UserNotifications

@MainActor
class NotificationService: NSObject, ObservableObject {
    @Published var isAuthorized = false
    @Published var authorizationStatusDescription = "Ukendt"
    @Published var fcmToken: String?
    @Published var lastPushSyncSummary = "Ikke synkroniseret endnu"
    @Published var subscribedTopicsDescription = "—"
    @Published var lastPushSyncedAt: Date?
    @Published var isResyncingPush = false
    @Published var remotePushTestResult: String?
    
    static let shared = NotificationService()
    
    private let logger = Logger(subsystem: "com.aproposmagazine.app", category: "NotificationService")
    
    private override init() {
        super.init()
        refreshAuthorizationStatus()
        
        if let existingToken = UserDefaults.standard.string(forKey: "FCMRegistrationToken") {
            fcmToken = existingToken
        }
    }
    
    // MARK: - Authorization
    
    func refreshAuthorizationStatus() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            DispatchQueue.main.async {
                self.isAuthorized = settings.authorizationStatus == .authorized
                    || settings.authorizationStatus == .provisional
                self.authorizationStatusDescription = Self.describe(settings.authorizationStatus)
            }
        }
    }
    
    func requestAuthorization() async -> Bool {
        do {
            let granted = try await UNUserNotificationCenter.current().requestAuthorization(
                options: [.alert, .badge, .sound]
            )
            
            refreshAuthorizationStatus()
            
            guard granted else {
                lastPushSyncSummary = "Notifikationer er slået fra i iOS-indstillinger."
                return false
            }
            
            await registerForRemoteNotifications()
            return true
        } catch {
            logger.error("Kunne ikke anmode om push-tilladelse: \(error.localizedDescription, privacy: .public)")
            lastPushSyncSummary = "Kunne ikke anmode om tilladelse."
            return false
        }
    }
    
    func activateArticlePushNotifications(
        preferences: NotificationPreferences,
        selectedCategoryIds: [String],
        allCategoryIds: [String]
    ) async {
        persistArticleNotificationSettings(
            preferences: preferences,
            selectedCategoryIds: selectedCategoryIds
        )
        
        let pushEnabled = pushNotificationsEnabled(
            preferences: preferences,
            selectedCategoryIds: selectedCategoryIds
        )
        guard pushEnabled else {
            updateArticleCategorySubscriptions(
                preferences: preferences,
                selectedCategoryIds: selectedCategoryIds,
                allCategoryIds: allCategoryIds
            )
            lastPushSyncSummary = "Notifikationer er slået fra."
            return
        }
        
        let authorized = isAuthorized ? true : await requestAuthorization()
        guard authorized else { return }
        
        await registerForRemoteNotifications()
        if fcmToken == nil {
            await refreshFCMToken()
        }

        updateArticleCategorySubscriptions(
            preferences: preferences,
            selectedCategoryIds: selectedCategoryIds,
            allCategoryIds: allCategoryIds
        )
        
        if fcmToken == nil {
            lastPushSyncSummary = "Push aktiveret. Afventer FCM-token — tryk Synkroniser push igen om et øjeblik."
        } else {
            updateFCMTokenOnServer(fcmToken)
        }
    }
    
    private static func describe(_ status: UNAuthorizationStatus) -> String {
        switch status {
        case .authorized: return "Tilladt"
        case .denied: return "Afslået"
        case .notDetermined: return "Ikke valgt endnu"
        case .provisional: return "Foreløbig tilladelse"
        case .ephemeral: return "Midlertidig tilladelse"
        @unknown default: return "Ukendt"
        }
    }
    
    // MARK: - First Launch Onboarding
    
    private static let onboardingCompletedKey = "notification_onboarding_completed_v1"
    
    func shouldPresentOnboarding() async -> Bool {
        guard !UserDefaults.standard.bool(forKey: Self.onboardingCompletedKey) else {
            return false
        }
        
        let settings = await currentNotificationSettings()
        return settings.authorizationStatus == .notDetermined
    }
    
    func markOnboardingCompleted() {
        UserDefaults.standard.set(true, forKey: Self.onboardingCompletedKey)
    }
    
    func completeOnboarding(allowNotifications: Bool, allCategoryIds: [String]) async {
        markOnboardingCompleted()
        
        var preferences = NotificationPreferences()
        preferences.newArticles = allowNotifications
        preferences.newPodcasts = allowNotifications
        
        await activateArticlePushNotifications(
            preferences: preferences,
            selectedCategoryIds: [],
            allCategoryIds: allCategoryIds
        )
    }
    
    private func currentNotificationSettings() async -> UNNotificationSettings {
        await withCheckedContinuation { continuation in
            UNUserNotificationCenter.current().getNotificationSettings { settings in
                continuation.resume(returning: settings)
            }
        }
    }
    
    private func registerForRemoteNotifications() async {
        await MainActor.run {
            UIApplication.shared.registerForRemoteNotifications()
        }
    }
    
    // MARK: - FCM Token Management
    
    func updateFCMTokenOnServer(_ token: String?) {
        guard let token else {
            return
        }
        
        if let user = UserManager.shared.currentUser, !user.uid.isEmpty {
            let db = Firestore.firestore()
            let validDate = Date()
            db.collection("users").document(user.uid).updateData([
                "fcmToken": token,
                "lastTokenUpdate": validDate
            ]) { error in
                if let error {
                    self.logger.error("Fejl ved opdatering af FCM token i Firestore: \(error.localizedDescription, privacy: .public)")
                }
            }
        }
        
        sendTokenToBackend(token)
    }
    
    private func sendTokenToBackend(_ token: String) {
        guard let url = SecureConfig.shared.fcmBackendURL else {
            return
        }
        
        var request = URLRequest(url: url)
        request.timeoutInterval = 30.0
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("AproposMagazine-iOS/1.0", forHTTPHeaderField: "User-Agent")
        
        let tokenData: [String: Any] = [
            "fcmToken": token,
            "userId": UserManager.shared.currentUser?.uid ?? "anonymous",
            "platform": "ios",
            "timestamp": Date().timeIntervalSince1970
        ]
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: tokenData)
        } catch {
            logger.error("Kunne ikke serialisere FCM token payload: \(error.localizedDescription, privacy: .public)")
            return
        }
        
        URLSession.shared.dataTask(with: request) { _, _, error in
            if let error {
                self.logger.error("Fejl ved afsendelse af FCM token til backend: \(error.localizedDescription, privacy: .public)")
                return
            }
        }.resume()
    }
    
    // MARK: - Topic Subscriptions
    
    private enum StorageKey {
        static let preferences = "article_notification_preferences_v1"
        static let categoryIds = "article_notification_category_ids_v1"
        static let allCategoryIds = "article_notification_all_category_ids_v1"
        static let podcastPreferenceMigrated = "notification_podcast_pref_migrated_v1"
    }

    func persistAllCategoryIds(_ ids: [String]) {
        UserDefaults.standard.set(ids, forKey: StorageKey.allCategoryIds)
    }

    func loadPersistedAllCategoryIds() -> [String] {
        UserDefaults.standard.stringArray(forKey: StorageKey.allCategoryIds) ?? []
    }

    func expectedActiveTopics(
        preferences: NotificationPreferences,
        selectedCategoryIds: [String]
    ) -> [String] {
        var topics: [String] = []
        if preferences.newPodcasts {
            topics.append("new_podcasts")
        }
        if articleNotificationsEnabled(preferences: preferences, selectedCategoryIds: selectedCategoryIds) {
            if preferences.newArticles && selectedCategoryIds.isEmpty {
                topics.append("new_articles")
            }
            for categoryId in selectedCategoryIds {
                topics.append(topicIdentifier(prefix: "category", rawValue: categoryId))
            }
        }
        if preferences.festivalReminders { topics.append("festival_reminders") }
        if preferences.breakingNews { topics.append("breaking_news") }
        if preferences.weeklyDigest { topics.append("weekly_digest") }
        return topics
    }

    func refreshPushDiagnostics(
        preferences: NotificationPreferences? = nil,
        selectedCategoryIds: [String]? = nil
    ) {
        let (resolvedPreferences, resolvedCategoryIds) = if let preferences, let selectedCategoryIds {
            (preferences, selectedCategoryIds)
        } else {
            loadPersistedArticleNotificationSettings()
        }

        let topics = expectedActiveTopics(
            preferences: resolvedPreferences,
            selectedCategoryIds: resolvedCategoryIds
        )
        subscribedTopicsDescription = topics.isEmpty ? "Ingen emner" : topics.joined(separator: ", ")
    }
    
    func articleNotificationsEnabled(
        preferences: NotificationPreferences,
        selectedCategoryIds: [String]
    ) -> Bool {
        if !selectedCategoryIds.isEmpty {
            return true
        }
        return preferences.newArticles
    }

    func pushNotificationsEnabled(
        preferences: NotificationPreferences,
        selectedCategoryIds: [String]
    ) -> Bool {
        articleNotificationsEnabled(
            preferences: preferences,
            selectedCategoryIds: selectedCategoryIds
        ) || preferences.newPodcasts
    }
    
    func persistArticleNotificationSettings(
        preferences: NotificationPreferences,
        selectedCategoryIds: [String]
    ) {
        if let data = try? JSONEncoder().encode(preferences) {
            UserDefaults.standard.set(data, forKey: StorageKey.preferences)
        }
        UserDefaults.standard.set(selectedCategoryIds, forKey: StorageKey.categoryIds)
    }
    
    func loadPersistedArticleNotificationSettings() -> (NotificationPreferences, [String]) {
        var preferences: NotificationPreferences
        if let data = UserDefaults.standard.data(forKey: StorageKey.preferences),
           let decoded = try? JSONDecoder().decode(NotificationPreferences.self, from: data) {
            preferences = decoded
        } else if let user = UserManager.shared.currentUser {
            preferences = user.notificationPreferences
        } else {
            preferences = NotificationPreferences()
        }
        
        let categoryIds = UserDefaults.standard.stringArray(forKey: StorageKey.categoryIds) ?? []

        if !UserDefaults.standard.bool(forKey: StorageKey.podcastPreferenceMigrated) {
            preferences.newPodcasts = articleNotificationsEnabled(
                preferences: preferences,
                selectedCategoryIds: categoryIds
            )
            UserDefaults.standard.set(true, forKey: StorageKey.podcastPreferenceMigrated)
            if let data = try? JSONEncoder().encode(preferences) {
                UserDefaults.standard.set(data, forKey: StorageKey.preferences)
            }
        }
        
        return (preferences, categoryIds)
    }
    
    func syncPersistedArticleNotificationSubscriptions(allCategoryIds: [String] = []) {
        refreshAuthorizationStatus()
        guard isAuthorized else {
            lastPushSyncSummary = "Push kræver tilladelse i iOS-indstillinger."
            refreshPushDiagnostics()
            return
        }

        let resolvedCategoryIds = allCategoryIds.isEmpty
            ? loadPersistedAllCategoryIds()
            : allCategoryIds
        if !allCategoryIds.isEmpty {
            persistAllCategoryIds(allCategoryIds)
        }
        
        let (preferences, categoryIds) = loadPersistedArticleNotificationSettings()
        updateArticleCategorySubscriptions(
            preferences: preferences,
            selectedCategoryIds: categoryIds,
            allCategoryIds: resolvedCategoryIds
        )
        toggleTopic(preferences.festivalReminders, topic: "festival_reminders")
        toggleTopic(preferences.breakingNews, topic: "breaking_news")
        toggleTopic(preferences.weeklyDigest, topic: "weekly_digest")
        lastPushSyncedAt = Date()
        refreshPushDiagnostics(preferences: preferences, selectedCategoryIds: categoryIds)
    }

    func resyncPushSubscriptions(allCategoryIds: [String] = []) async {
        isResyncingPush = true
        defer { isResyncingPush = false }

        refreshAuthorizationStatus()
        guard isAuthorized else {
            lastPushSyncSummary = "Slå notifikationer til under iOS-indstillinger → Apropos Magazine."
            refreshPushDiagnostics()
            return
        }

        if !allCategoryIds.isEmpty {
            persistAllCategoryIds(allCategoryIds)
        }

        await registerForRemoteNotifications()
        if fcmToken == nil {
            await refreshFCMToken()
        }

        syncPersistedArticleNotificationSubscriptions(allCategoryIds: allCategoryIds)

        if fcmToken == nil {
            lastPushSyncSummary = "Tilmelding sendt. Afventer FCM-token — prøv igen om et øjeblik."
        } else {
            updateFCMTokenOnServer(fcmToken)
        }
    }

    private func refreshFCMToken() async {
        await withCheckedContinuation { continuation in
            Messaging.messaging().token { token, error in
                Task { @MainActor in
                    if let error {
                        self.logger.error("Kunne ikke hente FCM-token: \(error.localizedDescription, privacy: .public)")
                    } else if let token {
                        self.fcmToken = token
                        UserDefaults.standard.set(token, forKey: "FCMRegistrationToken")
                    }
                    continuation.resume()
                }
            }
        }
    }
    
    func bootstrapPushNotifications(allCategoryIds: [String] = []) async {
        await resyncPushSubscriptions(allCategoryIds: allCategoryIds)

        if UserDefaults.standard.data(forKey: StorageKey.preferences) == nil,
           let user = UserManager.shared.currentUser {
            let (_, categoryIds) = loadPersistedArticleNotificationSettings()
            persistArticleNotificationSettings(
                preferences: user.notificationPreferences,
                selectedCategoryIds: categoryIds
            )
            syncPersistedArticleNotificationSubscriptions(allCategoryIds: allCategoryIds)
        }
    }
    
    func subscribeToTopics(for user: UserProfile) {
        let (_, categoryIds) = loadPersistedArticleNotificationSettings()
        persistArticleNotificationSettings(
            preferences: user.notificationPreferences,
            selectedCategoryIds: categoryIds
        )
        syncArticleTopicSubscriptions(
            preferences: user.notificationPreferences,
            selectedCategoryIds: categoryIds
        )
        toggleTopic(user.notificationPreferences.festivalReminders, topic: "festival_reminders")
        toggleTopic(user.notificationPreferences.breakingNews, topic: "breaking_news")
        toggleTopic(user.notificationPreferences.weeklyDigest, topic: "weekly_digest")
    }
    
    func unsubscribeFromTopics(for user: UserProfile) {
        Messaging.messaging().unsubscribe(fromTopic: "all_users")
        Messaging.messaging().unsubscribe(fromTopic: "new_articles")
        Messaging.messaging().unsubscribe(fromTopic: "new_podcasts")
        
        for categoryId in user.favoriteCategories {
            Messaging.messaging().unsubscribe(fromTopic: topicIdentifier(prefix: "category", rawValue: categoryId))
        }
        
        for authorId in user.favoriteAuthors {
            Messaging.messaging().unsubscribe(fromTopic: topicIdentifier(prefix: "author", rawValue: authorId))
        }
        
        toggleTopic(false, topic: "festival_reminders")
        toggleTopic(false, topic: "breaking_news")
        toggleTopic(false, topic: "weekly_digest")
    }
    
    func unsubscribeFromAllArticleTopics(allCategoryIds: [String] = []) {
        Messaging.messaging().unsubscribe(fromTopic: "all_users")
        Messaging.messaging().unsubscribe(fromTopic: "new_articles")
        
        for categoryId in allCategoryIds {
            Messaging.messaging().unsubscribe(fromTopic: topicIdentifier(prefix: "category", rawValue: categoryId))
        }
        
        if let storedCategoryIds = UserDefaults.standard.stringArray(forKey: StorageKey.categoryIds) {
            for categoryId in storedCategoryIds {
                Messaging.messaging().unsubscribe(fromTopic: topicIdentifier(prefix: "category", rawValue: categoryId))
            }
        }
    }
    
    // MARK: - Local Notifications
    
    func scheduleLocalNotification(title: String, body: String, timeInterval: TimeInterval, threadIdentifier: String? = nil) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        
        // Add thread identifier for grouping
        if let threadId = threadIdentifier {
            content.threadIdentifier = threadId
        }
        
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: timeInterval, repeats: false)
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: trigger)
        
        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                self.logger.error("Fejl ved planlægning af lokal notifikation: \(error.localizedDescription, privacy: .public)")
            }
        }
    }
    
    func scheduleFestivalReminder(festivalName: String, date: Date) {
        let content = UNMutableNotificationContent()
        content.title = "Festival Reminder"
        content.body = "\(festivalName) starter snart!"
        content.sound = .default
        
        let reminderDate = date.addingTimeInterval(-24 * 60 * 60)
        let trigger = UNCalendarNotificationTrigger(
            dateMatching: Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: reminderDate),
            repeats: false
        )
        
        let request = UNNotificationRequest(identifier: "festival_\(festivalName)", content: content, trigger: trigger)
        
        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                self.logger.error("Fejl ved planlægning af festivalpåmindelse: \(error.localizedDescription, privacy: .public)")
            }
        }
    }
    
    // MARK: - Notification Preferences
    
    func updateNotificationPreferences(_ preferences: NotificationPreferences) {
        let (_, categoryIds) = loadPersistedArticleNotificationSettings()
        syncArticleTopicSubscriptions(
            preferences: preferences,
            selectedCategoryIds: categoryIds
        )
        toggleTopic(preferences.festivalReminders, topic: "festival_reminders")
        toggleTopic(preferences.breakingNews, topic: "breaking_news")
        toggleTopic(preferences.weeklyDigest, topic: "weekly_digest")
    }

    func updateArticleCategorySubscriptions(
        preferences: NotificationPreferences,
        selectedCategoryIds: [String],
        allCategoryIds: [String]
    ) {
        syncArticleTopicSubscriptions(
            preferences: preferences,
            selectedCategoryIds: selectedCategoryIds,
            allCategoryIds: allCategoryIds
        )
    }
    
    private func toggleTopic(_ isEnabled: Bool, topic: String) {
        if isEnabled {
            Messaging.messaging().subscribe(toTopic: topic) { error in
                if let error {
                    self.logger.error("Fejl ved abonnement på \(topic, privacy: .public): \(error.localizedDescription, privacy: .public)")
                }
            }
        } else {
            Messaging.messaging().unsubscribe(fromTopic: topic) { error in
                if let error {
                    self.logger.error("Fejl ved afmelding af \(topic, privacy: .public): \(error.localizedDescription, privacy: .public)")
                }
            }
        }
    }

    private func subscribeToTopic(_ topic: String) {
        Messaging.messaging().subscribe(toTopic: topic) { error in
            if let error {
                self.logger.error("Fejl ved abonnement på \(topic, privacy: .public): \(error.localizedDescription, privacy: .public)")
                Task { @MainActor in
                    self.lastPushSyncSummary = "Kunne ikke tilmelde \(topic)."
                }
            } else {
                Task { @MainActor in
                    AppDiagnostics.breadcrumb("push_subscribed_\(topic)")
                }
            }
        }
    }

    private func unsubscribeFromTopic(_ topic: String) {
        Messaging.messaging().unsubscribe(fromTopic: topic) { error in
            if let error {
                self.logger.error("Fejl ved afmelding af \(topic, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    private func syncArticleTopicSubscriptions(
        preferences: NotificationPreferences,
        selectedCategoryIds: [String],
        allCategoryIds: [String] = []
    ) {
        let selectedCategoryTopics = Set(selectedCategoryIds.map {
            topicIdentifier(prefix: "category", rawValue: $0)
        })
        let articlesEnabled = articleNotificationsEnabled(
            preferences: preferences,
            selectedCategoryIds: selectedCategoryIds
        )
        let podcastsEnabled = preferences.newPodcasts

        if podcastsEnabled {
            subscribeToTopic("new_podcasts")
        } else {
            unsubscribeFromTopic("new_podcasts")
        }

        if articlesEnabled {
            if preferences.newArticles && selectedCategoryTopics.isEmpty {
                subscribeToTopic("new_articles")
            } else {
                unsubscribeFromTopic("new_articles")
            }

            for topic in selectedCategoryTopics {
                subscribeToTopic(topic)
            }

            for categoryId in allCategoryIds where !selectedCategoryIds.contains(categoryId) {
                unsubscribeFromTopic(topicIdentifier(prefix: "category", rawValue: categoryId))
            }
        } else {
            unsubscribeFromAllArticleTopics(allCategoryIds: allCategoryIds)
        }

        lastPushSyncSummary = pushSyncSummary(
            preferences: preferences,
            selectedCategoryIds: selectedCategoryIds
        )
        refreshPushDiagnostics(preferences: preferences, selectedCategoryIds: selectedCategoryIds)
    }

    private func pushSyncSummary(
        preferences: NotificationPreferences,
        selectedCategoryIds: [String]
    ) -> String {
        let topics = expectedActiveTopics(
            preferences: preferences,
            selectedCategoryIds: selectedCategoryIds
        )
        guard !topics.isEmpty else {
            return "Notifikationer er slået fra."
        }
        return "Tilmeldt: \(topics.joined(separator: ", "))"
    }
    
    // MARK: - Article Notifications (Rich Notifications Support)
    
    /// Send a notification about a new article with thumbnail support
    /// The thumbnail will be added by NotificationServiceExtension if available
    func sendArticleNotification(article: Article, title: String? = nil, body: String? = nil) {
        let content = UNMutableNotificationContent()
        content.title = title ?? "Ny artikel: \(article.name ?? "Ukendt")"
        content.body = body ?? article.intro ?? ""
        content.sound = .default
        content.categoryIdentifier = "NEW_ARTICLE"
        content.threadIdentifier = "new_articles" // Group all new article notifications
        
        // Add article data to userInfo for NotificationServiceExtension
        // The extension will download the thumbnail and add it as an attachment
        var userInfo: [String: Any] = [
            "type": "new_article",
            "article_id": article.id
        ]
        
        // Add mobile image URL first so rich notifications use the lightweight image when available.
        if let mobileImageURL = article.mobileImageURL {
            userInfo["thumbnail_url"] = mobileImageURL.absoluteString
        } else if let thumbnailURL = article.thumbURL {
            userInfo["thumbnail_url"] = thumbnailURL.absoluteString
        }
        
        // Add cover URL as fallback
        if let coverURL = article.coverURL {
            userInfo["cover_url"] = coverURL.absoluteString
        }
        
        content.userInfo = userInfo
        
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let request = UNNotificationRequest(
            identifier: "article_\(article.id)_\(UUID().uuidString)",
            content: content,
            trigger: trigger
        )
        
        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                self.logger.error("Fejl ved afsendelse af artikelnotifikation: \(error.localizedDescription, privacy: .public)")
            }
        }
    }
    
    // MARK: - Test Local Notification
    
    func sendTestLocalNotification(delay: TimeInterval = 2) {
        let content = UNMutableNotificationContent()
        content.title = "Apropos Magazine"
        content.body = "Lokal test — viser at iOS tillader notifikationer. Team-push er separat."
        content.sound = .default
        content.badge = 0
        content.threadIdentifier = "test_notifications"
        
        content.userInfo = [
            "type": "test",
            "article_id": "test_123"
        ]
        
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, delay), repeats: false)
        let request = UNNotificationRequest(
            identifier: "test_notification_\(UUID().uuidString)",
            content: content,
            trigger: trigger
        )
        
        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                self.logger.error("Fejl ved afsendelse af testnotifikation: \(error.localizedDescription, privacy: .public)")
            } else {
                self.logger.info("Testnotifikation planlagt om \(delay, privacy: .public)s")
            }
        }
    }
    
    func sendTestLocalNotificationAfterAuthorization(delay: TimeInterval = 2) async {
        let authorized = isAuthorized ? true : await requestAuthorization()
        guard authorized else { return }
        sendTestLocalNotification(delay: delay)
    }

    /// Sends a real FCM broadcast to `new_articles` (all subscribed devices). Requires PUSH_NOTIFY_SECRET in build.
    func sendRemoteArticlePushTest() async {
        remotePushTestResult = nil

        let (preferences, categoryIds) = loadPersistedArticleNotificationSettings()
        guard pushNotificationsEnabled(
            preferences: preferences,
            selectedCategoryIds: categoryIds
        ) else {
            remotePushTestResult = "Slå artikel- eller podcast-notifikationer til først."
            return
        }

        guard let secret = SecureConfig.shared.pushNotifySecret else {
            remotePushTestResult = "Fjern-test kræver PUSH_NOTIFY_SECRET i denne build."
            return
        }

        guard let url = SecureConfig.shared.pushTestArticleURL else {
            remotePushTestResult = "Test-endpoint mangler."
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(secret, forHTTPHeaderField: "X-Apropos-Podcast-Secret")
        request.httpBody = try? JSONSerialization.data(withJSONObject: [
            "title": "Test: Ny artikel på Apropos Magazine",
            "body": "Hvis du ser dette, modtager din enhed artikel-push korrekt.",
        ])

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            if (200...299).contains(status) {
                remotePushTestResult = "Test-push sendt til alle tilmeldte enheder (emne: new_articles)."
                AppDiagnostics.breadcrumb("push_remote_test_sent")
            } else {
                let body = String(data: data, encoding: .utf8) ?? ""
                remotePushTestResult = "Test-push fejlede (HTTP \(status)). \(body)"
            }
        } catch {
            remotePushTestResult = "Kunne ikke sende test-push: \(error.localizedDescription)"
        }
    }
    
    // MARK: - Comprehensive Debug
    
    func debugNotificationSystem() {
        if UserManager.shared.currentUser != nil {
            Messaging.messaging().subscribe(toTopic: "new_articles") { error in
                if let error {
                    self.logger.error("Fejl ved abonnement på 'new_articles': \(error.localizedDescription, privacy: .public)")
                }
            }
            
            Messaging.messaging().subscribe(toTopic: "all_users") { error in
                if let error {
                    self.logger.error("Fejl ved abonnement på 'all_users': \(error.localizedDescription, privacy: .public)")
                }
            }
        }
    }
    
    func forceSubscribeToNewArticles() {
        Messaging.messaging().subscribe(toTopic: "new_articles") { error in
            if let error {
                self.logger.error("Fejl ved abonnement på 'new_articles': \(error.localizedDescription, privacy: .public)")
                return
            }

            Task {
                let token = await MainActor.run { self.fcmToken }
                if let token {
                    await MainActor.run {
                        self.updateFCMTokenOnServer(token)
                    }
                }
            }
        }
    }
    
    // MARK: - Helpers
    
    private func topicIdentifier(prefix: String, rawValue: String) -> String {
        let sanitized = rawValue
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .joined()
        return "\(prefix)_\(sanitized)"
    }
}
