import FirebaseFirestore
import Foundation

enum FirestoreArticleError: LocalizedError {
    case empty
    case withdrawn
    case decodeFailed(String)

    var allowsCMSFallback: Bool {
        if case .empty = self { return true }
        return false
    }

    var errorDescription: String? {
        switch self {
        case .withdrawn:
            return "Artiklen er ikke længere publiceret."
        case .empty:
            return "Ingen artikler fundet i Firestore."
        case .decodeFailed(let message):
            return "Kunne ikke dekode artikel fra Firestore: \(message)"
        }
    }
}

@MainActor
final class FirestoreArticleService {
    static let shared = FirestoreArticleService()

    private lazy var db = Firestore.firestore()

    private init() {}

    typealias CurrentGuard = @MainActor () -> Bool

    /// Compatibility for callers requiring a complete catalog. Production UI
    /// and background refresh consume the typed per-language update below.
    func fetchArticles(stillCurrent: @escaping CurrentGuard = { true },
                       completion: @escaping (Result<[Article], Error>) -> Void) {
        fetchCatalog(stillCurrent: stillCurrent) { result in
            completion(result.flatMap { update in
                if let error = ArticleContentLanguage.allCases.compactMap({ update.failures[$0] }).first {
                    return .failure(error)
                }
                return .success(update.articles)
            })
        }
    }

    func fetchCatalog(stillCurrent: @escaping CurrentGuard,
                      completion: @escaping (Result<ArticleMirrorCatalog.Update, Error>) -> Void) {
        Task { @MainActor in
            guard stillCurrent() else { completion(.failure(CancellationError())); return }
            let ticket = ArticleAvailabilityService.model.beginRead()
            do {
                let englishEnabled = ArticleMirrorCatalog.englishEnabled(in: Bundle.main.infoDictionary ?? [:])
                let batch = try await ArticleMirrorCatalog.loadIndependently(
                    englishEnabled: englishEnabled, stillCurrent: stillCurrent) { language in
                    guard stillCurrent() else { throw CancellationError() }
                    let client = self.db
                    guard stillCurrent() else { throw CancellationError() }
                    let reference = client.collection(language.mirrorCollection)
                    guard stillCurrent() else { throw CancellationError() }
                    let snapshot = try await reference.getDocuments()
                    guard stillCurrent() else { throw CancellationError() }
                    return ArticleMirrorCatalog.Source(language: language,
                        documents: snapshot.documents.map { ($0.documentID, $0.data()) },
                        isFromCache: snapshot.metadata.isFromCache,
                        hasPendingWrites: snapshot.metadata.hasPendingWrites)
                }
                guard stillCurrent() else { throw CancellationError() }
                DispatchQueue.global(qos: .userInitiated).async {
                    let update = ArticleMirrorCatalog.decode(batch)
                    let announcements = ArticleMirrorCatalog.confirmedPublications(from: update.articles,
                        sources: update.namespaces.map(\.source))
                    Task { @MainActor in
                        guard stillCurrent() else { completion(.failure(CancellationError())); return }
                        if !englishEnabled, update.failures.isEmpty,
                           update.validatedSources.allSatisfy({ $0.documents.isEmpty }) {
                            completion(.failure(FirestoreArticleError.empty)); return
                        }
                        if update.hadDecodeFailures { AppDiagnostics.recordOperational(.contentDecodeFailed) }
                        for source in update.validatedSources where !source.isFromCache && !source.hasPendingWrites {
                            guard stillCurrent() else { completion(.failure(CancellationError())); return }
                            let withdrawn = Set(source.documents.filter { CMSMirrorDocumentPolicy.isWithdrawn($0.data) }.map(\.id))
                            ArticleAvailabilityService.model.recordWithdrawals(withdrawn, ticket: ticket)
                        }
                        guard stillCurrent() else { completion(.failure(CancellationError())); return }
                        PodcastAvailabilityService.recordMirrors(update.validatedSources.flatMap(\.documents))
                        guard stillCurrent() else { completion(.failure(CancellationError())); return }
                        let verified = update.articles.filter { article in
                            article.contentLanguage.map(update.freshLanguages.contains) == true
                                && Article.parseWebflowTimestamp(article.lastPublished) != nil
                        }
                        ArticleAvailabilityService.model.recordPublications(verified, ticket: ticket)
                        guard stillCurrent() else { completion(.failure(CancellationError())); return }
                        await NotificationInboxRuntime.reconcilePublishedArticles(announcements,
                            verifiedLanguages: update.freshLanguages, stillCurrent: stillCurrent)
                        guard stillCurrent() else { completion(.failure(CancellationError())); return }
                        completion(.success(update))
                    }
                }
            } catch {
                completion(stillCurrent() ? .failure(error) : .failure(CancellationError()))
            }
        }
    }

    func fetchArticle(by id: String, stillCurrent: @escaping CurrentGuard = { true },
                      completion: @escaping (Result<Article, Error>) -> Void) {
        Task { @MainActor in
            guard stillCurrent() else { completion(.failure(CancellationError())); return }
            self.fetchArticle(by: id, ticket: ArticleAvailabilityService.model.beginRead(),
                              stillCurrent: stillCurrent, completion: completion)
        }
    }

    @MainActor
    private func fetchArticle(by id: String, ticket: ArticleAvailabilityModel.ReadTicket,
                              stillCurrent: @escaping CurrentGuard,
                              completion: @escaping (Result<Article, Error>) -> Void) {
        guard stillCurrent() else { completion(.failure(CancellationError())); return }
        guard CMSMirrorDocumentPolicy.isSafeDocumentID(id) else {
            completion(.failure(FirestoreArticleError.decodeFailed("Invalid article identifier"))); return
        }
        let language = ArticleLanguageSelection.mirrorLanguage(forReaderID: id)
        guard language != .english || ArticleMirrorCatalog.englishEnabled(in: Bundle.main.infoDictionary ?? [:]) else {
            completion(.failure(FirestoreArticleError.decodeFailed("English catalog unavailable"))); return
        }
        let client = db
        guard stillCurrent() else { completion(.failure(CancellationError())); return }
        let collection = client.collection(language.mirrorCollection)
        guard stillCurrent() else { completion(.failure(CancellationError())); return }
        let reference = collection.document(id)
        guard stillCurrent() else { completion(.failure(CancellationError())); return }
        reference.getDocument(source: .server) { snapshot, error in
            Task { @MainActor in
                guard stillCurrent() else { completion(.failure(CancellationError())); return }
                if let error { completion(.failure(error)); return }
                guard let snapshot, snapshot.exists, let data = snapshot.data() else {
                    guard language != .english else { completion(.failure(FirestoreArticleError.empty)); return }
                    // Keep the original read/account authority through fallback.
                    self.fetchArticle(bySlug: id, ticket: ticket, stillCurrent: stillCurrent, completion: completion)
                    return
                }
                do {
                    try ArticleMirrorCatalog.validate(.init(language: language,
                        documents: [(snapshot.documentID, data)], isFromCache: snapshot.metadata.isFromCache,
                        hasPendingWrites: snapshot.metadata.hasPendingWrites))
                } catch { completion(.failure(error)); return }
                self.finishArticle(data: data, id: snapshot.documentID,
                    pending: snapshot.metadata.hasPendingWrites, ticket: ticket,
                    stillCurrent: stillCurrent, completion: completion)
            }
        }
    }

    func fetchArticle(bySlug slug: String, stillCurrent: @escaping CurrentGuard = { true },
                      completion: @escaping (Result<Article, Error>) -> Void) {
        Task { @MainActor in
            guard stillCurrent() else { completion(.failure(CancellationError())); return }
            self.fetchArticle(bySlug: slug, ticket: ArticleAvailabilityService.model.beginRead(),
                              stillCurrent: stillCurrent, completion: completion)
        }
    }

    @MainActor
    private func fetchArticle(bySlug slug: String, ticket: ArticleAvailabilityModel.ReadTicket,
                              stillCurrent: @escaping CurrentGuard,
                              completion: @escaping (Result<Article, Error>) -> Void) {
        guard stillCurrent() else { completion(.failure(CancellationError())); return }
        let normalizedSlug = slug.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedSlug.isEmpty else { completion(.failure(FirestoreArticleError.empty)); return }
        let language = PreferencesManager.shared.articleLanguage
        guard language != .english || ArticleMirrorCatalog.englishEnabled(in: Bundle.main.infoDictionary ?? [:]) else {
            completion(.failure(FirestoreArticleError.decodeFailed("English catalog unavailable"))); return
        }
        let client = db
        guard stillCurrent() else { completion(.failure(CancellationError())); return }
        let collection = client.collection(language.mirrorCollection)
        guard stillCurrent() else { completion(.failure(CancellationError())); return }
        let reference = collection.whereField("fieldData.slug", isEqualTo: normalizedSlug).limit(to: 3)
        guard stillCurrent() else { completion(.failure(CancellationError())); return }
        reference.getDocuments(source: .server) { snapshot, error in
            Task { @MainActor in
                guard stillCurrent() else { completion(.failure(CancellationError())); return }
                if let error { completion(.failure(error)); return }
                do {
                    if let snapshot {
                        try ArticleMirrorCatalog.validate(.init(language: language,
                            documents: snapshot.documents.map { ($0.documentID, $0.data()) },
                            isFromCache: snapshot.metadata.isFromCache, hasPendingWrites: snapshot.metadata.hasPendingWrites))
                    }
                    guard let snapshot, let document = try ArticleLanguageSelection.uniqueSlugDocument(
                        snapshot.documents.map { ($0.documentID, $0.data()) }, language: language) else {
                        completion(.failure(FirestoreArticleError.empty)); return
                    }
                    self.finishArticle(data: document.data, id: document.id,
                        pending: snapshot.metadata.hasPendingWrites, ticket: ticket,
                        stillCurrent: stillCurrent, completion: completion)
                } catch { completion(.failure(error)) }
            }
        }
    }

    @MainActor
    private func finishArticle(data: [String: Any], id: String, pending: Bool,
                               ticket: ArticleAvailabilityModel.ReadTicket,
                               stillCurrent: @escaping CurrentGuard,
                               completion: @escaping (Result<Article, Error>) -> Void) {
        guard stillCurrent() else { completion(.failure(CancellationError())); return }
        guard !pending else { completion(.failure(NSError(domain: "ArticleAvailability", code: 1))); return }
        do {
            let article = try decodeArticle(from: data, expectedID: id)
            guard article.isPubliclyPublished else { throw FirestoreArticleError.withdrawn }
            guard stillCurrent() else { completion(.failure(CancellationError())); return }
            // A server point read owns the same original publication boundary
            // as the feed. It cannot undo a newer withdrawal/observation.
            ArticleAvailabilityService.model.recordPublications([article], ticket: ticket)
            guard stillCurrent() else { completion(.failure(CancellationError())); return }
            completion(.success(article))
        } catch {
            guard stillCurrent() else { completion(.failure(CancellationError())); return }
            if let failure = error as? FirestoreArticleError, case .withdrawn = failure {
                PodcastAvailabilityService.recordMirror(id: id, data: data)
                guard stillCurrent() else { completion(.failure(CancellationError())); return }
                ArticleAvailabilityService.model.recordWithdrawals([id], ticket: ticket)
            }
            guard stillCurrent() else { completion(.failure(CancellationError())); return }
            completion(.failure(error))
        }
    }

    /// Canonical incoming-link lookup: exact document first, otherwise at most
    /// two slug rows so duplicate identities fail closed instead of picking one.
    @MainActor
    func fetchIncomingLinkArticle(identifier: String,
                                  language: ArticleContentLanguage = .danish,
                                  stillCurrent: @escaping CurrentGuard = { true }) async -> Result<Article, Error> {
        guard !Task.isCancelled, stillCurrent() else { return .failure(CancellationError()) }
        guard CMSMirrorDocumentPolicy.isSafeDocumentID(identifier) else { return .failure(FirestoreArticleError.empty) }
        guard language != .english || ArticleMirrorCatalog.englishEnabled(in: Bundle.main.infoDictionary ?? [:]) else {
            return .failure(FirestoreArticleError.decodeFailed("English catalog unavailable"))
        }
        let ticket = ArticleAvailabilityService.model.beginRead()
        guard !Task.isCancelled, stillCurrent() else { return .failure(CancellationError()) }
        let client = db
        guard !Task.isCancelled, stillCurrent() else { return .failure(CancellationError()) }
        let collection = client.collection(language.mirrorCollection)
        guard !Task.isCancelled, stillCurrent() else { return .failure(CancellationError()) }
        let reference = collection.document(identifier)
        guard !Task.isCancelled, stillCurrent() else { return .failure(CancellationError()) }
        do {
            let document = try await reference.getDocument(source: .server)
            guard !Task.isCancelled, stillCurrent() else { return .failure(CancellationError()) }
            if document.exists, let data = document.data() {
                try ArticleMirrorCatalog.validate(.init(language: language, documents: [(document.documentID, data)],
                    isFromCache: document.metadata.isFromCache, hasPendingWrites: document.metadata.hasPendingWrites))
                return finishIncomingArticle(data: data, id: document.documentID,
                    pending: document.metadata.hasPendingWrites, ticket: ticket, stillCurrent: stillCurrent)
            }
            // No new reference or slug fallback under a replaced account.
            guard !Task.isCancelled, stillCurrent() else { return .failure(CancellationError()) }
            let query = collection.whereField("fieldData.slug", isEqualTo: identifier).limit(to: 3)
            guard !Task.isCancelled, stillCurrent() else { return .failure(CancellationError()) }
            let snapshot = try await query.getDocuments(source: .server)
            guard !Task.isCancelled, stillCurrent() else { return .failure(CancellationError()) }
            guard !snapshot.documents.isEmpty else { return .failure(FirestoreArticleError.empty) }
            try ArticleMirrorCatalog.validate(.init(language: language,
                documents: snapshot.documents.map { ($0.documentID, $0.data()) },
                isFromCache: snapshot.metadata.isFromCache, hasPendingWrites: snapshot.metadata.hasPendingWrites))
            guard let match = try ArticleLanguageSelection.uniqueSlugDocument(
                snapshot.documents.map { ($0.documentID, $0.data()) }, language: language) else {
                return .failure(FirestoreArticleError.empty)
            }
            return finishIncomingArticle(data: match.data, id: match.id,
                pending: snapshot.metadata.hasPendingWrites,
                ticket: ticket, stillCurrent: stillCurrent)
        } catch {
            guard !Task.isCancelled, stillCurrent() else { return .failure(CancellationError()) }
            return .failure(FirestoreArticleError.decodeFailed("Unavailable"))
        }
    }

    @MainActor
    private func finishIncomingArticle(data: [String: Any], id: String, pending: Bool,
        ticket: ArticleAvailabilityModel.ReadTicket,
        stillCurrent: @escaping CurrentGuard) -> Result<Article, Error> {
        guard !Task.isCancelled, stillCurrent() else { return .failure(CancellationError()) }
        do {
            guard !pending else { throw FirestoreArticleError.decodeFailed("Unconfirmed source") }
            let article = try decodeArticle(from: data, expectedID: id)
            guard article.isPubliclyPublished else { throw FirestoreArticleError.withdrawn }
            guard !Task.isCancelled, stillCurrent() else { return .failure(CancellationError()) }
            ArticleAvailabilityService.model.recordPublications([article], ticket: ticket)
            guard !Task.isCancelled, stillCurrent() else { return .failure(CancellationError()) }
            guard ArticleAvailabilityService.model.permitsBody(article) else { throw FirestoreArticleError.withdrawn }
            return .success(article)
        } catch {
            guard !Task.isCancelled, stillCurrent() else { return .failure(CancellationError()) }
            if case FirestoreArticleError.withdrawn = error {
                PodcastAvailabilityService.recordMirror(id: id, data: data)
                guard !Task.isCancelled, stillCurrent() else { return .failure(CancellationError()) }
                ArticleAvailabilityService.model.recordWithdrawals([id], ticket: ticket)
            }
            guard !Task.isCancelled, stillCurrent() else { return .failure(CancellationError()) }
            return .failure(FirestoreArticleError.withdrawn)
        }
    }

    private func decodeArticle(from data: [String: Any], expectedID: String, stripBodyContent: Bool = false) throws -> Article {
        try CMSArticleDocumentCodec.decodeArticle(from: data, stripBodyContent: stripBodyContent, expectedID: expectedID)
    }
}
