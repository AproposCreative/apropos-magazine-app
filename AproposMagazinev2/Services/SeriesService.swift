import Foundation
import Combine
import FirebaseFirestore

struct ContentSeries: Identifiable, Codable, Hashable {
    let slug: String
    let name: String
    let description: String
    let articleIds: [String]
    let generatedAt: Date?

    var id: String { slug }

    enum CodingKeys: String, CodingKey {
        case slug, name, description, articleIds, generatedAt
    }

    init(slug: String, name: String, description: String, articleIds: [String], generatedAt: Date?) {
        self.slug = slug
        self.name = name
        self.description = description
        self.articleIds = articleIds
        self.generatedAt = generatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        slug = try container.decode(String.self, forKey: .slug)
        name = try container.decode(String.self, forKey: .name)
        description = try container.decode(String.self, forKey: .description)
        articleIds = try container.decode([String].self, forKey: .articleIds)
        if let timestamp = try? container.decode(Timestamp.self, forKey: .generatedAt) {
            generatedAt = timestamp.dateValue()
        } else {
            generatedAt = try? container.decode(Date.self, forKey: .generatedAt)
        }
    }
}

@MainActor
final class SeriesService: ObservableObject {
    static let shared = SeriesService()

    nonisolated let objectWillChange = ObservableObjectPublisher()
    private(set) var series: [ContentSeries] = []
    private(set) var isLoading = false
    private(set) var errorMessage: String?

    typealias CurrentGuard = @MainActor () -> Bool
    typealias Transport = @MainActor (@escaping CurrentGuard) async throws -> [ContentSeries]

    // Construction is inert. Merely observing the shared service must not
    // instantiate Firestore before the caller's startup/account gate allows it.
    private lazy var db = Firestore.firestore()
    private let transport: Transport?
    private var operationID: UUID?

    init(transport: Transport? = nil) {
        self.transport = transport
    }

    func fetchSeries(stillCurrent: @escaping CurrentGuard = { true }) async {
        guard !Task.isCancelled, stillCurrent(), operationID == nil else { return }
        let operation = UUID()
        operationID = operation
        objectWillChange.send()
        isLoading = true
        defer {
            // Only the operation which owns the physical await can retire its
            // busy state, including a stale/cancelled result after account change.
            if operationID == operation {
                operationID = nil
                objectWillChange.send()
                isLoading = false
            }
        }
        guard !Task.isCancelled, stillCurrent(), operationID == operation else { return }
        guard publish(operation: operation, stillCurrent: stillCurrent, commit: {
            self.errorMessage = nil
        }) else { return }
        do {
            let loaded: [ContentSeries]
            if let transport {
                loaded = try await transport(stillCurrent)
            } else {
                loaded = try await loadSeries(stillCurrent: stillCurrent)
            }
            let sorted = loaded.sorted { ($0.generatedAt ?? .distantPast) > ($1.generatedAt ?? .distantPast) }
            publish(operation: operation, stillCurrent: stillCurrent) {
                self.series = sorted
            }
        } catch {
            guard !Task.isCancelled, stillCurrent(), operationID == operation else { return }
            guard !(error is CancellationError) else { return }
            let message = error.localizedDescription
            publish(operation: operation, stillCurrent: stillCurrent) {
                self.errorMessage = message
            }
        }
    }

    /// An ObservableObject subscriber can synchronously change the account.
    /// Commit only after that notification and a fresh original-owner check;
    /// @Published's willSet would otherwise assign the stale value afterwards.
    @discardableResult
    private func publish(operation: UUID, stillCurrent: CurrentGuard, commit: () -> Void) -> Bool {
        guard stillCurrent(), !Task.isCancelled, operationID == operation else { return false }
        objectWillChange.send()
        guard stillCurrent(), !Task.isCancelled, operationID == operation else { return false }
        commit()
        return true
    }

    private func loadSeries(stillCurrent: @escaping CurrentGuard) async throws -> [ContentSeries] {
        guard !Task.isCancelled, stillCurrent() else { throw CancellationError() }
        let client = db
        guard !Task.isCancelled, stillCurrent() else { throw CancellationError() }
        let reference = client.collection("series")
        guard !Task.isCancelled, stillCurrent() else { throw CancellationError() }
        let snapshot = try await reference.getDocuments()
        guard !Task.isCancelled, stillCurrent() else { throw CancellationError() }
        let loaded = snapshot.documents.compactMap { document -> ContentSeries? in
            try? document.data(as: ContentSeries.self)
        }
        guard !Task.isCancelled, stillCurrent() else { throw CancellationError() }
        return loaded
    }
}
