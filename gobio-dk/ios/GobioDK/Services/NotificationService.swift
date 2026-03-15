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
    
    private let logger = Logger(subsystem: "dk.gobio.app", category: "NotificationService")
    
    private override init() {
        super.init()
        checkAuthorizationStatus()
        
        if let existingToken = UserDefaults.standard.string(forKey: "FCMRegistrationToken") {
            fcmToken = existingToken
        }
    }
    
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
        } catch {
            logger.error("Kunne ikke anmode om push-tilladelse: \(error.localizedDescription, privacy: .public)")
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
    
    func updateFCMTokenOnServer(_ token: String?) {
        guard let token else { return }
        
        if let user = UserManager.shared.currentUser, !user.uid.isEmpty {
            let db = Firestore.firestore()
            db.collection("users").document(user.uid).updateData([
                "fcmToken": token,
                "lastTokenUpdate": Date()
            ]) { error in
                if let error {
                    self.logger.error("Fejl ved opdatering af FCM token: \(error.localizedDescription, privacy: .public)")
                }
            }
        }
    }
    
    // MARK: - Topic Subscriptions
    
    func subscribeToDefaultTopics() {
        Messaging.messaging().subscribe(toTopic: "gobio_all_users")
        Messaging.messaging().subscribe(toTopic: "gobio_new_movies")
    }
    
    func subscribeToPremiereNotifications(for movieId: Int) {
        let topic = "gobio_premiere_\(movieId)"
        Messaging.messaging().subscribe(toTopic: topic)
        logger.info("Abonneret på premiere-notifikation for film \(movieId)")
    }
    
    func unsubscribeFromPremiereNotifications(for movieId: Int) {
        let topic = "gobio_premiere_\(movieId)"
        Messaging.messaging().unsubscribe(fromTopic: topic)
    }
    
    func updateNotificationPreferences(_ preferences: GobioNotificationPreferences) {
        guard UserManager.shared.currentUser != nil else { return }
        
        toggleTopic(preferences.premiereAlerts, topic: "gobio_premieres")
        toggleTopic(preferences.newMovies, topic: "gobio_new_movies")
        toggleTopic(preferences.weeklyHighlights, topic: "gobio_weekly")
    }
    
    private func toggleTopic(_ isEnabled: Bool, topic: String) {
        if isEnabled {
            Messaging.messaging().subscribe(toTopic: topic)
        } else {
            Messaging.messaging().unsubscribe(fromTopic: topic)
        }
    }
    
    // MARK: - Notification Categories
    
    func setupNotificationCategories() {
        let viewAction = UNNotificationAction(
            identifier: "VIEW_MOVIE",
            title: "Se film",
            options: [.foreground]
        )
        
        let bookAction = UNNotificationAction(
            identifier: "BOOK_TICKETS",
            title: "Bestil billetter",
            options: [.foreground]
        )
        
        let premiereCategory = UNNotificationCategory(
            identifier: "PREMIERE",
            actions: [viewAction, bookAction],
            intentIdentifiers: [],
            options: [.customDismissAction]
        )
        
        let newMovieCategory = UNNotificationCategory(
            identifier: "NEW_MOVIE",
            actions: [viewAction],
            intentIdentifiers: [],
            options: []
        )
        
        UNUserNotificationCenter.current().setNotificationCategories([premiereCategory, newMovieCategory])
    }
    
    // MARK: - Local Notifications (Premiere Reminders)
    
    func schedulePremiereReminder(movie: Movie) {
        guard let releaseDate = movie.releaseDateObject else { return }
        
        let content = UNMutableNotificationContent()
        content.title = "\(movie.title) har premiere!"
        content.body = "Filmen du har fulgt har nu premiere i biograferne. Se spilletider og bestil billetter."
        content.sound = .default
        content.categoryIdentifier = "PREMIERE"
        content.threadIdentifier = "premieres"
        content.userInfo = [
            "type": "premiere",
            "movie_id": String(movie.tmdbId),
            "movie_title": movie.title
        ]
        
        if let posterPath = movie.posterPath {
            content.userInfo["poster_url"] = "https://image.tmdb.org/t/p/w342\(posterPath)"
        }
        
        let triggerDate = Calendar.current.dateComponents([.year, .month, .day, .hour], from: releaseDate)
        let trigger = UNCalendarNotificationTrigger(dateMatching: triggerDate, repeats: false)
        
        let request = UNNotificationRequest(
            identifier: "premiere_\(movie.tmdbId)",
            content: content,
            trigger: trigger
        )
        
        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                self.logger.error("Fejl ved planlægning af premiere-påmindelse: \(error.localizedDescription, privacy: .public)")
            } else {
                self.logger.info("Premiere-påmindelse planlagt for \(movie.title, privacy: .public)")
            }
        }
    }
    
    func cancelPremiereReminder(for movieId: Int) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(
            withIdentifiers: ["premiere_\(movieId)"]
        )
    }
}
