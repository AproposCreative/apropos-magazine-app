import Foundation

/// Tap-time catalog validation uses the same enrichment as prepared Home. Raw
/// catalog values can omit artwork/articleID. Resume still requires one current
/// playable episode with that ID; a newly ambiguous catalog never borrows an old
/// snapshot's former uniqueness while its replacement is being prepared.
enum HomePodcastAdmission {
    static func rawEpisode(for pair: PodcastArticlePair, in episodes: [PodcastEpisode],
                           requiresUniquePlayableID: Bool) -> PodcastEpisode? {
        let candidates = episodes.filter { $0.id == pair.episode.id && (!requiresUniquePlayableID || $0.hasPlayableAudioURL) }
        if requiresUniquePlayableID, candidates.count != 1 { return nil }
        return candidates.first { $0 == pair.episode || HomePodcastIndex.enriched($0, with: pair.article) == pair.episode }
    }
}
