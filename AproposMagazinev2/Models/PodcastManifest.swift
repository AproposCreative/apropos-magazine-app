import Foundation

struct PodcastManifest: Decodable {
    let version: Int
    let updatedAt: Date?
    let episodes: [PodcastManifestEntry]

    enum CodingKeys: String, CodingKey {
        case version
        case updatedAt
        case episodes
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decodeIfPresent(Int.self, forKey: .version) ?? 1
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt)
        episodes = try container.decode([PodcastManifestEntry].self, forKey: .episodes)
    }
}

struct PodcastManifestEntry: Decodable {
    let id: String
    let articleSlug: String
    let title: String
    let subtitle: String?
    let audioURL: String
    let hosts: [String]
    let publishedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case articleSlug
        case slug
        case title
        case subtitle
        case audioURL
        case audioUrl
        case hosts
        case publishedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        let slugFromDashboard = try container.decodeIfPresent(String.self, forKey: .slug)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let slugFromLegacy = try container.decodeIfPresent(String.self, forKey: .articleSlug)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedSlug = Self.firstNonEmpty(slugFromLegacy, slugFromDashboard) ?? ""

        let decodedId = try container.decodeIfPresent(String.self, forKey: .id)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        id = Self.firstNonEmpty(decodedId, resolvedSlug) ?? UUID().uuidString

        articleSlug = resolvedSlug.isEmpty ? id : resolvedSlug
        title = try container.decode(String.self, forKey: .title)
        subtitle = try container.decodeIfPresent(String.self, forKey: .subtitle)

        let legacyAudioURL = try container.decodeIfPresent(String.self, forKey: .audioURL)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let dashboardAudioURL = try container.decodeIfPresent(String.self, forKey: .audioUrl)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        audioURL = Self.firstNonEmpty(legacyAudioURL, dashboardAudioURL) ?? ""

        hosts = try container.decodeIfPresent([String].self, forKey: .hosts) ?? []
        publishedAt = try container.decodeIfPresent(Date.self, forKey: .publishedAt)
    }

    func toEpisode() -> PodcastEpisode? {
        guard let url = URL(string: audioURL.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            return nil
        }

        return PodcastEpisode(
            id: id,
            articleId: nil,
            articleSlug: articleSlug,
            title: title,
            subtitle: subtitle ?? "Lyt til artiklen",
            audioURL: url,
            productionSourceURL: nil,
            duration: nil,
            artworkURL: nil,
            hosts: hosts.isEmpty ? ["Apropos Magazine"] : hosts,
            publishedDate: publishedAt
        )
    }

    private static func firstNonEmpty(_ candidates: String?...) -> String? {
        for candidate in candidates {
            if let candidate, !candidate.isEmpty {
                return candidate
            }
        }
        return nil
    }
}
