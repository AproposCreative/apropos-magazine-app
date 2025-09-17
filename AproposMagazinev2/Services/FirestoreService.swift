import Foundation
import FirebaseFirestore
import FirebaseAuth
import UIKit

class FirestoreService {
    static let shared = FirestoreService()
    private lazy var db = Firestore.firestore()
    private init() {}
    
    // Enable offline persistence once per process
    func configurePersistenceIfNeeded() {
        let settings = db.settings
        // Enable persistent on-disk cache with default size
        settings.cacheSettings = PersistentCacheSettings()
        db.settings = settings
    }
    
    // MARK: - Test Functions
    
    /// Test function to verify Firestore connection
    func testFirestoreConnection() async -> Bool {
        do {
            let testRef = db.collection("test").document("connection")
            try await testRef.setData([
                "timestamp": Date(),
                "message": "Connection test successful",
                "device": UIDevice.current.name
            ])
            print("✅ Firestore connection test successful")
            return true
        } catch {
            print("❌ Firestore connection test failed: \(error)")
            return false
        }
    }
    
    /// Test function to read from Firestore
    func testFirestoreRead() async -> String {
        do {
            let testRef = db.collection("test").document("connection")
            let document = try await testRef.getDocument()
            
            if let data = document.data() {
                let message = data["message"] as? String ?? "No message"
                // Safely handle timestamp - skip timestamp processing to avoid crashes
                print("✅ Firestore read test successful: \(message)")
                return "Read successful: \(message)"
            } else {
                print("❌ Firestore read test failed: Document doesn't exist")
                return "Document doesn't exist"
            }
        } catch {
            print("❌ Firestore read test failed: \(error)")
            return "Read failed: \(error.localizedDescription)"
        }
    }
    
    /// Test function to create a test user document
    func createTestUser() async -> Bool {
        do {
            let testUserData: [String: Any] = [
                "name": "Test User",
                "email": "test@aproposmagazine.com",
                "createdAt": Date(),
                "isTestUser": true,
                "favoriteCategories": ["music", "culture"],
                "readingPreferences": [
                    "fontSize": "medium",
                    "theme": "dark"
                ]
            ]
            
            let userRef = db.collection("users").document("test-user-123")
            try await userRef.setData(testUserData)
            print("✅ Test user created successfully")
            return true
        } catch {
            print("❌ Failed to create test user: \(error)")
            return false
        }
    }
    
    /// Test function to read the test user
    func readTestUser() async -> String {
        do {
            let userRef = db.collection("users").document("test-user-123")
            let document = try await userRef.getDocument()
            
            if let data = document.data() {
                let name = data["name"] as? String ?? "Unknown"
                let email = data["email"] as? String ?? "No email"
                print("✅ Test user read successful: \(name) (\(email))")
                return "User: \(name) (\(email))"
            } else {
                print("❌ Test user doesn't exist")
                return "Test user doesn't exist"
            }
        } catch {
            print("❌ Failed to read test user: \(error)")
            return "Read failed: \(error.localizedDescription)"
        }
    }

    func toggleFavorite(_ article: Article, isFavorite: Bool) async throws {
        guard let uid = Auth.auth().currentUser?.uid else {
            throw NSError(domain: "No user", code: 401)
        }

        let favRef = db.collection("users").document(uid).collection("favorites").document(article.id)

        if isFavorite {
            let data: [String: Any] = [
                "id": article.id,
                "name": article.name ?? "",
                "slug": article.slug ?? "",
                "intro": article.intro ?? "",
                "content": article.content ?? "",
                "thumbURL": article.thumbURL?.absoluteString ?? "",
                "coverURL": article.coverURL?.absoluteString ?? "",
                "stjerne": article.stjerne ?? 0,
                "topicID": article.topicID ?? "",
                "topicsIDs": article.topicsIDs ?? [],
                "location": article.location ?? "",
                "authorID": article.authorID ?? ""
            ]
            try await favRef.setData(data)
        } else {
            try await favRef.delete()
        }
    }

    func fetchFavorites() async throws -> [Article] {
        guard let uid = Auth.auth().currentUser?.uid else {
            throw NSError(domain: "No user", code: 401)
        }

        let favRef = db.collection("users").document(uid).collection("favorites")
        // Prefer local cache first, then server
        let snapshot: QuerySnapshot
        do {
            snapshot = try await favRef.getDocuments(source: .cache)
        } catch {
            snapshot = try await favRef.getDocuments(source: .default)
        }

        return snapshot.documents.compactMap { doc in
            let data = doc.data()
            return Article(
                id: data["id"] as? String ?? UUID().uuidString,
                name: data["name"] as? String ?? "No Title",
                slug: data["slug"] as? String ?? "",
                content: data["content"] as? String ?? "",
                intro: data["intro"] as? String ?? "",
                stjerne: data["stjerne"] as? Int ?? 0,
                topicID: data["topicID"] as? String ?? "",
                topicsIDs: data["topicsIDs"] as? [String],
                authorID: data["authorID"] as? String,
                thumbURL: URL(string: data["thumbURL"] as? String ?? ""),
                coverURL: URL(string: data["coverURL"] as? String ?? ""),
                location: data["location"] as? String,
                subtitle: nil,
                isDraft: nil,
                date: nil,
                createdOn: nil,  // Safe default for date fields
                lastPublished: nil,  // Safe default for date fields
                featured: nil
            )
        }
    }
    
    // Realtime listener for favorites
    func listenFavorites(onChange: @escaping ([Article]) -> Void) -> ListenerRegistration? {
        guard let uid = Auth.auth().currentUser?.uid else { return nil }
        let favRef = db.collection("users").document(uid).collection("favorites")
        return favRef.addSnapshotListener { snapshot, _ in
            guard let snapshot = snapshot else { return }
            let articles: [Article] = snapshot.documents.compactMap { doc in
                let data = doc.data()
                return Article(
                    id: data["id"] as? String ?? UUID().uuidString,
                    name: data["name"] as? String ?? "No Title",
                    slug: data["slug"] as? String ?? "",
                    content: data["content"] as? String ?? "",
                    intro: data["intro"] as? String ?? "",
                    stjerne: data["stjerne"] as? Int ?? 0,
                    topicID: data["topicID"] as? String ?? "",
                    topicsIDs: data["topicsIDs"] as? [String],
                    authorID: data["authorID"] as? String,
                    thumbURL: URL(string: data["thumbURL"] as? String ?? ""),
                    coverURL: URL(string: data["coverURL"] as? String ?? ""),
                    location: data["location"] as? String,
                    subtitle: nil,
                    isDraft: nil,
                    date: nil,
                    createdOn: nil,
                    lastPublished: nil,
                    featured: nil
                )
            }
            onChange(articles)
        }
    }
} 
