import Foundation
import OSLog
import SwiftUI
import UserNotifications

@MainActor
class SmartNotificationService: NSObject, ObservableObject {
    @Published var isAuthorized = false
    @Published var notificationSettings = NotificationSettings()
    
    static let shared = SmartNotificationService()
    
    private let notificationService = NotificationService.shared
    private let logger = Logger(subsystem: "com.aproposmagazine.app", category: "SmartNotificationService")
    
    private override init() {
        super.init()
        checkAuthorizationStatus()
        loadNotificationSettings()
    }
    
    // MARK: - Authorization
    
    func requestAuthorization() async {
        await notificationService.requestAuthorization()
        
        await MainActor.run {
            self.isAuthorized = self.notificationService.isAuthorized
        }
        
        if isAuthorized {
            HapticManager.shared.success()
        } else {
            logger.warning("Push-autorisation blev ikke givet.")
            HapticManager.shared.error()
        }
    }
    
    private func checkAuthorizationStatus() {
        UNUserNotificationCenter.current().getNotificationSettings { [weak self] settings in
            DispatchQueue.main.async {
                self?.isAuthorized = settings.authorizationStatus == .authorized
            }
        }
    }
    
    // MARK: - Smart Notifications
    
    func scheduleReadingReminder() {
        guard isAuthorized else { return }
        
        let content = UNMutableNotificationContent()
        content.title = "Læsning påkrævet"
        content.body = "Du har ikke læst i dag. Tjek de nyeste artikler!"
        content.sound = .default
        content.categoryIdentifier = "READING_REMINDER"
        content.threadIdentifier = "reading_reminders" // Group all reading reminders
        
        // Schedule for 8 PM if user hasn't read today
        var dateComponents = DateComponents()
        dateComponents.hour = 20
        dateComponents.minute = 0
        
        let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: true)
        let request = UNNotificationRequest(identifier: "reading_reminder", content: content, trigger: trigger)
        
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                self.logger.error("Fejl ved planlægning af læsepåmindelse: \(error.localizedDescription, privacy: .public)")
            }
        }
    }
    
    func schedulePersonalizedRecommendations() {
        guard isAuthorized else { return }
        
        let content = UNMutableNotificationContent()
        content.title = "Nye artikler for dig"
        content.body = "Vi har fundet nye artikler baseret på dine interesser"
        content.sound = .default
        content.categoryIdentifier = "PERSONALIZED_RECOMMENDATIONS"
        content.threadIdentifier = "personalized_recommendations" // Group all personalized recommendations
        
        // Schedule for 10 AM daily
        var dateComponents = DateComponents()
        dateComponents.hour = 10
        dateComponents.minute = 0
        
        let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: true)
        let request = UNNotificationRequest(identifier: "personalized_recommendations", content: content, trigger: trigger)
        
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                self.logger.error("Fejl ved planlægning af personlige anbefalinger: \(error.localizedDescription, privacy: .public)")
            }
        }
    }
    
    func scheduleFestivalReminder(festivalName: String, date: Date) {
        guard isAuthorized else { return }
        
        let content = UNMutableNotificationContent()
        content.title = "Festival påmindelse"
        content.body = "\(festivalName) starter snart! Læs vores guide."
        content.sound = .default
        content.categoryIdentifier = "FESTIVAL_REMINDER"
        content.threadIdentifier = "festival_reminders" // Group all festival reminders
        
        // Schedule 1 day before
        let reminderDate = date.addingTimeInterval(-24 * 60 * 60)
        let trigger = UNCalendarNotificationTrigger(
            dateMatching: Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: reminderDate),
            repeats: false
        )
        
        let request = UNNotificationRequest(
            identifier: "festival_\(festivalName)",
            content: content,
            trigger: trigger
        )
        
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                self.logger.error("Fejl ved planlægning af festivalpåmindelse: \(error.localizedDescription, privacy: .public)")
            }
        }
    }
    
    func scheduleBreakingNewsAlert(title: String, body: String) {
        guard isAuthorized && notificationSettings.breakingNews else { return }
        
        let content = UNMutableNotificationContent()
        content.title = "Breaking News: \(title)"
        content.body = body
        content.sound = .default
        content.categoryIdentifier = "BREAKING_NEWS"
        content.interruptionLevel = .timeSensitive
        content.threadIdentifier = "breaking_news" // Group all breaking news
        
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let request = UNNotificationRequest(
            identifier: "breaking_news_\(UUID().uuidString)",
            content: content,
            trigger: trigger
        )
        
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                self.logger.error("Fejl ved planlægning af breaking news: \(error.localizedDescription, privacy: .public)")
            }
        }
    }
    
    func scheduleWeeklyDigest() {
        guard isAuthorized && notificationSettings.weeklyDigest else { return }
        
        let content = UNMutableNotificationContent()
        content.title = "Ugens bedste artikler"
        content.body = "Se hvad du har misset denne uge"
        content.sound = .default
        content.categoryIdentifier = "WEEKLY_DIGEST"
        content.threadIdentifier = "weekly_digest" // Group all weekly digests
        
        // Schedule for Sunday at 9 AM
        var dateComponents = DateComponents()
        dateComponents.weekday = 1 // Sunday
        dateComponents.hour = 9
        dateComponents.minute = 0
        
        let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: true)
        let request = UNNotificationRequest(identifier: "weekly_digest", content: content, trigger: trigger)
        
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                self.logger.error("Fejl ved planlægning af weekly digest: \(error.localizedDescription, privacy: .public)")
            }
        }
    }
    
    // MARK: - Smart Scheduling
    
    func scheduleBasedOnUserBehavior() {
        guard UserManager.shared.currentUser != nil else { return }
        
        // Analyze user reading patterns
        let readingStats = ReadingProgressManager.shared.readingStats
        
        if readingStats?.totalArticlesRead == 0 {
            // New user - send welcome notification
            scheduleWelcomeNotification()
        } else if readingStats?.totalArticlesRead ?? 0 < 5 {
            // Casual reader - gentle reminders
            scheduleGentleReminders()
        } else {
            // Active reader - personalized content
            schedulePersonalizedContent()
        }
    }
    
    private func scheduleWelcomeNotification() {
        let content = UNMutableNotificationContent()
        content.title = "Velkommen til Apropos Magazine"
        content.body = "Udforsk vores artikler og find din næste favorit"
        content.sound = .default
        content.categoryIdentifier = "WELCOME"
        content.threadIdentifier = "welcome" // Group welcome notifications
        
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 3600, repeats: false) // 1 hour delay
        let request = UNNotificationRequest(identifier: "welcome", content: content, trigger: trigger)
        
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                self.logger.error("Fejl ved planlægning af velkomstnotifikation: \(error.localizedDescription, privacy: .public)")
            }
        }
    }
    
    private func scheduleGentleReminders() {
        let content = UNMutableNotificationContent()
        content.title = "Nye historier venter"
        content.body = "Tjek vores seneste artikler"
        content.sound = .default
        content.categoryIdentifier = "GENTLE_REMINDER"
        content.threadIdentifier = "gentle_reminders" // Group all gentle reminders
        
        // Schedule for 6 PM
        var dateComponents = DateComponents()
        dateComponents.hour = 18
        dateComponents.minute = 0
        
        let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: true)
        let request = UNNotificationRequest(identifier: "gentle_reminder", content: content, trigger: trigger)
        
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                self.logger.error("Fejl ved planlægning af gentle reminder: \(error.localizedDescription, privacy: .public)")
            }
        }
    }
    
    private func schedulePersonalizedContent() {
        // Schedule more frequent, personalized notifications
        schedulePersonalizedRecommendations()
        scheduleWeeklyDigest()
    }
    
    // MARK: - Notification Categories
    
    func setupNotificationCategories() {
        let readingReminderAction = UNNotificationAction(
            identifier: "READ_ACTION",
            title: "Læs nu",
            options: [.foreground]
        )
        
        let readingReminderCategory = UNNotificationCategory(
            identifier: "READING_REMINDER",
            actions: [readingReminderAction],
            intentIdentifiers: [],
            options: []
        )
        
        // New article category with "Læs nu" action
        let newArticleAction = UNNotificationAction(
            identifier: "READ_ACTION",
            title: "Læs nu",
            options: [.foreground]
        )
        
        let newArticleCategory = UNNotificationCategory(
            identifier: "NEW_ARTICLE",
            actions: [newArticleAction],
            intentIdentifiers: [],
            options: [.customDismissAction]
        )
        
        let personalizedAction = UNNotificationAction(
            identifier: "VIEW_RECOMMENDATIONS",
            title: "Se anbefalinger",
            options: [.foreground]
        )
        
        let personalizedCategory = UNNotificationCategory(
            identifier: "PERSONALIZED_RECOMMENDATIONS",
            actions: [personalizedAction],
            intentIdentifiers: [],
            options: []
        )
        
        let festivalAction = UNNotificationAction(
            identifier: "VIEW_FESTIVAL_GUIDE",
            title: "Se guide",
            options: [.foreground]
        )
        
        let festivalCategory = UNNotificationCategory(
            identifier: "FESTIVAL_REMINDER",
            actions: [festivalAction],
            intentIdentifiers: [],
            options: []
        )
        
        let breakingNewsAction = UNNotificationAction(
            identifier: "READ_BREAKING_NEWS",
            title: "Læs nu",
            options: [.foreground]
        )
        
        let breakingNewsCategory = UNNotificationCategory(
            identifier: "BREAKING_NEWS",
            actions: [breakingNewsAction],
            intentIdentifiers: [],
            options: []
        )
        
        UNUserNotificationCenter.current().setNotificationCategories([
            readingReminderCategory,
            personalizedCategory,
            festivalCategory,
            breakingNewsCategory,
            newArticleCategory
        ])
    }
    
    // MARK: - Settings Management
    
    func updateNotificationSettings(_ settings: NotificationSettings) {
        notificationSettings = settings
        saveNotificationSettings()
        
        // Update scheduled notifications based on new settings
        updateScheduledNotifications()
    }
    
    private func updateScheduledNotifications() {
        // Remove all existing notifications
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
        
        // Re-schedule based on current settings
        if notificationSettings.readingReminders {
            scheduleReadingReminder()
        }
        
        if notificationSettings.personalizedRecommendations {
            schedulePersonalizedRecommendations()
        }
        
        if notificationSettings.weeklyDigest {
            scheduleWeeklyDigest()
        }
        
        // Re-schedule based on user behavior
        scheduleBasedOnUserBehavior()
    }
    
    // MARK: - Persistence
    
    private func loadNotificationSettings() {
        guard let data = UserDefaults.standard.data(forKey: "notification_settings"),
              let settings = try? JSONDecoder().decode(NotificationSettings.self, from: data) else {
            return
        }
        
        notificationSettings = settings
    }
    
    private func saveNotificationSettings() {
        if let data = try? JSONEncoder().encode(notificationSettings) {
            UserDefaults.standard.set(data, forKey: "notification_settings")
        }
    }
}

// MARK: - Notification Settings

struct NotificationSettings: Codable, Equatable {
    var newArticles: Bool = true
    var readingReminders: Bool = true
    var personalizedRecommendations: Bool = true
    var festivalReminders: Bool = true
    var breakingNews: Bool = true
    var weeklyDigest: Bool = false
    var quietHours: QuietHours = QuietHours()
    
    struct QuietHours: Codable, Equatable {
        var enabled: Bool = false
        var startTime: Date = Calendar.current.date(from: DateComponents(hour: 22, minute: 0)) ?? Date()
        var endTime: Date = Calendar.current.date(from: DateComponents(hour: 8, minute: 0)) ?? Date()
    }
}

// MARK: - SwiftUI Extensions

extension View {
    func withSmartNotifications() -> some View {
        self.environmentObject(SmartNotificationService.shared)
    }
}
