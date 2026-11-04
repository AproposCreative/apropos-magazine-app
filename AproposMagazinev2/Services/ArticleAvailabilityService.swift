import Foundation
import FirebaseFirestore

/// Only normal app paths access this facade. Model/tests inject local transport.
@MainActor
enum ArticleAvailabilityService {
    static let model: ArticleAvailabilityModel = {
        let defaults = UserDefaults.standard
        let key = "articleAvailabilityState_v1"
        let snapshot = defaults.data(forKey: key).flatMap { try? JSONDecoder().decode(ArticleAvailabilityModel.Snapshot.self, from: $0) } ?? .init()
        return ArticleAvailabilityModel(snapshot: snapshot, save: { state in
            if let data = try? JSONEncoder().encode(state) { defaults.set(data, forKey: key) }
        })
    }()

    typealias CurrentGuard = @MainActor () -> Bool
    typealias Mirror = @MainActor (String, [String: Any]) -> Void
    /// SDK snapshot projection used by the actual adapter and local tests.
    /// This value carries no account/startup authority by itself.
    struct Document {
        let exists: Bool
        let isFromCache: Bool
        let hasPendingWrites: Bool
        let data: [String: Any]
    }
    typealias Subscribe = @MainActor (String, @escaping CurrentGuard,
        @escaping @MainActor (Result<Document, Error>) -> Void) -> (() -> Void)

    @discardableResult
    static func observe(_ id: String, stillCurrent: @escaping CurrentGuard,
                        model injectedModel: ArticleAvailabilityModel? = nil,
                        subscribe injectedSubscribe: Subscribe? = nil,
                        recordPodcastMirror: Mirror? = nil) -> ArticleAvailabilityModel.ObservationTicket? {
        guard CMSMirrorDocumentPolicy.isSafeDocumentID(id), stillCurrent() else { return nil }
        let target = injectedModel ?? model
        guard stillCurrent() else { return nil }
        return target.observe(id: id, stillCurrent: stillCurrent) { articleID, originalGuard, completion in
            guard originalGuard() else { return {} }
            let subscribe = injectedSubscribe ?? subscribeLive
            return subscribe(articleID, originalGuard) { result in
                // The model supplies an observation-token guard as well as the
                // captured startup/account guard. Podcast effects happen only
                // after both have survived the real callback boundary.
                guard originalGuard() else { return }
                switch result {
                case .failure(let error):
                    completion(.failure(error))
                case .success(let document):
                    let localOnly = document.isFromCache || document.hasPendingWrites
                    // Cache misses and unacknowledged local writes are not server evidence.
                    if !document.exists, localOnly { return }
                    let data = document.data
                    if document.exists {
                        do {
                            try ArticleMirrorCatalog.validate(.init(
                                language: ArticleLanguageSelection.mirrorLanguage(forReaderID: articleID),
                                documents: [(articleID, data)], isFromCache: document.isFromCache,
                                hasPendingWrites: document.hasPendingWrites))
                        } catch {
                            guard originalGuard() else { return }
                            completion(.failure(error)); return
                        }
                    }
                    guard originalGuard() else { return }
                    if let recordPodcastMirror { recordPodcastMirror(articleID, data) }
                    else { PodcastAvailabilityService.recordMirror(id: articleID, data: data) }
                    guard originalGuard() else { return }
                    let withdrawn = !document.exists || CMSMirrorDocumentPolicy.isWithdrawn(data)
                    var revision: String?
                    if !withdrawn {
                        guard let article = try? CMSArticleDocumentCodec.decodeArticle(from: data,
                            stripBodyContent: true, expectedID: articleID),
                              article.isPubliclyPublished,
                              Article.parseWebflowTimestamp(article.lastPublished) != nil else {
                            guard originalGuard() else { return }
                            completion(.failure(FirestoreArticleError.decodeFailed("Invalid publication state")))
                            return
                        }
                        revision = article.bodyRevision
                    }
                    guard originalGuard() else { return }
                    completion(.success(.init(withdrawn: withdrawn, isFromCache: localOnly, revision: revision)))
                }
            }
        }
    }

    private static func subscribeLive(_ id: String, stillCurrent: @escaping CurrentGuard,
        completion: @escaping @MainActor (Result<Document, Error>) -> Void) -> (() -> Void) {
        guard stillCurrent() else { return {} }
        let language = ArticleLanguageSelection.mirrorLanguage(forReaderID: id)
        guard language != .english || ArticleMirrorCatalog.englishEnabled(in: Bundle.main.infoDictionary ?? [:]) else {
            completion(.failure(FirestoreArticleError.decodeFailed("English catalog unavailable"))); return {}
        }
        let client = Firestore.firestore()
        guard stillCurrent() else { return {} }
        let collection = client.collection(language.mirrorCollection)
        guard stillCurrent() else { return {} }
        let reference = collection.document(id)
        guard stillCurrent() else { return {} }
        let listener = reference.addSnapshotListener(includeMetadataChanges: true) { snapshot, error in
            Task { @MainActor in
                guard stillCurrent() else { return }
                if let error { completion(.failure(error)); return }
                guard let snapshot else { return }
                let document = Document(exists: snapshot.exists, isFromCache: snapshot.metadata.isFromCache,
                    hasPendingWrites: snapshot.metadata.hasPendingWrites, data: snapshot.data() ?? [:])
                guard stillCurrent() else { return }
                completion(.success(document))
            }
        }
        return { listener.remove() }
    }
}
