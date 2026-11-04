import Foundation
import FirebaseFirestore
import FirebaseAuth
import UIKit

class FirestoreService {
    static let shared = FirestoreService()
    private lazy var db = Firestore.firestore()
    private static var persistenceConfigured = false
    private let injectedFavoriteWriteEffects: FavoriteWriteEffects?
    private init() { injectedFavoriteWriteEffects = nil }
    init(favoriteWriteEffects: FavoriteWriteEffects) { injectedFavoriteWriteEffects = favoriteWriteEffects }
    
    // Enable offline persistence once per process
    // IMPORTANT: This must be called BEFORE any Firestore operations
    // Call this in AppDelegate.didFinishLaunchingWithOptions
    func configurePersistenceIfNeeded() {
        // Only configure once per app lifecycle
        guard !Self.persistenceConfigured else {
            return
        }
        
        // Get Firestore instance and configure settings BEFORE any operations
        // We use Firestore.firestore() directly to get the shared instance
        let firestore = Firestore.firestore()
        let settings = firestore.settings
        
        // Configure cache settings
        // Note: cacheSettings is not optional, so we always set it
        // The static flag ensures we only do this once
        settings.cacheSettings = PersistentCacheSettings()
        firestore.settings = settings
        Self.persistenceConfigured = true
    }
    
    #if DEBUG
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
            return true
        } catch {
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
                return "Read successful: \(message)"
            } else {
                return "Document doesn't exist"
            }
        } catch {
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
            return true
        } catch {
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
                return "User: \(name) (\(email))"
            } else {
                return "Test user doesn't exist"
            }
        } catch {
            return "Read failed: \(error.localizedDescription)"
        }
    }
    #endif

    enum FavoriteFailure: Error { case wrongOwner, invalidMetadata, unavailable }

    struct FavoriteWriteEffects {
        let identity: @MainActor () -> String?
        let performWrite: @MainActor (String, @escaping FavoriteCurrentGuard,
            @escaping ReaderWriterDrainRuntime.Start) async throws -> Void
        let write: @MainActor (String, Article, Bool, @escaping FavoriteCurrentGuard,
            @escaping ReaderWriterDrainRuntime.Completion) -> Void
        let drain: @MainActor (@escaping FavoriteCurrentGuard, @escaping ReaderWriterDrainRuntime.Completion) -> Void
    }

    /// Own the first physical drain return without making cancellation release
    /// an SDK wait which is still in flight.
    private final class FavoriteDrainReply: @unchecked Sendable {
        private let lock = NSLock()
        private var continuation: CheckedContinuation<Void, Error>?
        init(_ continuation: CheckedContinuation<Void, Error>) { self.continuation = continuation }
        func finish(_ error: Error?) {
            lock.lock(); let value = continuation; continuation = nil; lock.unlock()
            guard let value else { return }
            if let error { value.resume(throwing: error) } else { value.resume() }
        }
    }

    /// Retain the exact SDK client without reading its non-Sendable state from
    /// the callback queue. The holder itself is isolated to the main actor.
    @MainActor private final class FavoriteDrainClientLifetime {
        private let client: Firestore
        init(_ client: Firestore) { self.client = client }
    }

    @MainActor private func favoriteWriteEffects() -> FavoriteWriteEffects {
        if let injectedFavoriteWriteEffects { return injectedFavoriteWriteEffects }
        return .init(identity: { Auth.auth().currentUser?.uid }, performWrite: { uid, current, start in
            guard current() else { throw CancellationError() }
            let runtime = ReaderWriterDrainRuntime.shared
            guard current() else { throw CancellationError() }
            try await runtime.performWrite(expectedUserID: uid, stillCurrent: current, start: start)
        }, write: { [self] uid, article, enabled, current, completion in
            guard current() else { completion(CancellationError()); return }
            let client = self.db
            guard current() else { completion(CancellationError()); return }
            let users = client.collection("users")
            guard current() else { completion(CancellationError()); return }
            let user = users.document(uid)
            guard current() else { completion(CancellationError()); return }
            let favorites = user.collection("favorites")
            guard current() else { completion(CancellationError()); return }
            let reference = favorites.document(article.id)
            var fields = FavoriteArticleDocumentCodec.encode(article)
            fields.removeValue(forKey: "content"); fields.removeValue(forKey: "intro"); fields.removeValue(forKey: "trailer")
            guard current() else { completion(CancellationError()); return }
            if enabled { reference.setData(fields, completion: completion) }
            else { reference.delete(completion: completion) }
        }, drain: { [self] current, completion in
            guard current() else { completion(CancellationError()); return }
            let client = self.db
            guard current() else { completion(CancellationError()); return }
            let lifetime = FavoriteDrainClientLifetime(client)
            client.waitForPendingWrites { error in
                withExtendedLifetime(lifetime) { completion(error) }
            }
        })
    }

    @MainActor private func favoriteWritePermission(expectedUserID: String, articleID: String,
        source: @escaping FavoriteCurrentGuard, identity: @escaping @MainActor () -> String?) -> FavoriteCurrentGuard {
        var denied = false
        return {
            guard !denied, !Task.isCancelled, source(), !denied else { denied = true; return false }
            let actual = identity()
            guard source(), !denied, !Task.isCancelled,
                  FavoritesCloudSelection.permitsWrite(expectedUserID: expectedUserID,
                    actualUserID: actual, articleID: articleID) else { denied = true; return false }
            return true
        }
    }

    /// Firebase's public contract includes pending writes from a previous app
    /// session for the active user. The caller additionally owns the original
    /// model generation; UID equality alone cannot fence A -> guest -> A.
    @MainActor
    func drainPendingFavoriteWrites(expectedUserID: String, stillCurrent: @escaping FavoriteCurrentGuard) async throws {
        guard stillCurrent(), !Task.isCancelled else { throw FavoriteFailure.wrongOwner }
        let effects = favoriteWriteEffects()
        let original = favoriteWritePermission(expectedUserID: expectedUserID, articleID: "favorites",
            source: stillCurrent, identity: effects.identity)
        guard original() else { throw FavoriteFailure.wrongOwner }
        do {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                let reply = FavoriteDrainReply(continuation)
                guard original() else { reply.finish(CancellationError()); return }
                effects.drain(original) { error in reply.finish(error) }
            }
        } catch { throw FavoriteFailure.unavailable }
        guard original() else { throw FavoriteFailure.wrongOwner }
    }

    /// Absolute desired state at the original expected path. Authentication is
    /// checked before SDK lookup; provider work already started cannot be undone
    /// by a later account change and remains serialized by the coordinator.
    @MainActor
    func setFavorite(_ article: Article, enabled: Bool, expectedUserID: String,
                     stillCurrent: @escaping @MainActor () -> Bool) async throws {
        guard stillCurrent(), !Task.isCancelled else { throw FavoriteFailure.wrongOwner }
        guard let light = try? FavoritesRecordCodec.lightweight(article) else { throw FavoriteFailure.invalidMetadata }
        let effects = favoriteWriteEffects()
        let original = favoriteWritePermission(expectedUserID: expectedUserID, articleID: light.id,
            source: stillCurrent, identity: effects.identity)
        guard original() else { throw FavoriteFailure.wrongOwner }
        do {
            try await effects.performWrite(expectedUserID, original) { stillAdmitted, completion in
                guard original(), stillAdmitted() else { completion(CancellationError()); return }
                effects.write(expectedUserID, light, enabled, {
                    original() && stillAdmitted()
                }, completion)
            }
            guard original() else { throw FavoriteFailure.wrongOwner }
        } catch { throw FavoriteFailure.unavailable }
    }

    typealias FavoriteCurrentGuard = @MainActor () -> Bool
    struct FavoriteDocument {
        let id: String
        let fields: [String: Any]
    }
    struct FavoriteSnapshot {
        let documents: [FavoriteDocument]
        let isFromCache: Bool
        let hasPendingWrites: Bool
    }
    /// Failure ends this subscription. Snapshot decoding failures are separate
    /// and must leave the subscription available for a later valid snapshot.
    typealias FavoriteSubscribe = @MainActor (String, @escaping FavoriteCurrentGuard,
        @escaping @MainActor (Result<FavoriteSnapshot, Error>) -> Void) -> (() -> Void)

    /// Exact physical listener ownership. A denied authority stays denied even
    /// if a later provider happens to have the same UID. The owner must remove
    /// this handle on retirement; construction itself starts no service.
    @MainActor
    final class FavoriteListener {
        private let permission: FavoriteCurrentGuard
        private var removed = false
        private var cancellation: (() -> Void)?

        fileprivate init(permission: @escaping FavoriteCurrentGuard) { self.permission = permission }

        func isCurrent() -> Bool {
            guard !removed else { return false }
            let permitted = permission() // May synchronously remove this listener.
            guard !removed else { return false }
            guard permitted else { remove(); return false }
            return true
        }

        func remove() {
            guard !removed else { return }
            removed = true // Revoke before the SDK can synchronously deliver a callback.
            let cancel = cancellation
            cancellation = nil
            cancel?()
        }

        fileprivate func finish(_ notify: () -> Void) {
            guard isCurrent() else { return }
            remove()
            // Physical cancellation may reenter with another account/listener.
            guard permission() else { return }
            notify()
        }

        fileprivate func installCancellation(_ cancel: @escaping () -> Void) {
            // A synchronous first callback can revoke ownership before subscribe
            // returns its physical handle. Retire that returned handle once.
            guard !removed else { cancel(); return }
            cancellation = cancel
            _ = isCurrent()
        }
    }

    /// Query cardinality is bounded; legacy Firestore documents may still carry
    /// body fields over the wire. They are discarded before model publication.
    @MainActor
    func listenFavorites(expectedUserID: String, stillCurrent: @escaping FavoriteCurrentGuard,
        actualUserID: (@MainActor () -> String?)? = nil,
        subscribe injectedSubscribe: FavoriteSubscribe? = nil,
        onChange: @escaping @MainActor (Result<FavoritesModel.RemoteSnapshot, Error>) -> Void
    ) -> FavoriteListener? {
        // Do not even look up the provider until the original startup gate is open.
        guard stillCurrent() else { return nil }
        let currentUID: @MainActor () -> String? = actualUserID ?? { Auth.auth().currentUser?.uid }
        let actual = currentUID()
        guard stillCurrent(), FavoritesCloudSelection.permitsWrite(expectedUserID: expectedUserID,
            actualUserID: actual, articleID: "favorites") else { return nil }
        let listener = FavoriteListener(permission: {
            guard stillCurrent() else { return false }
            let actual = currentUID()
            return stillCurrent() && FavoritesCloudSelection.permitsWrite(expectedUserID: expectedUserID,
                actualUserID: actual, articleID: "favorites")
        })
        guard listener.isCurrent() else { return nil }
        let original: FavoriteCurrentGuard = { [weak listener] in listener?.isCurrent() == true }
        let subscribe = injectedSubscribe ?? subscribeFavoriteSnapshots
        let cancel = subscribe(expectedUserID, original) { [weak listener] result in
            guard let listener, listener.isCurrent() else { return }
            let decoded: Result<FavoritesModel.RemoteSnapshot, Error>
            switch result {
            case .failure:
                listener.finish { onChange(.failure(FavoriteFailure.unavailable)) }
                return
            case .success(let snapshot):
                decoded = Self.decodeFavoriteSnapshot(snapshot)
            }
            guard listener.isCurrent() else { return }
            onChange(decoded)
        }
        listener.installCancellation(cancel)
        guard listener.isCurrent() else { return nil }
        return listener
    }

    @MainActor
    private func subscribeFavoriteSnapshots(_ expectedUserID: String, stillCurrent: @escaping FavoriteCurrentGuard,
        completion: @escaping @MainActor (Result<FavoriteSnapshot, Error>) -> Void) -> (() -> Void) {
        guard stillCurrent() else { return {} }
        let client = db
        guard stillCurrent() else { return {} }
        let users = client.collection("users")
        guard stillCurrent() else { return {} }
        let user = users.document(expectedUserID)
        guard stillCurrent() else { return {} }
        let favorites = user.collection("favorites")
        guard stillCurrent() else { return {} }
        let query = favorites.limit(to: FavoritesRecordCodec.maximumEntries + 1)
        guard stillCurrent() else { return {} }
        let registration = query.addSnapshotListener(includeMetadataChanges: true) { snapshot, error in
            Task { @MainActor in
                guard stillCurrent() else { return }
                guard error == nil, let snapshot else {
                    completion(.failure(FavoriteFailure.unavailable)); return
                }
                let value = FavoriteSnapshot(documents: snapshot.documents.map {
                    FavoriteDocument(id: $0.documentID, fields: $0.data())
                }, isFromCache: snapshot.metadata.isFromCache, hasPendingWrites: snapshot.metadata.hasPendingWrites)
                guard stillCurrent() else { return }
                completion(.success(value))
            }
        }
        return { registration.remove() }
    }

    private static func decodeFavoriteSnapshot(_ snapshot: FavoriteSnapshot) -> Result<FavoritesModel.RemoteSnapshot, Error> {
        guard snapshot.documents.count <= FavoritesRecordCodec.maximumEntries,
              Set(snapshot.documents.map(\.id)).count == snapshot.documents.count else {
            return .failure(FavoriteFailure.invalidMetadata)
        }
        var articles: [Article] = []
        for document in snapshot.documents {
            var fields = document.fields
            guard FavoritesRecordCodec.isValidID(document.id), CMSMirrorDocumentPolicy.isSafeDocumentID(document.id),
                  fields["id"] == nil || fields["id"] as? String == document.id else {
                return .failure(FavoriteFailure.invalidMetadata)
            }
            fields.removeValue(forKey: "content")
            fields.removeValue(forKey: "intro")
            fields.removeValue(forKey: "trailer")
            let decoded = FavoriteArticleDocumentCodec.decode(fields, documentID: document.id)
            guard let light = try? FavoritesRecordCodec.lightweight(decoded) else {
                return .failure(FavoriteFailure.invalidMetadata)
            }
            articles.append(light)
        }
        return .success(.init(articles: articles, isFromCache: snapshot.isFromCache,
                              hasPendingWrites: snapshot.hasPendingWrites))
    }
}
