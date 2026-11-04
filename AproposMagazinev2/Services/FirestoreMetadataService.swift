import FirebaseFirestore
import Foundation

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
@MainActor
final class FirestoreMetadataService {
    static let shared = FirestoreMetadataService()

    private lazy var db = Firestore.firestore()

    private init() {}

    typealias CurrentGuard = @MainActor () -> Bool

    func fetchTopics(stillCurrent: @escaping CurrentGuard = { true },
                     completion: @escaping (Result<[Topic], Error>) -> Void) {
        fetchItems(collection: "topics", as: Topic.self, stillCurrent: stillCurrent, completion: completion)
    }

    func fetchSections(stillCurrent: @escaping CurrentGuard = { true },
                       completion: @escaping (Result<[WebflowSection], Error>) -> Void) {
        fetchItems(collection: "sections", as: WebflowSection.self, stillCurrent: stillCurrent, completion: completion)
    }

    func fetchAuthors(stillCurrent: @escaping CurrentGuard = { true },
                      completion: @escaping (Result<[Author], Error>) -> Void) {
        fetchItems(collection: "authors", as: AuthorWrapper.self, stillCurrent: stillCurrent) { result in
            switch result {
            case .success(let wrappers):
                completion(.success(wrappers.map { $0.toAuthor() }))
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    /// `nil` preserves the existing optional-result API. A guarded caller must
    /// recheck its original authority before treating nil as a CMS fallback;
    /// cancellation also completes with nil rather than stranding its waiter.
    func fetchStarsMapping(stillCurrent: @escaping CurrentGuard = { true },
                           completion: @escaping ([String: String]?) -> Void) {
        Task { @MainActor in
            guard stillCurrent() else { completion(nil); return }
            let client = self.db
            guard stillCurrent() else { completion(nil); return }
            let collection = client.collection("metadata")
            guard stillCurrent() else { completion(nil); return }
            let reference = collection.document("starsMapping")
            guard stillCurrent() else { completion(nil); return }
            reference.getDocument { snapshot, error in
                Task { @MainActor in
                    guard stillCurrent() else { completion(nil); return }
                    if error != nil {
                        AppDiagnostics.recordOperational(.metadataFetchFailed)
                        completion(nil)
                        return
                    }
                    guard let data = snapshot?.data(),
                          let mapping = data["mapping"] as? [String: String],
                          !mapping.isEmpty else {
                        completion(nil)
                        return
                    }
                    guard stillCurrent() else { completion(nil); return }
                    completion(mapping)
                }
            }
        }
    }

    // MARK: - Generic item decoding

    private func fetchItems<T: Decodable>(
        collection: String,
        as type: T.Type,
        stillCurrent: @escaping CurrentGuard,
        completion: @escaping (Result<[T], Error>) -> Void
    ) {
        Task { @MainActor in
            guard stillCurrent() else { completion(.failure(CancellationError())); return }
            let client = self.db
            guard stillCurrent() else { completion(.failure(CancellationError())); return }
            let reference = client.collection(collection)
            guard stillCurrent() else { completion(.failure(CancellationError())); return }
            reference.getDocuments { snapshot, error in
                Task { @MainActor in
                    guard stillCurrent() else { completion(.failure(CancellationError())); return }
                    if let error { completion(.failure(error)); return }
                    guard let snapshot, !snapshot.documents.isEmpty else {
                        completion(.failure(FirestoreMetadataError.empty)); return
                    }
                    var items: [T] = []
                    var decodeErrors: [String] = []
                    for document in snapshot.documents {
                        if CMSMirrorDocumentPolicy.isWithdrawn(document.data()) { continue }
                        do {
                            items.append(try self.decodeItem(from: document.data(), as: T.self))
                        } catch {
                            decodeErrors.append("\(document.documentID): \(error.localizedDescription)")
                        }
                    }
                    guard stillCurrent() else { completion(.failure(CancellationError())); return }
                    if !decodeErrors.isEmpty {
                        AppDiagnostics.recordOperational(.metadataDecodeFailed)
                    }
                    if items.isEmpty, !decodeErrors.isEmpty {
                        completion(.failure(FirestoreMetadataError.decodeFailed(decodeErrors.joined(separator: "; "))))
                        return
                    }
                    completion(.success(items))
                }
            }
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
