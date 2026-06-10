import FirebaseFirestore
import Foundation
import OSLog

enum FirestoreArticleError: LocalizedError {
    case empty
    case decodeFailed(String)

    var errorDescription: String? {
        switch self {
        case .empty:
            return "Ingen artikler fundet i Firestore."
        case .decodeFailed(let message):
            return "Kunne ikke dekode artikel fra Firestore: \(message)"
        }
    }
}

final class FirestoreArticleService {
    static let shared = FirestoreArticleService()

    private let logger = Logger(subsystem: "com.aproposmagazine.app", category: "FirestoreArticleService")
    private lazy var db = Firestore.firestore()

    private init() {}

    func fetchArticles(completion: @escaping (Result<[Article], Error>) -> Void) {
        db.collection("articles").getDocuments { [weak self] snapshot, error in
            guard let self else { return }

            if let error {
                completion(.failure(error))
                return
            }

            guard let snapshot, !snapshot.documents.isEmpty else {
                completion(.failure(FirestoreArticleError.empty))
                return
            }

            do {
                let articles = try self.decodeArticles(from: snapshot.documents)
                    .filter(\.isPubliclyPublished)
                if articles.isEmpty {
                    completion(.failure(FirestoreArticleError.empty))
                    return
                }

                let sorted = articles.sorted { lhs, rhs in
                    let leftCreated = lhs.createdOn ?? ""
                    let rightCreated = rhs.createdOn ?? ""
                    if leftCreated != rightCreated {
                        return leftCreated > rightCreated
                    }
                    return (lhs.lastPublished ?? "") > (rhs.lastPublished ?? "")
                }
                completion(.success(sorted))
            } catch {
                completion(.failure(error))
            }
        }
    }

    func fetchArticle(by id: String, completion: @escaping (Result<Article, Error>) -> Void) {
        guard !id.isEmpty else {
            completion(.failure(FirestoreArticleError.empty))
            return
        }

        db.collection("articles").document(id).getDocument { [weak self] snapshot, error in
            guard let self else { return }

            if let error {
                completion(.failure(error))
                return
            }

            guard let snapshot, snapshot.exists, let data = snapshot.data() else {
                self.fetchArticle(bySlug: id, completion: completion)
                return
            }

            do {
                let article = try self.decodeArticle(from: data)
                guard article.isPubliclyPublished else {
                    completion(.failure(FirestoreArticleError.empty))
                    return
                }
                completion(.success(article))
            } catch {
                completion(.failure(error))
            }
        }
    }

    func fetchArticle(bySlug slug: String, completion: @escaping (Result<Article, Error>) -> Void) {
        let normalizedSlug = slug.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedSlug.isEmpty else {
            completion(.failure(FirestoreArticleError.empty))
            return
        }

        db.collection("articles")
            .whereField("fieldData.slug", isEqualTo: normalizedSlug)
            .limit(to: 1)
            .getDocuments { [weak self] snapshot, error in
                guard let self else { return }

                if let error {
                    completion(.failure(error))
                    return
                }

                guard let snapshot,
                      let document = snapshot.documents.first,
                      let data = document.data() as [String: Any]? else {
                    completion(.failure(FirestoreArticleError.empty))
                    return
                }

                do {
                    let article = try self.decodeArticle(from: data)
                    guard article.isPubliclyPublished else {
                        completion(.failure(FirestoreArticleError.empty))
                        return
                    }
                    completion(.success(article))
                } catch {
                    completion(.failure(error))
                }
            }
    }

    private func decodeArticles(from documents: [QueryDocumentSnapshot]) throws -> [Article] {
        var articles: [Article] = []
        var decodeErrors: [String] = []

        for document in documents {
            do {
                articles.append(try decodeArticle(from: document.data()))
            } catch {
                decodeErrors.append("\(document.documentID): \(error.localizedDescription)")
            }
        }

        if !decodeErrors.isEmpty {
            logger.error("Firestore article decode failures: \(decodeErrors.joined(separator: "; "), privacy: .public)")
            if articles.isEmpty {
                throw FirestoreArticleError.decodeFailed(decodeErrors.joined(separator: "; "))
            }
        }

        return articles
    }

    private func decodeArticle(from data: [String: Any]) throws -> Article {
        var payload: [String: Any] = [:]

        if let id = data["id"] as? String {
            payload["id"] = id
        } else {
            throw FirestoreArticleError.decodeFailed("Missing article id")
        }

        if let fieldData = data["fieldData"] as? [String: Any] {
            payload["fieldData"] = fieldData
        } else {
            payload["fieldData"] = [:]
        }

        if let isDraft = data["isDraft"] {
            payload["isDraft"] = isDraft
        }
        if let createdOn = data["createdOn"] {
            payload["createdOn"] = createdOn
        }
        if let lastPublished = data["lastPublished"] {
            payload["lastPublished"] = lastPublished
        }

        let jsonData = try JSONSerialization.data(withJSONObject: payload)
        return try JSONDecoder().decode(Article.self, from: jsonData)
    }
}
