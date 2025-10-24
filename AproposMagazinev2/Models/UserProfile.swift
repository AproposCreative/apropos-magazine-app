import Foundation
import FirebaseAuth

struct UserProfile: Codable {
    let uid: String
    let email: String
    let displayName: String
    let photoURL: String?
    let createdAt: Date
    let lastLoginAt: Date
    
    // User preferences
    var favoriteCategories: [String] = []
    var favoriteAuthors: [String] = []
    var notificationPreferences: NotificationPreferences = NotificationPreferences()
    var readingPreferences: ReadingPreferences = ReadingPreferences()
    
    // Reading history
    var readArticles: [String] = [] // Article IDs
    var bookmarkedArticles: [String] = [] // Article IDs
    var readingProgress: [String: Double] = [:] // Article ID -> Progress (0.0-1.0)
    
    init(firebaseUser: User) {
        self.uid = firebaseUser.uid
        self.email = firebaseUser.email ?? ""
        self.displayName = firebaseUser.displayName ?? ""
        self.photoURL = firebaseUser.photoURL?.absoluteString
        
        // Validate dates once during initialization to prevent timestamp crashes
        let now = Date()
        
        if let creationDate = firebaseUser.metadata.creationDate,
           creationDate.timeIntervalSince1970 > 0 {
            self.createdAt = creationDate
        } else {
            print("⚠️ Invalid creation date, using current date")
            self.createdAt = now
        }
        
        if let lastSignInDate = firebaseUser.metadata.lastSignInDate,
           lastSignInDate.timeIntervalSince1970 > 0 {
            self.lastLoginAt = lastSignInDate
        } else {
            print("⚠️ Invalid last sign in date, using current date")
            self.lastLoginAt = now
        }
    }
    
    // Custom initializer for validated dates
    init(uid: String, email: String, displayName: String, photoURL: String?, createdAt: Date, lastLoginAt: Date, favoriteCategories: [String], favoriteAuthors: [String], notificationPreferences: NotificationPreferences, readingPreferences: ReadingPreferences, readArticles: [String], bookmarkedArticles: [String], readingProgress: [String: Double]) {
        self.uid = uid
        self.email = email
        self.displayName = displayName
        self.photoURL = photoURL
        self.createdAt = createdAt
        self.lastLoginAt = lastLoginAt
        self.favoriteCategories = favoriteCategories
        self.favoriteAuthors = favoriteAuthors
        self.notificationPreferences = notificationPreferences
        self.readingPreferences = readingPreferences
        self.readArticles = readArticles
        self.bookmarkedArticles = bookmarkedArticles
        self.readingProgress = readingProgress
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        uid = try container.decode(String.self, forKey: .uid)
        email = try container.decode(String.self, forKey: .email)
        displayName = try container.decode(String.self, forKey: .displayName)
        photoURL = try? container.decode(String.self, forKey: .photoURL)
        
        // Validate dates once during decoding to prevent timestamp crashes
        let now = Date()
        
        if let date = try? container.decode(Date.self, forKey: .createdAt),
           date.timeIntervalSince1970 > 0 {
            createdAt = date
        } else {
            print("⚠️ Invalid createdAt date from decoder, using current date")
            createdAt = now
        }
        
        if let date = try? container.decode(Date.self, forKey: .lastLoginAt),
           date.timeIntervalSince1970 > 0 {
            lastLoginAt = date
        } else {
            print("⚠️ Invalid lastLoginAt date from decoder, using current date")
            lastLoginAt = now
        }
        
        // Decode optional fields with defaults efficiently (decoding only once)
        favoriteCategories = (try? container.decode([String].self, forKey: .favoriteCategories)) ?? []
        favoriteAuthors = (try? container.decode([String].self, forKey: .favoriteAuthors)) ?? []
        notificationPreferences = (try? container.decode(NotificationPreferences.self, forKey: .notificationPreferences)) ?? NotificationPreferences()
        readingPreferences = (try? container.decode(ReadingPreferences.self, forKey: .readingPreferences)) ?? ReadingPreferences()
        readArticles = (try? container.decode([String].self, forKey: .readArticles)) ?? []
        bookmarkedArticles = (try? container.decode([String].self, forKey: .bookmarkedArticles)) ?? []
        readingProgress = (try? container.decode([String: Double].self, forKey: .readingProgress)) ?? [:]
    }
    
    enum CodingKeys: String, CodingKey {
        case uid, email, displayName, photoURL, createdAt, lastLoginAt
        case favoriteCategories, favoriteAuthors, notificationPreferences, readingPreferences
        case readArticles, bookmarkedArticles, readingProgress
    }
}

// Structs for preferences are value types and have no stored or computed properties that would cause repeated allocations
// Therefore, no caching needed, and no deinit required as structs don't have deinit
// Using structs is efficient because they avoid heap allocations and ARC overhead

struct NotificationPreferences: Codable, Equatable {
    var newArticles: Bool = true
    var festivalReminders: Bool = true
    var breakingNews: Bool = true
    var weeklyDigest: Bool = false
    var quietHours: QuietHours = QuietHours()
}

struct QuietHours: Codable, Equatable {
    var enabled: Bool = false
    // Anchor quiet hour times to 1970-01-01 to avoid out-of-range timestamps in Firestore
    var startTime: Date = Date(timeIntervalSince1970: 22 * 3600) // 1970-01-01 22:00:00 UTC
    var endTime: Date = Date(timeIntervalSince1970: 8 * 3600)   // 1970-01-01 08:00:00 UTC
    
    init() {
        // Default initializer
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try container.decode(Bool.self, forKey: .enabled)
        
        // Validate dates once during decoding to prevent timestamp crashes
        let defaultStartTime = Date(timeIntervalSince1970: 22 * 3600)
        let defaultEndTime = Date(timeIntervalSince1970: 8 * 3600)
        
        if let startTime = try? container.decode(Date.self, forKey: .startTime),
           startTime.timeIntervalSince1970 > 0 {
            self.startTime = startTime
        } else {
            self.startTime = defaultStartTime
        }
        
        if let endTime = try? container.decode(Date.self, forKey: .endTime),
           endTime.timeIntervalSince1970 > 0 {
            self.endTime = endTime
        } else {
            self.endTime = defaultEndTime
        }
    }
    
    enum CodingKeys: String, CodingKey {
        case enabled, startTime, endTime
    }
}

struct ReadingPreferences: Codable, Equatable {
    var fontSize: FontSize = .medium
    var darkMode: Bool = false
    var autoPlayVideos: Bool = true
    var showImages: Bool = true
    var readingTimeEstimate: Bool = true
}

enum FontSize: String, CaseIterable, Codable {
    case small = "small"
    case medium = "medium"
    case large = "large"
    case extraLarge = "extraLarge"
    
    // Computed properties are simple switches with no allocations,
    // so no caching necessary
    
    var displayName: String {
        switch self {
        case .small: return "Lille"
        case .medium: return "Medium"
        case .large: return "Stor"
        case .extraLarge: return "Ekstra stor"
        }
    }
    
    var size: CGFloat {
        switch self {
        case .small: return 14
        case .medium: return 16
        case .large: return 18
        case .extraLarge: return 20
        }
    }
}
