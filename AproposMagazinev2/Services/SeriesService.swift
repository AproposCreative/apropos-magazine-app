import Foundation
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

    @Published private(set) var series: [ContentSeries] = []
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?

    private let db = Firestore.firestore()

    private init() {}

    func fetchSeries() async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil

        do {
            let snapshot = try await db.collection("series").getDocuments()
            let loaded = snapshot.documents.compactMap { document -> ContentSeries? in
                try? document.data(as: ContentSeries.self)
            }
            series = loaded.sorted { ($0.generatedAt ?? .distantPast) > ($1.generatedAt ?? .distantPast) }
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }
}
