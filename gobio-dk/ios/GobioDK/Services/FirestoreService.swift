import Foundation
import FirebaseFirestore
import FirebaseAuth

class FirestoreService {
    static let shared = FirestoreService()
    private lazy var db = Firestore.firestore()
    private static var persistenceConfigured = false
    private init() {}
    
    func configurePersistenceIfNeeded() {
        guard !Self.persistenceConfigured else { return }
        
        let firestore = Firestore.firestore()
        let settings = firestore.settings
        settings.cacheSettings = PersistentCacheSettings()
        firestore.settings = settings
        Self.persistenceConfigured = true
    }
    
    // MARK: - Watchlist
    
    func addToWatchlist(_ movie: Movie) async throws {
        guard let uid = Auth.auth().currentUser?.uid else {
            throw NSError(domain: "No user", code: 401)
        }
        
        let watchlistRef = db.collection("users").document(uid).collection("watchlist").document(String(movie.tmdbId))
        
        let data: [String: Any] = [
            "tmdbId": movie.tmdbId,
            "title": movie.title,
            "posterPath": movie.posterPath ?? "",
            "releaseDate": movie.releaseDate ?? "",
            "isUpcoming": movie.isUpcoming,
            "genres": movie.genreNames,
            "voteAverage": movie.voteAverage ?? 0,
            "addedAt": FieldValue.serverTimestamp(),
            "notifyOnPremiere": true
        ]
        
        try await watchlistRef.setData(data)
    }
    
    func removeFromWatchlist(tmdbId: Int) async throws {
        guard let uid = Auth.auth().currentUser?.uid else {
            throw NSError(domain: "No user", code: 401)
        }
        
        let watchlistRef = db.collection("users").document(uid).collection("watchlist").document(String(tmdbId))
        try await watchlistRef.delete()
    }
    
    func fetchWatchlist() async throws -> [Movie] {
        guard let uid = Auth.auth().currentUser?.uid else {
            throw NSError(domain: "No user", code: 401)
        }
        
        let watchlistRef = db.collection("users").document(uid).collection("watchlist")
        let snapshot: QuerySnapshot
        do {
            snapshot = try await watchlistRef.getDocuments(source: .cache)
        } catch {
            snapshot = try await watchlistRef.getDocuments(source: .default)
        }
        
        return snapshot.documents.compactMap { doc in
            let data = doc.data()
            let tmdbId = data["tmdbId"] as? Int ?? 0
            return Movie(
                id: tmdbId,
                tmdbId: tmdbId,
                title: data["title"] as? String ?? "",
                originalTitle: nil,
                overview: nil,
                posterPath: {
                    let path = data["posterPath"] as? String ?? ""
                    return path.isEmpty ? nil : path
                }(),
                backdropPath: nil,
                trailerYoutubeKey: nil,
                releaseDate: data["releaseDate"] as? String,
                runtimeMinutes: nil,
                genres: (data["genres"] as? [String] ?? []).enumerated().map { Genre(id: $0.offset, name: $0.element) },
                voteAverage: data["voteAverage"] as? Double,
                voteCount: nil,
                isUpcoming: data["isUpcoming"] as? Bool ?? false
            )
        }
    }
    
    func listenWatchlist(onChange: @escaping ([Movie]) -> Void) -> ListenerRegistration? {
        guard let uid = Auth.auth().currentUser?.uid else { return nil }
        let watchlistRef = db.collection("users").document(uid).collection("watchlist")
        return watchlistRef.addSnapshotListener { snapshot, _ in
            guard let snapshot = snapshot else { return }
            let movies: [Movie] = snapshot.documents.compactMap { doc in
                let data = doc.data()
                let tmdbId = data["tmdbId"] as? Int ?? 0
                return Movie(
                    id: tmdbId,
                    tmdbId: tmdbId,
                    title: data["title"] as? String ?? "",
                    originalTitle: nil,
                    overview: nil,
                    posterPath: {
                        let path = data["posterPath"] as? String ?? ""
                        return path.isEmpty ? nil : path
                    }(),
                    backdropPath: nil,
                    trailerYoutubeKey: nil,
                    releaseDate: data["releaseDate"] as? String,
                    runtimeMinutes: nil,
                    genres: (data["genres"] as? [String] ?? []).enumerated().map { Genre(id: $0.offset, name: $0.element) },
                    voteAverage: data["voteAverage"] as? Double,
                    voteCount: nil,
                    isUpcoming: data["isUpcoming"] as? Bool ?? false
                )
            }
            onChange(movies)
        }
    }
    
    func isInWatchlist(tmdbId: Int) async -> Bool {
        guard let uid = Auth.auth().currentUser?.uid else { return false }
        
        let docRef = db.collection("users").document(uid).collection("watchlist").document(String(tmdbId))
        do {
            let doc = try await docRef.getDocument()
            return doc.exists
        } catch {
            return false
        }
    }
}
