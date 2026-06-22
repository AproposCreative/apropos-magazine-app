import FirebaseFirestore
import Foundation
import OSLog

enum FirestoreMetadataError: LocalizedError {
    case empty
    case decodeFailed(String)

    var errorDescription: String? {
        switch self {
        case .empty:
            return "Ingen metadata fundet i Firestore."
        case .decodeFailed(let message):
            return "Kunne ikke dekode metadata fra Firestore: \(message)"
        }
    }
}

/// Reads CMS metadata (topics, sections, authors, stars-mapping) from Firestore.
///
/// The Cloud Functions `syncMetadata`/`syncMetadataScheduled` jobs store each
/// Webflow item as a raw `{ id, fieldData }` document, so we can reconstruct the
/// exact JSON shape the existing models expect via their `init(from:)`.
final class FirestoreMetadataService {
    static let shared = FirestoreMetadataService()

    private let logger = Logger(
        subsystem: "com.aproposmagazine.app",
        category: "FirestoreMetadataService"
    )
    private lazy var db = Firestore.firestore()

    private init() {}

    func fetchTopics(completion: @escaping (Result<[Topic], Error>) -> Void) {
        fetchItems(collection: "topics", as: Topic.self, completion: completion)
    }

    func fetchSections(completion: @escaping (Result<[WebflowSection], Error>) -> Void) {
        fetchItems(collection: "sections", as: WebflowSection.self, completion: completion)
    }

    func fetchAuthors(completion: @escaping (Result<[Author], Error>) -> Void) {
        fetchItems(collection: "authors", as: AuthorWrapper.self) { result in
            switch result {
            case .success(let wrappers):
                completion(.success(wrappers.map { $0.toAuthor() }))
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    /// Returns `nil` when the mapping has not been synced yet, so callers can
    /// decide whether to fall back to Webflow or to bundled defaults.
    func fetchStarsMapping(completion: @escaping ([String: String]?) -> Void) {
        db.collection("metadata").document("starsMapping").getDocument { [weak self] snapshot, error in
            if let error {
                self?.logger.error("Failed to read stars mapping from Firestore: \(error.localizedDescription, privacy: .public)")
                completion(nil)
                return
            }

            guard let data = snapshot?.data(),
                  let mapping = data["mapping"] as? [String: String],
                  !mapping.isEmpty else {
                completion(nil)
                return
            }

            completion(mapping)
        }
    }

    // MARK: - Generic item decoding

    private func fetchItems<T: Decodable>(
        collection: String,
        as type: T.Type,
        completion: @escaping (Result<[T], Error>) -> Void
    ) {
        db.collection(collection).getDocuments { [weak self] snapshot, error in
            guard let self else { return }

            if let error {
                completion(.failure(error))
                return
            }

            guard let snapshot, !snapshot.documents.isEmpty else {
                completion(.failure(FirestoreMetadataError.empty))
                return
            }

            var items: [T] = []
            var decodeErrors: [String] = []

            for document in snapshot.documents {
                do {
                    items.append(try self.decodeItem(from: document.data(), as: T.self))
                } catch {
                    decodeErrors.append("\(document.documentID): \(error.localizedDescription)")
                }
            }

            if !decodeErrors.isEmpty {
                self.logger.error("Firestore \(collection, privacy: .public) decode failures: \(decodeErrors.joined(separator: "; "), privacy: .public)")
            }

            if items.isEmpty {
                completion(.failure(FirestoreMetadataError.empty))
                return
            }

            completion(.success(items))
        }
    }

    private func decodeItem<T: Decodable>(from data: [String: Any], as type: T.Type) throws -> T {
        var payload: [String: Any] = [:]

        guard let id = data["id"] as? String else {
            throw FirestoreMetadataError.decodeFailed("Missing item id")
        }
        payload["id"] = id
        payload["fieldData"] = (data["fieldData"] as? [String: Any]) ?? [:]

        let jsonData = try JSONSerialization.data(withJSONObject: payload)
        return try JSONDecoder().decode(T.self, from: jsonData)
    }
}
