import Combine
import XCTest
@testable import Apropos

/// Exercises the actual catalog publication boundary with a local manifest,
/// real membership leases and a pin spy. No shared repository, SDK or player.
@MainActor
final class SavedAudioCatalogIntegrationTests: XCTestCase {
    @MainActor private final class Signal {
        private var signaled = false
        private var waiters: [CheckedContinuation<Void, Never>] = []
        func wait() async {
            guard !signaled else { return }
            await withCheckedContinuation { waiters.append($0) }
        }
        func signal() {
            signaled = true
            let pending = waiters; waiters.removeAll()
            pending.forEach { $0.resume() }
        }
    }

    @MainActor private final class HeldManifest {
        let started = Signal()
        private(set) var requests: [URLRequest] = []
        private var result: Data?
        private var waiters: [CheckedContinuation<(Data, URLResponse), Error>] = []
        func fetch(_ request: URLRequest) async throws -> (Data, URLResponse) {
            requests.append(request); started.signal()
            if let result { return response(result, url: request.url!) }
            return try await withCheckedThrowingContinuation { waiters.append($0) }
        }
        func complete(_ data: Data) {
            result = data
            let pending = waiters; waiters.removeAll()
            let url = requests.first!.url!
            pending.forEach { $0.resume(returning: response(data, url: url)) }
        }
        private func response(_ data: Data, url: URL) -> (Data, URLResponse) {
            (data, HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
    }

    private struct Pin: Hashable {
        let key: String
        let lease: UUID
        let asset: PodcastAudioAsset
    }
    @MainActor private final class Retry {
        let delay: TimeInterval
        let work: @MainActor () -> Void
        var cancelled = false
        init(delay: TimeInterval, work: @escaping @MainActor () -> Void) {
            self.delay = delay; self.work = work
        }
    }
    @MainActor private final class Memory {
        var records: [FavoritesNamespace: FavoritesRecord] = [:]
        var bodies: [String: Article] = [:]
    }
    private enum Failure: Error { case staleRecord }

    @MainActor private final class Harness {
        let articleAvailability = ArticleAvailabilityModel(schedule: { _ in {} })
        let memory = Memory()
        lazy var audioAvailability = PodcastAvailabilityModel(
            approvedRevision: { [articleAvailability] in articleAvailability.approvedRevision(for: $0) },
            wasInvalidated: { [articleAvailability] in articleAvailability.wasInvalidated($0) })
        lazy var model = FavoritesModel(storage: .init(read: { [memory] namespace, completion in
            completion(.success(memory.records[namespace]))
        }, write: { [memory] namespace, record, expected, completion in
            guard memory.records[namespace]?.recordRevision == expected else {
                completion(.failure(Failure.staleRecord)); return
            }
            memory.records[namespace] = record; completion(.success(()))
        }))
        var repository: PodcastRepository?
        var retries: [Retry] = []
        var firedRetryCount = 0
        var pinAttempts: [Pin] = []
        var releases: [Pin] = []
        var physicalStarts: [Pin] = []
        var pendingPins = Set<Pin>()
        var capturedTicketBatches: [[FavoritesOfflineCoordinator.AccessTicket]] = []
        var submittedTicketBatches: [[FavoritesOfflineCoordinator.AccessTicket]] = []
        var catalogNotifications = 0
        lazy var offline = FavoritesOfflineCoordinator(model: model, requiresAccount: true,
            storage: .init(read: { [memory] in memory.bodies[$0] },
                           write: { [memory] in memory.bodies[$0] = $1 }),
            permitsBody: { [articleAvailability] in articleAvailability.permitsBody($0) },
            effects: .init(cacheImages: { _, _ in },
                audioAsset: { [weak self] in self?.repository?.audioAsset(for: $0) },
                audioIsCached: { _ in false },
                pinAudio: { [weak self] key, lease, asset in self?.pin(key: key, lease: lease, asset: asset) },
                releaseAudio: { [weak self] key, lease, asset in
                    let pin = Pin(key: key, lease: lease, asset: asset)
                    self?.releases.append(pin); self?.pendingPins.remove(pin)
                },
                scheduleRetry: { [weak self] delay, work in
                    let retry = Retry(delay: delay, work: work)
                    self?.retries.append(retry)
                    return { retry.cancelled = true }
                }))

        func select(_ uid: String) {
            model.changeContext(to: .confirmed(userID: uid))
            offline.synchronizeCurrentMembership()
        }
        func prime(_ articles: [Article]) {
            articleAvailability.trackPublicationIDs(Set(articles.map(\.id)))
            articleAvailability.recordPublications(articles, ticket: articleAvailability.beginRead())
            audioAvailability.recordIdentities(articles.map { ($0.id, $0.slug) })
        }
        func save(_ article: Article) throws -> FavoritesOfflineCoordinator.AccessTicket {
            _ = model.setFavorite(article, enabled: true)
            offline.synchronizeCurrentMembership()
            return try XCTUnwrap(offline.captureAccess(articleID: article.id))
        }
        func remove(_ article: Article) {
            _ = model.setFavorite(article, enabled: false)
            offline.synchronizeCurrentMembership()
        }
        func expireFiniteRetries() {
            // Advance only the injected finite timer, not wall-clock or network.
            let pending = retries; retries.removeAll()
            for retry in pending where !retry.cancelled {
                XCTAssertEqual(retry.delay, 2)
                firedRetryCount += 1; retry.work()
            }
            XCTAssertTrue(retries.isEmpty, "The one missing-catalog retry must not schedule another retry")
        }
        func makeRepository(_ service: PodcastManifestService) -> PodcastRepository {
            var effects = PodcastRepository.Effects(availability: audioAvailability)
            effects.trackEpisodes = { [weak self] episodes in
                self?.articleAvailability.trackPublicationIDs(Set(episodes.filter(\.isAINarration).compactMap(\.articleId)))
            }
            effects.recordArticles = { [weak self] articles in
                self?.audioAvailability.recordIdentities(articles.map { ($0.id, $0.slug) })
            }
            effects.permitsArticle = { [weak self] in self?.articleAvailability.permitsBody($0) == true }
            effects.currentSavedTickets = { [weak self] in
                guard let self else { return [] }
                let tickets = self.offline.currentAccessTickets
                self.capturedTicketBatches.append(tickets)
                return tickets
            }
            effects.saveSavedTickets = { [weak self] tickets in
                guard let self else { return }
                self.submittedTicketBatches.append(tickets)
                tickets.forEach { _ = self.offline.cacheAudio($0) }
            }
            effects.catalogDidChange = { [weak self] in
                guard let self else { return }
                self.catalogNotifications += 1
                self.offline.synchronizeCurrentMembership()
            }
            let repository = PodcastRepository(manifestService: service, initialEpisodes: [], effects: effects)
            self.repository = repository
            return repository
        }
        private func pin(key: String, lease: UUID, asset: PodcastAudioAsset) {
            let current = offline.currentAccessTickets
            XCTAssertTrue(current.contains { $0.pinKey == key && $0.leaseID == lease && $0.articleID == asset.canonicalArticleID },
                          "Every pin must belong to the current actual membership lease")
            let pin = Pin(key: key, lease: lease, asset: asset)
            pinAttempts.append(pin)
            // Model only transport coalescing, never completed audio bytes.
            if pendingPins.insert(pin).inserted { physicalStarts.append(pin) }
        }
    }

    private let manifestURL = URL(string: "https://fixtures.example.invalid/saved-catalog.json")!
    private func cachePath() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("saved-audio-catalog-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return directory.appendingPathComponent("manifest.json")
    }
    private func article(_ id: String = "saved-story") -> Article {
        Article(id: id, name: "Saved story", slug: id, content: "<p>Local article.</p>", intro: "", topicID: "music",
                isDraft: false, lastPublished: "2026-11-01T08:00:00Z",
                contentRevision: "cms-sha256-v1:" + String(repeating: "a", count: 64))
    }
    private func payload(_ articles: [Article], legacy: Bool = false) throws -> Data {
        let rows: [[String: Any]] = articles.map { article in
            var row: [String: Any] = ["id": "ai-" + article.id, "slug": article.slug!, "title": article.name,
                "audioUrl": "https://fixtures.example.invalid/" + article.id + ".m4a", "kind": "ai"]
            if !legacy { row["articleId"] = article.id; row["sourceContentRevision"] = article.bodyRevision! }
            return row
        }
        return try JSONSerialization.data(withJSONObject: ["version": 1, "episodes": rows])
    }
    private func service(_ transport: HeldManifest, cache: URL) -> PodcastManifestService {
        PodcastManifestService(manifestURL: manifestURL, cacheURL: cache, fallbackEpisodes: [],
                               fetch: { try await transport.fetch($0) })
    }

    func testSaveDuringHeldManifestAfterFiniteRetryPinsCurrentAssetOnPublication() async throws {
        let h = Harness(), story = article(), transport = HeldManifest()
        h.prime([story]); h.select("A")
        let repo = h.makeRepository(service(transport, cache: try cachePath()))
        let refresh = Task { await repo.refreshManifest(force: true, allowPrefetch: false) }
        await transport.started.wait()
        XCTAssertTrue(h.capturedTicketBatches.first?.isEmpty == true)
        let member = try h.save(story)
        h.expireFiniteRetries()
        XCTAssertEqual(h.firedRetryCount, 1); XCTAssertTrue(h.physicalStarts.isEmpty)
        XCTAssertNil(repo.audioAsset(for: story))
        transport.complete(try payload([story])); await refresh.value
        XCTAssertEqual(repo.episodes.map(\.id), ["ai-saved-story"])
        let asset = try XCTUnwrap(repo.audioAsset(for: story))
        XCTAssertEqual(h.physicalStarts, [.init(key: member.pinKey, lease: member.leaseID, asset: asset)],
                       "Publishing the delayed catalog must start the exact current saved asset without another Save")
        XCTAssertTrue(h.offline.isCurrent(member))
        XCTAssertFalse(h.offline.audioDownloaded(articleID: story.id), "A pin request is not completed audio")
        XCTAssertEqual(transport.requests.count, 1)
    }

    func testCachedHydrationReconcilesExistingSavedMemberWithoutNewSave() async throws {
        let h = Harness(), story = article(), transport = HeldManifest(), path = try cachePath()
        h.prime([story]); h.select("A")
        let member = try h.save(story); h.expireFiniteRetries()
        try payload([story]).write(to: path)
        let repo = h.makeRepository(service(transport, cache: path))
        let published = expectation(description: "Actual cached repository catalog is published")
        var fulfilled = false
        let observation = repo.changes.sink { snapshot in
            if !fulfilled, snapshot.episodes.map(\.id) == ["ai-saved-story"] {
                fulfilled = true; published.fulfill()
            }
        }
        await fulfillment(of: [published], timeout: 3)
        let asset = try XCTUnwrap(repo.audioAsset(for: story))
        XCTAssertEqual(h.physicalStarts, [.init(key: member.pinKey, lease: member.leaseID, asset: asset)])
        XCTAssertTrue(transport.requests.isEmpty, "Cached hydration never starts the transport")
        XCTAssertFalse(h.offline.audioDownloaded(articleID: story.id))
        withExtendedLifetime(observation) {}
    }

    func testLateCatalogAfterAccountSwitchReconcilesOnlyCurrentOwner() async throws {
        let h = Harness(), oldStory = article("old-story"), currentStory = article("current-story"), transport = HeldManifest()
        h.prime([oldStory, currentStory]); h.select("A")
        let old = try h.save(oldStory); h.expireFiniteRetries()
        let repo = h.makeRepository(service(transport, cache: try cachePath()))
        let refresh = Task { await repo.refreshManifest(force: true, allowPrefetch: false) }
        await transport.started.wait()
        h.select("B"); let current = try h.save(currentStory); h.expireFiniteRetries()
        XCTAssertFalse(h.offline.isCurrent(old)); XCTAssertTrue(h.physicalStarts.isEmpty)
        transport.complete(try payload([oldStory, currentStory])); await refresh.value
        let asset = try XCTUnwrap(repo.audioAsset(for: currentStory))
        XCTAssertEqual(h.physicalStarts, [.init(key: current.pinKey, lease: current.leaseID, asset: asset)])
        XCTAssertFalse(h.pinAttempts.contains { $0.lease == old.leaseID })
        XCTAssertEqual(h.model.snapshot.articles.map(\.id), [currentStory.id])
        XCTAssertFalse(h.offline.audioDownloaded(articleID: currentStory.id))
    }

    func testRemovedMembershipCannotBePinnedByLateCatalog() async throws {
        let h = Harness(), story = article(), transport = HeldManifest()
        h.prime([story]); h.select("A")
        let member = try h.save(story); h.expireFiniteRetries()
        let repo = h.makeRepository(service(transport, cache: try cachePath()))
        let refresh = Task { await repo.refreshManifest(force: true, allowPrefetch: false) }
        await transport.started.wait()
        h.remove(story)
        transport.complete(try payload([story])); await refresh.value
        XCTAssertNotNil(repo.audioAsset(for: story), "Public catalog validity alone never restores private membership")
        XCTAssertFalse(h.offline.isCurrent(member)); XCTAssertTrue(h.offline.currentAccessTickets.isEmpty)
        XCTAssertTrue(h.pinAttempts.isEmpty); XCTAssertTrue(h.physicalStarts.isEmpty)
        XCTAssertFalse(h.offline.audioDownloaded(articleID: story.id))
    }

    func testRepeatedCatalogPublicationCoalescesCurrentAssetWithoutClaimingOffline() async throws {
        let h = Harness(), story = article(), transport = HeldManifest()
        h.prime([story]); h.select("A")
        let member = try h.save(story); h.expireFiniteRetries()
        let repo = h.makeRepository(service(transport, cache: try cachePath()))
        let first = Task { await repo.refreshManifest(force: true, allowPrefetch: false) }
        await transport.started.wait()
        transport.complete(try payload([story])); await first.value
        let asset = try XCTUnwrap(repo.audioAsset(for: story))
        await repo.refreshManifest(force: true, allowPrefetch: false)
        await repo.refreshManifest(force: true, allowPrefetch: false)
        XCTAssertEqual(h.physicalStarts, [.init(key: member.pinKey, lease: member.leaseID, asset: asset)])
        XCTAssertTrue(h.pinAttempts.allSatisfy { $0.lease == member.leaseID && $0.asset == asset })
        XCTAssertEqual(transport.requests.count, 3)
        XCTAssertFalse(h.offline.audioDownloaded(articleID: story.id))
    }

    func testLegacyCatalogHydrationNeverInventsSourceBoundOfflineAsset() async throws {
        let h = Harness(), story = article(), transport = HeldManifest()
        h.prime([story]); h.select("A")
        let member = try h.save(story); h.expireFiniteRetries()
        let repo = h.makeRepository(service(transport, cache: try cachePath()))
        let refresh = Task { await repo.refreshManifest(force: true, allowPrefetch: false) }
        await transport.started.wait()
        transport.complete(try payload([story], legacy: true)); await refresh.value
        XCTAssertEqual(repo.episodes.count, 1, "Legacy streaming remains discoverable")
        let raw = try XCTUnwrap(repo.episodes.first)
        let asset = try XCTUnwrap(repo.audioAsset(for: story))
        XCTAssertEqual(asset.binding, .acceptedRecording(articleID: nil, articleSlug: story.slug))
        XCTAssertNil(raw.sourceContentRevision); XCTAssertNil(asset.sourceRevision)
        XCTAssertEqual(asset.canonicalArticleID, story.id); XCTAssertEqual(asset.remoteURL, raw.audioURL)
        XCTAssertEqual(h.physicalStarts, [.init(key: member.pinKey, lease: member.leaseID, asset: asset)])
        XCTAssertFalse(h.pinAttempts.isEmpty)
        XCTAssertTrue(h.pinAttempts.allSatisfy { $0.key == member.pinKey && $0.lease == member.leaseID && $0.asset == asset })
        // This harness observes/coalesces real pin admission, never audio bytes.
        XCTAssertFalse(h.offline.audioDownloaded(articleID: story.id))
    }
}
