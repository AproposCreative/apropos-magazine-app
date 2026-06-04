import Foundation

struct PodcastManifest: Codable {
    let version: Int
    let updatedAt: Date
    let episodes: [PodcastManifestEntry]
}

struct PodcastManifestEntry: Codable {
    let id: String
    let articleSlug: String
    let title: String
    let subtitle: String?
    let audioURL: String
    let hosts: [String]
    let publishedAt: Date?

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
}
