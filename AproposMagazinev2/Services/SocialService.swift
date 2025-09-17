import SwiftUI
import FirebaseFirestore
import FirebaseAuth

@MainActor
class SocialService: ObservableObject {
    @Published var comments: [Comment] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    static let shared = SocialService()
    private lazy var db = Firestore.firestore()
    
    private init() {}
    
    // MARK: - Comments
    
    func loadComments(for articleId: String) {
        isLoading = true
        
        db.collection("articles").document(articleId)
            .collection("comments")
            .order(by: "timestamp", descending: false)
            .addSnapshotListener { [weak self] snapshot, error in
                DispatchQueue.main.async {
                    self?.isLoading = false
                    
                    if let error = error {
                        self?.errorMessage = "Failed to load comments: \(error.localizedDescription)"
                        return
                    }
                    
                    guard let documents = snapshot?.documents else {
                        self?.comments = []
                        return
                    }
                    
                    self?.comments = documents.compactMap { document in
                        do {
                            return try document.data(as: Comment.self)
                        } catch {
                            print("[SocialService] Failed to decode comment: \(error.localizedDescription)")
                            return nil
                        }
                    }
                }
            }
    }
    
    func addComment(_ text: String, for articleId: String) {
        guard let user = UserManager.shared.currentUser else {
            errorMessage = "Du skal være logget ind for at kommentere"
            return
        }
        
        let comment = Comment(
            id: UUID().uuidString,
            articleId: articleId,
            userId: user.uid,
            userName: user.displayName,
            userPhotoURL: user.photoURL,
            text: text,
            timestamp: Date(),
            likes: 0,
            replies: []
        )
        
        do {
            try db.collection("articles").document(articleId)
                .collection("comments").document(comment.id)
                .setData(from: comment)
        } catch {
            errorMessage = "Failed to add comment: \(error.localizedDescription)"
        }
    }
    
    func likeComment(_ commentId: String, in articleId: String) {
        guard let user = UserManager.shared.currentUser else { return }
        
        let commentRef = db.collection("articles").document(articleId)
            .collection("comments").document(commentId)
        
        commentRef.updateData([
            "likes": FieldValue.increment(Int64(1)),
            "likedBy": FieldValue.arrayUnion([user.uid])
        ]) { [weak self] error in
            if let error = error {
                DispatchQueue.main.async {
                    self?.errorMessage = "Failed to like comment: \(error.localizedDescription)"
                }
            }
        }
    }
    
    func replyToComment(_ text: String, commentId: String, in articleId: String) {
        guard let user = UserManager.shared.currentUser else {
            errorMessage = "Du skal være logget ind for at svare"
            return
        }
        
        let reply = CommentReply(
            id: UUID().uuidString,
            userId: user.uid,
            userName: user.displayName,
            userPhotoURL: user.photoURL,
            text: text,
            timestamp: Date()
        )
        
        let commentRef = db.collection("articles").document(articleId)
            .collection("comments").document(commentId)
        
        commentRef.updateData([
            "replies": FieldValue.arrayUnion([(try? JSONEncoder().encode(reply)) ?? Data()])
        ]) { [weak self] error in
            if let error = error {
                DispatchQueue.main.async {
                    self?.errorMessage = "Failed to add reply: \(error.localizedDescription)"
                }
            }
        }
    }
    
    // MARK: - Ratings
    
    func rateArticle(_ rating: Int, for articleId: String) {
        guard let user = UserManager.shared.currentUser else {
            errorMessage = "Du skal være logget ind for at rate"
            return
        }
        
        guard rating >= 1 && rating <= 5 else {
            errorMessage = "Rating skal være mellem 1 og 5"
            return
        }
        
        let ratingData: [String: Any] = [
            "userId": user.uid,
            "userName": user.displayName,
            "rating": rating,
            "timestamp": Date()
        ]
        
        db.collection("articles").document(articleId)
            .collection("ratings").document(user.uid)
            .setData(ratingData) { [weak self] error in
                if let error = error {
                    DispatchQueue.main.async {
                        self?.errorMessage = "Failed to rate article: \(error.localizedDescription)"
                    }
                }
            }
    }
    
    func getAverageRating(for articleId: String, completion: @escaping (Double) -> Void) {
        db.collection("articles").document(articleId)
            .collection("ratings").getDocuments { snapshot, error in
                guard let documents = snapshot?.documents else {
                    completion(0.0)
                    return
                }
                
                let ratings = documents.compactMap { doc -> Int? in
                    doc.data()["rating"] as? Int
                }
                
                let average = ratings.isEmpty ? 0.0 : Double(ratings.reduce(0, +)) / Double(ratings.count)
                completion(average)
            }
    }
    
    func getUserRating(for articleId: String, completion: @escaping (Int?) -> Void) {
        guard let user = UserManager.shared.currentUser else {
            completion(nil)
            return
        }
        
        db.collection("articles").document(articleId)
            .collection("ratings").document(user.uid).getDocument { snapshot, error in
                if let data = snapshot?.data(),
                   let rating = data["rating"] as? Int {
                    completion(rating)
                } else {
                    completion(nil)
                }
            }
    }
    
    // MARK: - Sharing
    
    func shareArticle(_ article: Article) -> UIActivityViewController {
        let text = "Tjek denne artikel: \(article.name ?? "Apropos Magazine")"
        let url = URL(string: "https://aproposmagazine.com/article/\(article.slug ?? article.id)") ?? URL(string: "https://aproposmagazine.com")!
        
        let activityItems: [Any] = [text, url]
        
        let activityViewController = UIActivityViewController(
            activityItems: activityItems,
            applicationActivities: nil
        )
        
        // Exclude some activity types
        activityViewController.excludedActivityTypes = [
            .assignToContact,
            .addToReadingList,
            .openInIBooks
        ]
        
        return activityViewController
    }
    
    // MARK: - Social Analytics
    
    func trackArticleView(_ articleId: String) {
        guard let user = UserManager.shared.currentUser else { return }
        
        let viewData: [String: Any] = [
            "userId": user.uid,
            "timestamp": Date(),
            "type": "view"
        ]
        
        db.collection("articles").document(articleId)
            .collection("analytics").addDocument(data: viewData)
    }
    
    func trackArticleShare(_ articleId: String, platform: String) {
        guard let user = UserManager.shared.currentUser else { return }
        
        let shareData: [String: Any] = [
            "userId": user.uid,
            "platform": platform,
            "timestamp": Date(),
            "type": "share"
        ]
        
        db.collection("articles").document(articleId)
            .collection("analytics").addDocument(data: shareData)
    }
}

// MARK: - Supporting Types

struct Comment: Codable, Identifiable {
    let id: String
    let articleId: String
    let userId: String
    let userName: String
    let userPhotoURL: String?
    let text: String
    let timestamp: Date
    var likes: Int
    var replies: [CommentReply]

    init(id: String, articleId: String, userId: String, userName: String, userPhotoURL: String?, text: String, timestamp: Date, likes: Int, replies: [CommentReply]) {
        self.id = id
        self.articleId = articleId
        self.userId = userId
        self.userName = userName
        self.userPhotoURL = userPhotoURL
        self.text = text
        self.timestamp = timestamp
        self.likes = likes
        self.replies = replies
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        articleId = try container.decode(String.self, forKey: .articleId)
        userId = try container.decode(String.self, forKey: .userId)
        userName = try container.decode(String.self, forKey: .userName)
        userPhotoURL = try? container.decode(String.self, forKey: .userPhotoURL)
        text = try container.decode(String.self, forKey: .text)
        likes = (try? container.decode(Int.self, forKey: .likes)) ?? 0
        replies = (try? container.decode([CommentReply].self, forKey: .replies)) ?? []
        
        // Simple timestamp handling - just use Date() if there's any issue
        if let date = try? container.decode(Date.self, forKey: .timestamp) {
            timestamp = date
        } else {
            timestamp = Date()
        }
    }

    enum CodingKeys: String, CodingKey {
        case id, articleId, userId, userName, userPhotoURL, text, timestamp, likes, replies
    }

    var formattedDate: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: timestamp, relativeTo: Date())
    }
}

struct CommentReply: Codable, Identifiable {
    let id: String
    let userId: String
    let userName: String
    let userPhotoURL: String?
    let text: String
    let timestamp: Date

    enum CodingKeys: String, CodingKey {
        case id, userId, userName, userPhotoURL, text, timestamp
    }

    init(id: String, userId: String, userName: String, userPhotoURL: String?, text: String, timestamp: Date) {
        self.id = id
        self.userId = userId
        self.userName = userName
        self.userPhotoURL = userPhotoURL
        self.text = text
        self.timestamp = timestamp
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        userId = try container.decode(String.self, forKey: .userId)
        userName = try container.decode(String.self, forKey: .userName)
        userPhotoURL = try? container.decode(String.self, forKey: .userPhotoURL)
        text = try container.decode(String.self, forKey: .text)
        
        // Robust timestamp handling - try Date first, fallback to current date
        if let date = try? container.decode(Date.self, forKey: .timestamp) {
            timestamp = date
        } else {
            timestamp = Date()
        }
    }

    var formattedDate: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: timestamp, relativeTo: Date())
    }
}
