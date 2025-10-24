import SwiftUI
import UserNotifications
import FirebaseFirestore
import FirebaseMessaging

@MainActor
class NotificationService: NSObject, ObservableObject {
    @Published var isAuthorized = false
    @Published var fcmToken: String?
    
    static let shared = NotificationService()
    
    private override init() {
        super.init()
        checkAuthorizationStatus()
        // Don't set up messaging here - let AppDelegate handle it
        // Just get the existing token if available
        if let existingToken = UserDefaults.standard.string(forKey: "FCMRegistrationToken") {
            self.fcmToken = existingToken
            print("[NotificationService] Using existing FCM token: \(existingToken)")
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
            
            if granted {
                await registerForRemoteNotifications()
            }
        } catch {
            print("Failed to request notification authorization: \(error)")
        }
    }
    
    private func checkAuthorizationStatus() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            DispatchQueue.main.async {
                self.isAuthorized = settings.authorizationStatus == .authorized
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
        guard let token = token else { 
            print("[NotificationService] No FCM token provided")
            return 
        }
        
        print("[NotificationService] Updating FCM token: \(token)")
        
        // If user is logged in, update in Firestore
        if let user = UserManager.shared.currentUser, !user.uid.isEmpty {
            let db = Firestore.firestore()
            let validDate = Date()
            db.collection("users").document(user.uid).updateData([
                "fcmToken": token,
                "lastTokenUpdate": validDate
            ]) { error in
                if let error = error {
                    print("[NotificationService] Error updating FCM token in Firestore: \(error)")
                } else {
                    print("[NotificationService] FCM token updated successfully in Firestore")
                }
            }
        }
        
        // Also send to your backend API if you have one
        sendTokenToBackend(token)
    }
    
    private func sendTokenToBackend(_ token: String) {
        // Use your actual backend endpoint for FCM token registration
        // This should be your own server, not the Webflow webhook
        guard let url = URL(string: "https://your-backend-api.com/api/fcm-token") else {
            print("[NotificationService] Invalid backend URL - please configure your FCM token endpoint")
            return
        }
        
        // Add timeout and retry configuration
        var request = URLRequest(url: url)
        request.timeoutInterval = 30.0
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("AproposMagazine-iOS/1.0", forHTTPHeaderField: "User-Agent")
        
        let tokenData = [
            "fcmToken": token,
            "userId": UserManager.shared.currentUser?.uid ?? "anonymous",
            "platform": "ios",
            "timestamp": Date().timeIntervalSince1970
        ] as [String : Any]
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: tokenData)
        } catch {
            print("[NotificationService] Error serializing token data: \(error)")
            return
        }
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                print("[NotificationService] Error sending token to backend: \(error)")
            } else if let httpResponse = response as? HTTPURLResponse {
                print("[NotificationService] Backend response: \(httpResponse.statusCode)")
            }
        }.resume()
    }
    
    // MARK: - Topic Subscriptions
    
    func subscribeToTopics(for user: UserProfile) {
        // Subscribe to general topics
        Messaging.messaging().subscribe(toTopic: "all_users")
        
        // Subscribe to user-specific topics
        // Messaging.messaging().subscribe(toTopic: "user_\(user.uid)")
        
        // Subscribe to favorite categories
        for _ in user.favoriteCategories {
            // Messaging.messaging().subscribe(toTopic: "category_\(categoryId)")
        }
        
        // Subscribe to favorite authors
        for _ in user.favoriteAuthors {
            // Messaging.messaging().subscribe(toTopic: "author_\(authorId)")
        }
    }
    
    func unsubscribeFromTopics(for user: UserProfile) {
        // Unsubscribe from all topics
        // Messaging.messaging().unsubscribe(fromTopic: "all_users")
        // Messaging.messaging().unsubscribe(fromTopic: "user_\(user.uid)")
        
        // Unsubscribe from categories and authors
        for _ in user.favoriteCategories {
            // Messaging.messaging().unsubscribe(fromTopic: "category_\(categoryId)")
        }
        
        for _ in user.favoriteAuthors {
            // Messaging.messaging().unsubscribe(fromTopic: "author_\(authorId)")
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
            if let error = error {
                print("Error scheduling local notification: \(error)")
            }
        }
    }
    
    func scheduleFestivalReminder(festivalName: String, date: Date) {
        let content = UNMutableNotificationContent()
        content.title = "Festival Reminder"
        content.body = "\(festivalName) starter snart!"
        content.sound = .default
        
        // Schedule 1 day before
        let reminderDate = date.addingTimeInterval(-24 * 60 * 60)
        let trigger = UNCalendarNotificationTrigger(dateMatching: Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: reminderDate), repeats: false)
        
        let request = UNNotificationRequest(identifier: "festival_\(festivalName)", content: content, trigger: trigger)
        
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("Error scheduling festival reminder: \(error)")
            }
        }
    }
    
    // MARK: - Notification Preferences
    
    func updateNotificationPreferences(_ preferences: NotificationPreferences) {
        guard UserManager.shared.currentUser != nil else { return }
        
        // Update topic subscriptions based on preferences
        if preferences.newArticles {
            Messaging.messaging().subscribe(toTopic: "new_articles")
        } else {
            Messaging.messaging().unsubscribe(fromTopic: "new_articles")
        }
        
        if preferences.festivalReminders {
            Messaging.messaging().subscribe(toTopic: "festival_reminders")
        } else {
            Messaging.messaging().unsubscribe(fromTopic: "festival_reminders")
        }
        
        if preferences.breakingNews {
            Messaging.messaging().subscribe(toTopic: "breaking_news")
        } else {
            Messaging.messaging().unsubscribe(fromTopic: "breaking_news")
        }
        
        if preferences.weeklyDigest {
            Messaging.messaging().subscribe(toTopic: "weekly_digest")
        } else {
            Messaging.messaging().unsubscribe(fromTopic: "weekly_digest")
        }
    }
    
    // MARK: - Test Local Notification
    
    func sendTestLocalNotification() {
        let content = UNMutableNotificationContent()
        content.title = "Test Notification"
        content.body = "This is a test notification from Apropos Magazine"
        content.sound = .default
        content.badge = 1
        
        // Add custom data
        content.userInfo = [
            "type": "test",
            "article_id": "test_123"
        ]
        
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 2, repeats: false)
        let request = UNNotificationRequest(identifier: "test_notification", content: content, trigger: trigger)
        
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("Error sending test notification: \(error)")
            } else {
                print("Test notification scheduled successfully")
            }
        }
    }
    
    // MARK: - Comprehensive Debug
    
    func debugNotificationSystem() {
        print("🔍 === COMPREHENSIVE NOTIFICATION DEBUG ===")
        print("📱 FCM Token: \(fcmToken ?? "NIL")")
        print("📱 Is Authorized: \(isAuthorized)")
        
        // Check current user
        if let user = UserManager.shared.currentUser {
            print("👤 Current User: \(user.uid)")
            print("👤 User Name: \(user.displayName)")
            print("👤 Notification Preferences: \(user.notificationPreferences)")
        } else {
            print("👤 No current user logged in")
        }
        
        // Check notification settings
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            print("📱 Notification Settings:")
            print("   - Authorization: \(settings.authorizationStatus.rawValue)")
            print("   - Alert: \(settings.alertSetting.rawValue)")
            print("   - Badge: \(settings.badgeSetting.rawValue)")
            print("   - Sound: \(settings.soundSetting.rawValue)")
            print("   - Lock Screen: \(settings.lockScreenSetting.rawValue)")
            print("   - Notification Center: \(settings.notificationCenterSetting.rawValue)")
            print("   - Car Play: \(settings.carPlaySetting.rawValue)")
            print("   - Critical Alert: \(settings.criticalAlertSetting.rawValue)")
            print("   - Announcement: \(settings.announcementSetting.rawValue)")
        }
        
        // Check pending notifications
        UNUserNotificationCenter.current().getPendingNotificationRequests { requests in
            print("📱 Pending Notifications: \(requests.count)")
            for request in requests {
                print("   - \(request.identifier): \(request.content.title)")
            }
        }
        
        // Check delivered notifications
        UNUserNotificationCenter.current().getDeliveredNotifications { notifications in
            print("📱 Delivered Notifications: \(notifications.count)")
            for notification in notifications {
                print("   - \(notification.request.identifier): \(notification.request.content.title)")
            }
        }
        
        // Test FCM topics
        print("🔔 Testing FCM topic subscriptions...")
        if UserManager.shared.currentUser != nil {
            // Force subscribe to new_articles for testing
            Messaging.messaging().subscribe(toTopic: "new_articles") { error in
                if let error = error {
                    print("❌ Error subscribing to 'new_articles': \(error)")
                } else {
                    print("✅ Successfully subscribed to 'new_articles'")
                }
            }
            
            // Test other topics
            Messaging.messaging().subscribe(toTopic: "all_users") { error in
                if let error = error {
                    print("❌ Error subscribing to 'all_users': \(error)")
                } else {
                    print("✅ Successfully subscribed to 'all_users'")
                }
            }
        }
        
        print("🔍 === END DEBUG ===")
    }
    
    func forceSubscribeToNewArticles() {
        print("🔔 Force subscribing to 'new_articles' topic...")
        Messaging.messaging().subscribe(toTopic: "new_articles") { error in
            if let error = error {
                print("❌ Error subscribing to 'new_articles': \(error)")
            } else {
                print("✅ Successfully force subscribed to 'new_articles'")
                
                Task {
                    let token = await MainActor.run { self.fcmToken }
                    if let token {
                        await MainActor.run { self.updateFCMTokenOnServer(token) }
                    }
                }
            }
        }
    }
    
}
