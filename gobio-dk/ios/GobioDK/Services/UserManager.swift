import FirebaseAuth
import FirebaseFirestore
import OSLog
import SwiftUI

@MainActor
class UserManager: ObservableObject {
    @Published var currentUser: UserProfile?
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    static let shared = UserManager()
    private lazy var db = Firestore.firestore()
    private var authStateListener: AuthStateDidChangeListenerHandle?
    private let logger = Logger(subsystem: "dk.gobio.app", category: "UserManager")
    
    private init() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.setupAuthListener()
        }
    }
    
    private func merge(existing: UserProfile, with firebaseUser: User) -> UserProfile {
        let now = Date()
        let created = existing.createdAt.timeIntervalSince1970 > 0
            ? existing.createdAt
            : (firebaseUser.metadata.creationDate ?? now)
        
        let lastLogin = firebaseUser.metadata.lastSignInDate ?? existing.lastLoginAt
        
        return UserProfile(
            uid: existing.uid,
            email: firebaseUser.email ?? existing.email,
            displayName: {
                if let name = firebaseUser.displayName, !name.isEmpty {
                    return name
                }
                return existing.displayName
            }(),
            photoURL: firebaseUser.photoURL?.absoluteString ?? existing.photoURL,
            createdAt: created,
            lastLoginAt: lastLogin.timeIntervalSince1970 > 0 ? lastLogin : now,
            preferredCity: existing.preferredCity,
            watchlistMovieIds: existing.watchlistMovieIds,
            notificationPreferences: existing.notificationPreferences
        )
    }
    
    private func setupAuthListener() {
        authStateListener = Auth.auth().addStateDidChangeListener { [weak self] _, user in
            if let user = user, !user.uid.isEmpty {
                self?.loadUserProfile(for: user)
            } else {
                self?.currentUser = nil
            }
        }
        
        if let currentUser = Auth.auth().currentUser, !currentUser.uid.isEmpty {
            loadUserProfile(for: currentUser)
        }
    }
    
    func loadUserProfile(for firebaseUser: User) {
        guard !firebaseUser.uid.isEmpty else { return }
        
        isLoading = true
        
        Task {
            do {
                let document = try await db.collection("users").document(firebaseUser.uid).getDocument()
                let profile: UserProfile
                
                if document.exists {
                    do {
                        let data = document.data() ?? [:]
                        
                        let isoFormatter = ISO8601DateFormatter()
                        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                        
                        func convertTimestamps(_ dict: [String: Any]) -> [String: Any] {
                            var converted = dict
                            for (key, value) in converted {
                                if let timestamp = value as? Timestamp {
                                    converted[key] = isoFormatter.string(from: timestamp.dateValue())
                                } else if let nestedDict = value as? [String: Any] {
                                    converted[key] = convertTimestamps(nestedDict)
                                }
                            }
                            return converted
                        }
                        
                        let jsonData = convertTimestamps(data)
                        let jsonSerialized = try JSONSerialization.data(withJSONObject: jsonData)
                        let decoder = JSONDecoder()
                        decoder.dateDecodingStrategy = .iso8601
                        let existing = try decoder.decode(UserProfile.self, from: jsonSerialized)
                        profile = self.merge(existing: existing, with: firebaseUser)
                    } catch {
                        profile = UserProfile(firebaseUser: firebaseUser)
                    }
                } else {
                    profile = UserProfile(firebaseUser: firebaseUser)
                }
                
                await MainActor.run {
                    self.saveUserProfile(profile)
                    self.isLoading = false
                }
            } catch {
                let fallbackProfile = UserProfile(firebaseUser: firebaseUser)
                await MainActor.run {
                    self.errorMessage = "Kunne ikke hente brugerprofil."
                    self.saveUserProfile(fallbackProfile)
                    self.isLoading = false
                }
            }
        }
    }
    
    func saveUserProfile(_ profile: UserProfile) {
        let now = Date()
        let validatedProfile = UserProfile(
            uid: profile.uid,
            email: profile.email,
            displayName: profile.displayName,
            photoURL: profile.photoURL,
            createdAt: profile.createdAt.timeIntervalSince1970 > 0 ? profile.createdAt : now,
            lastLoginAt: profile.lastLoginAt.timeIntervalSince1970 > 0 ? profile.lastLoginAt : now,
            preferredCity: profile.preferredCity,
            watchlistMovieIds: profile.watchlistMovieIds,
            notificationPreferences: profile.notificationPreferences
        )
        
        var firestoreData: [String: Any] = [
            "uid": validatedProfile.uid,
            "email": validatedProfile.email,
            "displayName": validatedProfile.displayName,
            "createdAt": Timestamp(date: validatedProfile.createdAt),
            "lastLoginAt": Timestamp(date: validatedProfile.lastLoginAt),
            "preferredCity": validatedProfile.preferredCity,
            "watchlistMovieIds": validatedProfile.watchlistMovieIds
        ]
        
        if let photoURL = validatedProfile.photoURL {
            firestoreData["photoURL"] = photoURL
        }
        
        let encoder = JSONEncoder()
        if let notificationPrefs = try? encoder.encode(validatedProfile.notificationPreferences),
           let notificationDict = try? JSONSerialization.jsonObject(with: notificationPrefs) as? [String: Any] {
            firestoreData["notificationPreferences"] = notificationDict
        }
        
        db.collection("users").document(profile.uid).setData(firestoreData) { [weak self] error in
            Task { @MainActor in
                if let error = error {
                    self?.errorMessage = "Kunne ikke gemme profil: \(error.localizedDescription)"
                } else {
                    self?.currentUser = validatedProfile
                    
                    if let fcmToken = NotificationService.shared.fcmToken {
                        NotificationService.shared.updateFCMTokenOnServer(fcmToken)
                    }
                }
            }
        }
    }
    
    // MARK: - Watchlist
    
    func toggleWatchlistMovie(_ movieId: Int) {
        guard var user = currentUser else { return }
        
        if user.watchlistMovieIds.contains(movieId) {
            user.watchlistMovieIds.removeAll { $0 == movieId }
        } else {
            user.watchlistMovieIds.append(movieId)
        }
        
        saveUserProfile(user)
    }
    
    func isMovieInWatchlist(_ movieId: Int) -> Bool {
        return currentUser?.watchlistMovieIds.contains(movieId) ?? false
    }
    
    // MARK: - Preferences
    
    func updatePreferredCity(_ city: String) {
        guard var user = currentUser else { return }
        user.preferredCity = city
        saveUserProfile(user)
    }
    
    func updateNotificationPreferences(_ preferences: GobioNotificationPreferences) {
        guard var user = currentUser else { return }
        user.notificationPreferences = preferences
        saveUserProfile(user)
    }
}
