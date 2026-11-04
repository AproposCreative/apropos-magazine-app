import Foundation

/// Shared by production and tests: one coherent captured source set, with
/// independent accepted revisions. Progress, loading and player clocks are not
/// inputs. No SDK, cache, storage, player or timer is created here.
@MainActor
final class HomeFeedInputReceiver {
    private(set) var authority = HomeFeedAuthority()
    private var accepted: HomeFeedInput?
    private var owner: UUID?
    private var availability: UUID?
    private struct Name: Equatable { let id: String; let name: String }

    func receive(articles: [Article], topics: [Topic], sections: [WebflowSection], authors: [Author],
                 episodes: [PodcastEpisode], recommendations: [HomeRecommendation],
                 owner: UUID, recommendationOwner: UUID? = nil, availability: UUID, now: Date) -> HomeFeedInput {
        let recommendations = recommendationOwner == owner ? recommendations : []
        let previous = accepted
        let ownerChanged = self.owner != owner
        let value = HomeFeedAuthority(
            content: previous?.articles == articles ? authority.content : UUID(),
            metadata: previous?.topics.map { Name(id: $0.id, name: $0.name) } == topics.map { Name(id: $0.id, name: $0.name) }
                && previous?.sections.map { Name(id: $0.id, name: $0.name) } == sections.map { Name(id: $0.id, name: $0.name) }
                && previous?.authors.map { Name(id: $0.id, name: $0.name) } == authors.map { Name(id: $0.id, name: $0.name) }
                ? authority.metadata : UUID(),
            recommendations: !ownerChanged && previous?.recommendations == recommendations ? authority.recommendations : UUID(),
            episodes: previous?.episodes == episodes ? authority.episodes : UUID(),
            availability: self.availability == availability ? authority.availability : UUID(),
            owner: ownerChanged ? UUID() : authority.owner)
        authority = value
        self.owner = owner
        self.availability = availability
        let result = HomeFeedInput(authority: value, articles: articles, topics: topics, sections: sections,
                                   authors: authors, episodes: episodes, recommendations: recommendations, now: now)
        accepted = result
        return result
    }
    func isCurrent(_ original: HomeFeedAuthority) -> Bool { original == authority }
    func isCurrent(_ original: HomeFeedAuthority, owner: UUID) -> Bool { original == authority && self.owner == owner }
}
