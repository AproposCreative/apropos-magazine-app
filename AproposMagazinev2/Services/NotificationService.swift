import FirebaseFirestore
import FirebaseMessaging
import OSLog
import SwiftUI
import UserNotifications

@MainActor
class NotificationService: NSObject, ObservableObject {
    @Published var isAuthorized = false
    @Published var fcmToken: String?
    
    static let shared = NotificationService()
    
    private let logger = Logger(subsystem: "com.aproposmagazine.app", category: "NotificationService")
    
    private override init() {
        super.init()
        checkAuthorizationStatus()
        
        if let existingToken = UserDefaults.standard.string(forKey: "FCMRegistrationToken") {
            fcmToken = existingToken
            logger.debug("Genbruger eksisterende FCM token.")
        }
    }
    
    // MARK: - Authorization
    
    func requestAuthorization() async {
        do {
            let granted = try await UNUserNotificationCenter.current().requestAuthorization(
                options: [.alert, .badge, .sound, .provisional]
            )
            
            await MainActor.run {
                self.isAuthorized = granted
            }
            
            guard granted else {
                logger.warning("Bruger afviste push-notifikationer.")
                return
            }
            
            await registerForRemoteNotifications()
            logger.info("Push-notifikationer er autoriseret.")
        } catch {
            logger.error("Kunne ikke anmode om push-tilladelse: \(error.localizedDescription, privacy: .public)")
        }
    }
    
    private func checkAuthorizationStatus() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            DispatchQueue.main.async {
                self.isAuthorized = settings.authorizationStatus == .authorized
                self.logger.debug("Notifikationsstatus opdateret til \(settings.authorizationStatus.rawValue, privacy: .public)")
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
            logger.warning("Forsøgte at opdatere FCM token uden værdi.")
            return
        }
        
        logger.debug("Opdaterer FCM token mod backend.")
        
        if let user = UserManager.shared.currentUser, !user.uid.isEmpty {
            let db = Firestore.firestore()
            let validDate = Date()
            db.collection("users").document(user.uid).updateData([
                "fcmToken": token,
                "lastTokenUpdate": validDate
            ]) { error in
                if let error {
                    self.logger.error("Fejl ved opdatering af FCM token i Firestore: \(error.localizedDescription, privacy: .public)")
                } else {
                    self.logger.info("FCM token opdateret i Firestore.")
                }
            }
        }
        
        sendTokenToBackend(token)
    }
    
    private func sendTokenToBackend(_ token: String) {
        guard let url = SecureConfig.shared.fcmBackendURL else {
            logger.notice("Ingen FCM backend URL konfigureret. Spring HTTP-registrering over.")
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
        
        URLSession.shared.dataTask(with: request) { _, response, error in
            if let error {
                self.logger.error("Fejl ved afsendelse af FCM token til backend: \(error.localizedDescription, privacy: .public)")
                return
            }
            
            if let httpResponse = response as? HTTPURLResponse {
                self.logger.info("FCM backend svarede med status \(httpResponse.statusCode, privacy: .public).")
            }
        }.resume()
    }
    
    // MARK: - Topic Subscriptions
    
    func subscribeToTopics(for user: UserProfile) {
        Messaging.messaging().subscribe(toTopic: "all_users")
        
        for categoryId in user.favoriteCategories {
            Messaging.messaging().subscribe(toTopic: topicIdentifier(prefix: "category", rawValue: categoryId))
        }
        
        for authorId in user.favoriteAuthors {
            Messaging.messaging().subscribe(toTopic: topicIdentifier(prefix: "author", rawValue: authorId))
        }
    }
    
    func unsubscribeFromTopics(for user: UserProfile) {
        Messaging.messaging().unsubscribe(fromTopic: "all_users")
        
        for categoryId in user.favoriteCategories {
            Messaging.messaging().unsubscribe(fromTopic: topicIdentifier(prefix: "category", rawValue: categoryId))
        }
        
        for authorId in user.favoriteAuthors {
            Messaging.messaging().unsubscribe(fromTopic: topicIdentifier(prefix: "author", rawValue: authorId))
        }
    }
    
    // MARK: - Local Notifications
    
    func scheduleLocalNotification(title: String, body: String, timeInterval: TimeInterval) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        
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
        guard UserManager.shared.currentUser != nil else { return }
        
        toggleTopic(preferences.newArticles, topic: "new_articles")
        toggleTopic(preferences.festivalReminders, topic: "festival_reminders")
        toggleTopic(preferences.breakingNews, topic: "breaking_news")
        toggleTopic(preferences.weeklyDigest, topic: "weekly_digest")
    }
    
    private func toggleTopic(_ isEnabled: Bool, topic: String) {
        if isEnabled {
            Messaging.messaging().subscribe(toTopic: topic)
        } else {
            Messaging.messaging().unsubscribe(fromTopic: topic)
        }
    }
    
    // MARK: - Test Local Notification
    
    func sendTestLocalNotification() {
        let content = UNMutableNotificationContent()
        content.title = "Test Notification"
        content.body = "This is a test notification from Apropos Magazine"
        content.sound = .default
        content.badge = 1
        
        content.userInfo = [
            "type": "test",
            "article_id": "test_123"
        ]
        
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 2, repeats: false)
        let request = UNNotificationRequest(identifier: "test_notification", content: content, trigger: trigger)
        
        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                self.logger.error("Fejl ved afsendelse af testnotifikation: \(error.localizedDescription, privacy: .public)")
            } else {
                self.logger.info("Testnotifikation planlagt.")
            }
        }
    }
    
    // MARK: - Comprehensive Debug
    
    func debugNotificationSystem() {
        logger.info("=== Notifikationsdiagnostik start ===")
        logger.info("FCM token: \(self.fcmToken ?? "nil", privacy: .public)")
        logger.info("Autoriseret: \(self.isAuthorized)")
        
        if let user = UserManager.shared.currentUser {
            logger.info("Aktuel bruger: \(user.uid, privacy: .public)")
            logger.debug("Notifikationspræferencer: \(String(describing: user.notificationPreferences), privacy: .public)")
        } else {
            logger.info("Ingen bruger er logget ind.")
        }
        
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            self.logger.info("Notifikationsindstillinger: autorisation=\(settings.authorizationStatus.rawValue, privacy: .public)")
        }
        
        UNUserNotificationCenter.current().getPendingNotificationRequests { requests in
            self.logger.info("Planlagte notifikationer: \(requests.count)")
            for request in requests {
                self.logger.debug("Planlagt: \(request.identifier, privacy: .public) – \(request.content.title, privacy: .public)")
            }
        }
        
        UNUserNotificationCenter.current().getDeliveredNotifications { notifications in
            self.logger.info("Leverede notifikationer: \(notifications.count)")
            for notification in notifications {
                self.logger.debug("Leveret: \(notification.request.identifier, privacy: .public) – \(notification.request.content.title, privacy: .public)")
            }
        }
        
        if UserManager.shared.currentUser != nil {
            Messaging.messaging().subscribe(toTopic: "new_articles") { error in
                if let error {
                    self.logger.error("Fejl ved abonnement på 'new_articles': \(error.localizedDescription, privacy: .public)")
                } else {
                    self.logger.info("Abonnerede på 'new_articles'.")
                }
            }
            
            Messaging.messaging().subscribe(toTopic: "all_users") { error in
                if let error {
                    self.logger.error("Fejl ved abonnement på 'all_users': \(error.localizedDescription, privacy: .public)")
                } else {
                    self.logger.info("Abonnerede på 'all_users'.")
                }
            }
        }
        
        logger.info("=== Notifikationsdiagnostik slut ===")
    }
    
    func forceSubscribeToNewArticles() {
        logger.info("Tvinger abonnement på 'new_articles'.")
        Messaging.messaging().subscribe(toTopic: "new_articles") { error in
            if let error {
                self.logger.error("Fejl ved abonnement på 'new_articles': \(error.localizedDescription, privacy: .public)")
                return
            }
            
            self.logger.info("Abonnerede på 'new_articles'.")
            
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
