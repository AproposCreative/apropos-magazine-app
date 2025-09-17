import SwiftUI
import FirebaseAuth
import FirebaseFirestore

@MainActor
class UserManager: ObservableObject {
    @Published var currentUser: UserProfile?
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    static let shared = UserManager()
    private lazy var db = Firestore.firestore()
    private var authStateListener: AuthStateDidChangeListenerHandle?
    
    private init() {
        // Initialize Firebase auth listener after a short delay to ensure Firebase is configured
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.setupAuthListener()
        }
    }
    
    private func setupAuthListener() {
        // Listen for auth state changes
        authStateListener = Auth.auth().addStateDidChangeListener { [weak self] _, user in
            if let user = user, !user.uid.isEmpty {
                print("[UserManager] User authenticated, loading profile: \(user.uid)")
                self?.loadUserProfile(for: user)
            } else {
                print("[UserManager] No valid user, clearing profile")
                self?.currentUser = nil
            }
        }
        
        // Also check for existing user immediately
        if let currentUser = Auth.auth().currentUser, !currentUser.uid.isEmpty {
            print("[UserManager] Found existing Firebase user: \(currentUser.uid)")
            loadUserProfile(for: currentUser)
        }
    }
    
    // MARK: - Profile Management
    
    func loadUserProfile(for firebaseUser: User) {
        guard !firebaseUser.uid.isEmpty else {
            print("[UserManager] Invalid user UID, skipping profile load")
            return
        }
        
        print("[UserManager] Attempting to load profile for user: \(firebaseUser.uid)")
        isLoading = true
        
        // Skip reading existing profile to avoid timestamp crashes
        print("[UserManager] Skipping profile read to avoid timestamp issues")
        DispatchQueue.main.async { [weak self] in
            self?.isLoading = false
            let newProfile = UserProfile(firebaseUser: firebaseUser)
            self?.saveUserProfile(newProfile)
        }
    }
    
    func saveUserProfile(_ profile: UserProfile) {
        do {
            // Validate dates before saving to prevent timestamp issues
            let now = Date()
            let validatedProfile = UserProfile(
                uid: profile.uid,
                email: profile.email,
                displayName: profile.displayName,
                photoURL: profile.photoURL,
                createdAt: profile.createdAt.timeIntervalSince1970 > 0 ? profile.createdAt : now,
                lastLoginAt: profile.lastLoginAt.timeIntervalSince1970 > 0 ? profile.lastLoginAt : now,
                favoriteCategories: profile.favoriteCategories,
                favoriteAuthors: profile.favoriteAuthors,
                notificationPreferences: profile.notificationPreferences,
                readingPreferences: profile.readingPreferences,
                readArticles: profile.readArticles,
                bookmarkedArticles: profile.bookmarkedArticles,
                readingProgress: profile.readingProgress
            )
            
            try db.collection("users").document(profile.uid).setData(from: validatedProfile)
            currentUser = validatedProfile
            print("[UserManager] Profile saved successfully with validated dates")
        } catch {
            errorMessage = "Failed to save profile: \(error.localizedDescription)"
            print("[UserManager] Error saving profile: \(error)")
        }
    }
    
    // MARK: - Reading History
    
    func markArticleAsRead(_ articleId: String) {
        guard var user = currentUser else { return }
        
        if !user.readArticles.contains(articleId) {
            user.readArticles.append(articleId)
            saveUserProfile(user)
        }
    }
    
    func toggleBookmark(_ articleId: String) {
        guard var user = currentUser else { return }
        
        if user.bookmarkedArticles.contains(articleId) {
            user.bookmarkedArticles.removeAll { $0 == articleId }
        } else {
            user.bookmarkedArticles.append(articleId)
        }
        
        saveUserProfile(user)
    }
    
    func updateReadingProgress(_ progress: Double, for articleId: String) {
        guard var user = currentUser else { return }
        user.readingProgress[articleId] = progress
        saveUserProfile(user)
    }
    
    func isArticleBookmarked(_ articleId: String) -> Bool {
        return currentUser?.bookmarkedArticles.contains(articleId) ?? false
    }
    
    func getReadingProgress(for articleId: String) -> Double {
        return currentUser?.readingProgress[articleId] ?? 0.0
    }
    
    // MARK: - Preferences
    
    func updateNotificationPreferences(_ preferences: NotificationPreferences) {
        guard var user = currentUser else { return }
        user.notificationPreferences = preferences
        saveUserProfile(user)
    }
    
    func updateReadingPreferences(_ preferences: ReadingPreferences) {
        guard var user = currentUser else { return }
        user.readingPreferences = preferences
        saveUserProfile(user)
    }
    
    func toggleFavoriteCategory(_ categoryId: String) {
        guard var user = currentUser else { return }
        
        if user.favoriteCategories.contains(categoryId) {
            user.favoriteCategories.removeAll { $0 == categoryId }
        } else {
            user.favoriteCategories.append(categoryId)
        }
        
        saveUserProfile(user)
    }
    
    func toggleFavoriteAuthor(_ authorId: String) {
        guard var user = currentUser else { return }
        
        if user.favoriteAuthors.contains(authorId) {
            user.favoriteAuthors.removeAll { $0 == authorId }
        } else {
            user.favoriteAuthors.append(authorId)
        }
        
        saveUserProfile(user)
    }
    
    // MARK: - Analytics
    
    func getReadingStats() -> ReadingStats {
        guard let user = currentUser else { return ReadingStats() }
        
        return ReadingStats(
            totalArticlesRead: user.readArticles.count,
            totalBookmarks: user.bookmarkedArticles.count,
            averageReadingProgress: user.readingProgress.values.reduce(0, +) / Double(max(user.readingProgress.count, 1)),
            favoriteCategories: user.favoriteCategories.count,
            favoriteAuthors: user.favoriteAuthors.count
        )
    }
}

struct ReadingStats {
    let totalArticlesRead: Int
    let totalBookmarks: Int
    let averageReadingProgress: Double
    let favoriteCategories: Int
    let favoriteAuthors: Int
    
    init(totalArticlesRead: Int = 0, totalBookmarks: Int = 0, averageReadingProgress: Double = 0.0, favoriteCategories: Int = 0, favoriteAuthors: Int = 0) {
        self.totalArticlesRead = totalArticlesRead
        self.totalBookmarks = totalBookmarks
        self.averageReadingProgress = averageReadingProgress
        self.favoriteCategories = favoriteCategories
        self.favoriteAuthors = favoriteAuthors
    }
}
