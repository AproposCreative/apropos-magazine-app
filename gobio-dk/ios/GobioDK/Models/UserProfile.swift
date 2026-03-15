import Foundation
import FirebaseAuth

struct UserProfile: Codable {
    let uid: String
    let email: String
    let displayName: String
    let photoURL: String?
    let createdAt: Date
    let lastLoginAt: Date
    
    var preferredCity: String
    var watchlistMovieIds: [Int]
    var notificationPreferences: GobioNotificationPreferences
    
    init(firebaseUser: User) {
        self.uid = firebaseUser.uid
        self.email = firebaseUser.email ?? ""
        self.displayName = firebaseUser.displayName ?? ""
        self.photoURL = firebaseUser.photoURL?.absoluteString
        
        let now = Date()
        
        if let creationDate = firebaseUser.metadata.creationDate,
           creationDate.timeIntervalSince1970 > 0 {
            self.createdAt = creationDate
        } else {
            self.createdAt = now
        }
        
        if let lastSignInDate = firebaseUser.metadata.lastSignInDate,
           lastSignInDate.timeIntervalSince1970 > 0 {
            self.lastLoginAt = lastSignInDate
        } else {
            self.lastLoginAt = now
        }
        
        self.preferredCity = "København"
        self.watchlistMovieIds = []
        self.notificationPreferences = GobioNotificationPreferences()
    }
    
    init(uid: String, email: String, displayName: String, photoURL: String?,
         createdAt: Date, lastLoginAt: Date, preferredCity: String,
         watchlistMovieIds: [Int], notificationPreferences: GobioNotificationPreferences) {
        self.uid = uid
        self.email = email
        self.displayName = displayName
        self.photoURL = photoURL
        self.createdAt = createdAt
        self.lastLoginAt = lastLoginAt
        self.preferredCity = preferredCity
        self.watchlistMovieIds = watchlistMovieIds
        self.notificationPreferences = notificationPreferences
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        uid = try container.decode(String.self, forKey: .uid)
        email = try container.decode(String.self, forKey: .email)
        displayName = try container.decode(String.self, forKey: .displayName)
        photoURL = try? container.decode(String.self, forKey: .photoURL)
        
        let now = Date()
        
        if let date = try? container.decode(Date.self, forKey: .createdAt),
           date.timeIntervalSince1970 > 0 {
            createdAt = date
        } else {
            createdAt = now
        }
        
        if let date = try? container.decode(Date.self, forKey: .lastLoginAt),
           date.timeIntervalSince1970 > 0 {
            lastLoginAt = date
        } else {
            lastLoginAt = now
        }
        
        preferredCity = (try? container.decode(String.self, forKey: .preferredCity)) ?? "København"
        watchlistMovieIds = (try? container.decode([Int].self, forKey: .watchlistMovieIds)) ?? []
        notificationPreferences = (try? container.decode(GobioNotificationPreferences.self, forKey: .notificationPreferences)) ?? GobioNotificationPreferences()
    }
    
    enum CodingKeys: String, CodingKey {
        case uid, email, displayName, photoURL, createdAt, lastLoginAt
        case preferredCity, watchlistMovieIds, notificationPreferences
    }
}

struct GobioNotificationPreferences: Codable, Equatable {
    var premiereAlerts: Bool = true
    var newMovies: Bool = true
    var weeklyHighlights: Bool = false
}

let danishCities: [String] = [
    "København",
    "Aarhus",
    "Odense",
    "Aalborg",
    "Esbjerg",
    "Randers",
    "Kolding",
    "Horsens",
    "Vejle",
    "Roskilde",
    "Herning",
    "Silkeborg",
    "Næstved",
    "Fredericia",
    "Viborg",
    "Holstebro",
    "Sønderborg",
]
