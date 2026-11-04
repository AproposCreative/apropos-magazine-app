import XCTest
@testable import Apropos

final class HomeFeedInputReceiverTests: XCTestCase {
    private func article(_ id: String, content: String = "") -> Article {
        Article(id: id, name: id, slug: id, content: content, intro: "", topicID: "topic", isDraft: false,
                createdOn: "2026-01-01T00:00:00Z", lastPublished: "2026-01-01T00:00:00Z", contentRevision: "r1")
    }

    func testResumeAdmissionAcceptsActualEnrichedArtworkAndRejectsNewAmbiguity() {
        let article = Article(id: "story", name: "Story", slug: "story", content: "", intro: "", topicID: "topic",
                              mobileImageURL: URL(string: "https://example.invalid/art.jpg"), isDraft: false,
                              lastPublished: "2026-01-01T00:00:00Z")
        let raw = PodcastEpisode(id: "episode", articleId: "story", articleSlug: nil, title: "Story", subtitle: nil,
            audioURL: URL(string: "https://example.invalid/audio.mp3"), productionSourceURL: nil, duration: nil,
            artworkURL: nil, hosts: [], publishedDate: nil)
        let pair = PodcastArticlePair(article: article, episode: HomePodcastIndex.enriched(raw, with: article))
        XCTAssertNotEqual(raw, pair.episode)
        XCTAssertEqual(HomePodcastAdmission.rawEpisode(for: pair, in: [raw], requiresUniquePlayableID: true), raw)
        XCTAssertNil(HomePodcastAdmission.rawEpisode(for: pair, in: [raw, raw], requiresUniquePlayableID: true))
        XCTAssertNotNil(HomePodcastAdmission.rawEpisode(for: pair, in: [raw, raw], requiresUniquePlayableID: false))
        XCTAssertNil(HomePodcastAdmission.rawEpisode(for: pair, in: [], requiresUniquePlayableID: true))
    }

    @MainActor
    func testActualReceiverRepeatedRenderClockProgressInputsCauseNoArchiveWork() async {
        let receiver = HomeFeedInputReceiver()
        let model = HomeFeedPreparationModel(currentAuthority: { receiver.authority })
        let owner = UUID(), availability = UUID(), now = Date()
        let articles = (1...30).map { article("article-\($0)") }
        func receive(_ date: Date) {
            model.update(receiver.receive(articles: articles, topics: [], sections: [], authors: [], episodes: [],
                recommendations: [], owner: owner, availability: availability, now: date))
        }
        receive(now)
        await model.waitForCurrentWork()
        let baseline = model.snapshot?.metrics
        let publication = model.state.revision
        for tick in 1...100 { receive(now.addingTimeInterval(Double(tick))) }
        await model.waitForCurrentWork()
        XCTAssertEqual(model.snapshot?.metrics, baseline)
        XCTAssertEqual(model.state.revision, publication)
        XCTAssertEqual(baseline?.builds, 1)
    }

    @MainActor
    func testActualReceiverOldRecommendationBindingCannotBecomeNewOwnerInput() async {
        let receiver = HomeFeedInputReceiver()
        let model = HomeFeedPreparationModel(currentAuthority: { receiver.authority })
        let a = UUID(), b = UUID(), availability = UUID(), now = Date()
        let articles = (1...12).map { article("article-\($0)") }
        let recommendation = HomeRecommendation(articleID: "article-2", reason: "A's valg")
        let first = receiver.receive(articles: articles, topics: [], sections: [], authors: [], episodes: [],
            recommendations: [recommendation], owner: a, recommendationOwner: a, availability: availability, now: now)
        model.update(first)
        await model.waitForCurrentWork()
        XCTAssertEqual(model.snapshot?.rail(.recommended).reasonsByID["article-2"], "A's valg")
        let next = receiver.receive(articles: articles, topics: [], sections: [], authors: [], episodes: [],
            recommendations: [recommendation], owner: b, recommendationOwner: a, availability: availability, now: now)
        XCTAssertTrue(next.recommendations.isEmpty)
        model.update(next)
        XCTAssertFalse(receiver.isCurrent(first.authority, owner: b))
        XCTAssertTrue(model.snapshot?.rail(.recommended).reasonsByID.isEmpty == true)
        await model.waitForCurrentWork()
        XCTAssertTrue(model.snapshot?.rail(.recommended).reasonsByID.isEmpty == true)
    }

    @MainActor
    func testUnchangedVisibleMetadataRetainsAuthorityThroughBiographyUpdates() {
        let receiver = HomeFeedInputReceiver()
        let owner = UUID(), availability = UUID(), now = Date()
        func receive(_ bio: String, _ name: String) -> HomeFeedInput {
            receiver.receive(articles: [article("one")], topics: [], sections: [],
                authors: [Author(id: "writer", name: name, bio: bio, imageURL: nil, position: "", photoURL: "")],
                episodes: [], recommendations: [], owner: owner, availability: availability, now: now)
        }
        let original = receive("Old biography", "Writer")
        let biographyOnly = receive("New biography", "Writer")
        XCTAssertEqual(original.authority.metadata, biographyOnly.authority.metadata)
        let newName = receive("New biography", "New name")
        XCTAssertNotEqual(original.authority.metadata, newName.authority.metadata)
    }

    @MainActor
    func testOwnerRoundTripUsesNewGenerationEvenWithSamePublicSources() {
        let receiver = HomeFeedInputReceiver()
        let firstOwner = UUID(), otherOwner = UUID(), availability = UUID(), now = Date()
        func receive(_ owner: UUID) -> HomeFeedInput {
            receiver.receive(articles: [article("one")], topics: [], sections: [], authors: [], episodes: [],
                recommendations: [], owner: owner, availability: availability, now: now)
        }
        let a = receive(firstOwner), b = receive(otherOwner), returned = receive(UUID())
        XCTAssertNotEqual(a.authority.owner, b.authority.owner)
        XCTAssertNotEqual(a.authority.owner, returned.authority.owner)
        XCTAssertEqual(a.authority.content, returned.authority.content)
        XCTAssertFalse(receiver.isCurrent(a.authority))
    }

    @MainActor
    func testAvailabilityRevocationRunsThroughActualReceiverBeforeAwait() async {
        let receiver = HomeFeedInputReceiver()
        let model = HomeFeedPreparationModel(currentAuthority: { receiver.authority })
        let owner = UUID(), now = Date()
        let original = receiver.receive(articles: [article("denied"), article("kept")], topics: [], sections: [],
            authors: [], episodes: [], recommendations: [], owner: owner, availability: UUID(), now: now)
        model.update(original)
        await model.waitForCurrentWork()
        let withdrawal = receiver.receive(articles: [article("kept")], topics: [], sections: [], authors: [],
            episodes: [], recommendations: [], owner: owner, availability: UUID(), now: now)
        model.update(withdrawal)
        XCTAssertFalse(model.snapshot?.hero.contains(where: { $0.id == "denied" }) == true)
        XCTAssertFalse(model.snapshot?.resumeIndex.articlesByID.keys.contains("denied") == true)
        await model.waitForCurrentWork()
        XCTAssertEqual(model.snapshot?.hero.map(\.id), ["kept"])
    }

    @MainActor
    func testDetailBodyChangeDoesNotRepeatSelectionSortOrPodcastMatching() async {
        let receiver = HomeFeedInputReceiver()
        let model = HomeFeedPreparationModel(currentAuthority: { receiver.authority })
        let owner = UUID(), availability = UUID(), now = Date()
        func receive(_ values: [Article]) {
            model.update(receiver.receive(articles: values, topics: [], sections: [], authors: [], episodes: [],
                recommendations: [], owner: owner, availability: availability, now: now))
        }
        receive([article("one")]); await model.waitForCurrentWork()
        let baseline = model.snapshot!.metrics
        receive([article("one", content: "<p>Loaded article body</p>")]); await model.waitForCurrentWork()
        XCTAssertEqual(model.snapshot?.metrics.archiveSorts, baseline.archiveSorts)
        XCTAssertEqual(model.snapshot?.metrics.podcastCandidateChecks, baseline.podcastCandidateChecks)
    }
}
