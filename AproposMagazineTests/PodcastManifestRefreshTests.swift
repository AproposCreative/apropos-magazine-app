import XCTest
@testable import Apropos

final class PodcastManifestRefreshTests: XCTestCase {
    private let url = URL(string: "https://fixtures.example.invalid/manifest.json")!
    private let valid = Data("""
    {"episodes":[{"id":"episode-1","slug":"article-1","title":"Fixture","audioUrl":"https://fixtures.example.invalid/episode.mp3"}]}
    """.utf8)

    private func cachePath() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return directory.appendingPathComponent("manifest.json")
    }

    @MainActor
    func testForcedAndNormalRefreshJoinOneInFlightRequest() async throws {
        let transport = SuspendedManifestTransport()
        let service = PodcastManifestService(
            manifestURL: url, cacheURL: try cachePath(), fallbackEpisodes: [],
            fetch: { try await transport.fetch($0) }
        )
        let first = Task { await service.refreshEpisodes(force: true) }
        await transport.firstRequestStarted.wait()

        let forcedJoinerStarted = ManifestRefreshStartSignal()
        let normalJoinerStarted = ManifestRefreshStartSignal()
        let second = Task { @MainActor in
            forcedJoinerStarted.signal()
            return await service.refreshEpisodes(force: true)
        }
        let third = Task { @MainActor in
            normalJoinerStarted.signal()
            return await service.refreshEpisodes()
        }
        // These calls stay on the same actor: after signaling, each joiner
        // enters refresh and suspends there before this test can resume.
        await forcedJoinerStarted.wait()
        await normalJoinerStarted.wait()
        XCTAssertEqual(transport.requests, 1)
        transport.complete(data: valid, url: url)
        let values = await [first.value, second.value, third.value]
        XCTAssertEqual(values.map { $0.map(\.id) }, [["episode-1"], ["episode-1"], ["episode-1"]])
        XCTAssertEqual(transport.requests, 1)
    }

    @MainActor
    func testFreshnessIsReusedButForceAndExpiryRefresh() async throws {
        var time = Date(timeIntervalSince1970: 1_000)
        var requests = 0
        let service = PodcastManifestService(
            manifestURL: url, cacheURL: try cachePath(), fallbackEpisodes: [],
            minimumRefreshInterval: 30, now: { time },
            fetch: { [valid, url] _ in
                requests += 1
                return (valid, HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!)
            }
        )
        _ = await service.refreshEpisodes()
        _ = await service.refreshEpisodes()
        XCTAssertEqual(requests, 1)
        _ = await service.refreshEpisodes(force: true)
        XCTAssertEqual(requests, 2)
        time.addTimeInterval(31)
        _ = await service.refreshEpisodes()
        XCTAssertEqual(requests, 3)
    }

    @MainActor
    func testMalformedResponsePreservesLastGoodDiskCache() async throws {
        let path = try cachePath()
        var data = valid
        let service = PodcastManifestService(
            manifestURL: url, cacheURL: path, fallbackEpisodes: [],
            fetch: { [url] _ in
                (data, HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!)
            }
        )
        let first = await service.refreshEpisodes()
        XCTAssertEqual(first.map(\.id), ["episode-1"])
        for bad in [Data("bad JSON".utf8), Data("{\"episodes\":[{\"title\":false}]}".utf8)] {
            data = bad
            let result = await service.refreshEpisodes(force: true)
            XCTAssertEqual(result.map(\.id), ["episode-1"])
            XCTAssertEqual(try Data(contentsOf: path), valid)
        }
    }

    @MainActor
    func testFailureDoesNotSuppressImmediateRetryWithFreshnessTTL() async throws {
        var requests = 0
        let service = PodcastManifestService(
            manifestURL: url, cacheURL: try cachePath(), fallbackEpisodes: [],
            fetch: { [valid, url] _ in
                requests += 1
                if requests == 1 { throw URLError(.notConnectedToInternet) }
                return (valid, HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!)
            }
        )
        let failed = await service.refreshEpisodes()
        XCTAssertTrue(failed.isEmpty)
        let recovered = await service.refreshEpisodes()
        XCTAssertEqual(recovered.map(\.id), ["episode-1"])
        XCTAssertEqual(requests, 2)
    }
}

@MainActor
private final class ManifestRefreshStartSignal {
    private var didStart = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        guard !didStart else { return }
        await withCheckedContinuation { waiters.append($0) }
    }

    func signal() {
        didStart = true
        let pending = waiters
        waiters = []
        pending.forEach { $0.resume() }
    }
}

/// The injected transport suspends locally; no URLSession or network is created.
@MainActor
private final class SuspendedManifestTransport {
    var requests = 0
    let firstRequestStarted = ManifestRefreshStartSignal()
    private var result: (Data, URLResponse)?
    private var waiters: [CheckedContinuation<(Data, URLResponse), Error>] = []

    func fetch(_ request: URLRequest) async throws -> (Data, URLResponse) {
        requests += 1
        firstRequestStarted.signal()
        if let result { return result }
        return try await withCheckedThrowingContinuation { waiters.append($0) }
    }

    func complete(data: Data, url: URL) {
        let value: (Data, URLResponse) = (data, HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        result = value
        let pending = waiters
        waiters = []
        pending.forEach { $0.resume(returning: value) }
    }
}

extension PodcastManifestRefreshTests {
    @MainActor
    func testValidEmptyManifestClearsDiskAndSurvivesRestartFailureWithoutFallback() async throws {
        let path = try cachePath()
        var data = valid
        let service = PodcastManifestService(manifestURL: url, cacheURL: path, fallbackEpisodes: [], fetch: { [url] _ in
            (data, HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        })
        let first = await service.refreshEpisodes()
        XCTAssertFalse(first.isEmpty)
        data = Data("{\"episodes\":[]}".utf8)
        let empty = await service.refreshCatalog(force: true)
        XCTAssertTrue(empty.isFresh)
        XCTAssertTrue(empty.episodes.isEmpty)
        XCTAssertEqual(try Data(contentsOf: path), data)
        let restarted = PodcastManifestService(manifestURL: url, cacheURL: path, fallbackEpisodes: first,
                                               fetch: { _ in throw URLError(.notConnectedToInternet) })
        let restoredCache = await restarted.cachedEpisodesOffMain()
        XCTAssertNotNil(restoredCache)
        XCTAssertTrue(restoredCache?.isEmpty == true)
        let offline = await restarted.refreshEpisodes()
        XCTAssertTrue(offline.isEmpty)
    }

    @MainActor
    func testMissingOrMalformedCacheIsDistinctFromAnEmptyCatalog() async throws {
        let path = try cachePath()
        let service = PodcastManifestService(manifestURL: nil, cacheURL: path, fallbackEpisodes: [], fetch: { _ in
            XCTFail("No transport expected"); throw URLError(.unknown)
        })
        let missing = await service.cachedEpisodesOffMain()
        XCTAssertNil(missing)
        try Data("bad JSON".utf8).write(to: path)
        let malformed = await service.cachedEpisodesOffMain()
        XCTAssertNil(malformed)
        try Data("{\"episodes\":[]}".utf8).write(to: path)
        let empty = await service.cachedEpisodesOffMain()
        XCTAssertNotNil(empty)
        XCTAssertTrue(empty?.isEmpty == true)
    }

    @MainActor
    func testRefreshGenerationAdvancesOnlyOnNewTransportAndTTLRetainsIt() async throws {
        let service = PodcastManifestService(manifestURL: url, cacheURL: try cachePath(), fallbackEpisodes: [], fetch: { [valid, url] _ in
            (valid, HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        })
        let first = await service.refreshCatalog()
        let cached = await service.refreshCatalog()
        let forced = await service.refreshCatalog(force: true)
        XCTAssertEqual(first.generation, cached.generation)
        XCTAssertGreaterThan(forced.generation, first.generation)
    }
}

extension PodcastManifestRefreshTests {
    @MainActor
    func testDuplicateEpisodeIdentityPreservesLastGoodCatalogAndDisk() async throws {
        let path = try cachePath()
        var payload = valid
        let service = PodcastManifestService(manifestURL: url, cacheURL: path, fallbackEpisodes: [], fetch: { [url] _ in
            (payload, HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        })
        _ = await service.refreshEpisodes()
        let entry = ["id": "duplicate", "slug": "story", "title": "Story", "audioUrl": "https://fixtures.example.invalid/a.mp3"]
        var conflicting = entry
        conflicting["audioUrl"] = "https://fixtures.example.invalid/different.mp3"
        payload = try JSONSerialization.data(withJSONObject: ["episodes": [entry, conflicting]])
        let result = await service.refreshCatalog(force: true)
        XCTAssertFalse(result.isFresh)
        XCTAssertEqual(result.episodes.map(\.id), ["episode-1"])
        XCTAssertEqual(try Data(contentsOf: path), valid)
    }
}

extension PodcastManifestRefreshTests {
    @MainActor
    func testCanonicalPlaceboRepairRestoresDiscoveryWithoutRelaxingDuplicateIdentity() async throws {
        let path = try cachePath()
        let canonicalSlug = "placebo-sluk-telefonen-og-bliv-haengende-lidt-endnu"
        let episodeID = "ai-" + canonicalSlug
        let oldURL = "https://fixtures.example.invalid/old-placebo.m4a"
        let currentURL = "https://fixtures.example.invalid/current-placebo.m4a"
        let title = "Anmeldelse: Placebo i K.B. Hallen – et langt farvel"
        // Public entry shape, with injected local URLs and a fixture article ID.
        // The public catalog supplies no canonical CMS ID or source revision.
        let old: [String: String] = ["id": episodeID,
            "articleSlug": "placebo---sluk-telefonen-og-bliv-haengende-lidt-endnu",
            "title": "Placebo - Sluk telefonen, og bliv hængende lidt endnu",
            "audioURL": oldURL, "kind": "ai", "publishedAt": "2026-10-26T14:37:10.820Z"]
        let current: [String: String] = ["id": episodeID, "articleSlug": canonicalSlug,
            "title": title, "audioURL": currentURL, "kind": "ai", "publishedAt": "2026-10-27T10:25:13.805Z"]
        let article = Article(id: "fixture-placebo", name: title, slug: canonicalSlug,
            content: "Fixture content", intro: "", topicID: "fixture-topic")
        let oldPayload = try JSONSerialization.data(withJSONObject: ["version": 1, "episodes": [old]])
        var payload = oldPayload
        let service = PodcastManifestService(manifestURL: url, cacheURL: path, fallbackEpisodes: [], fetch: { [url] _ in
            (payload, HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        })
        let initial = await service.refreshCatalog()
        XCTAssertTrue(initial.isFresh); XCTAssertEqual(initial.episodes.count, 1)
        XCTAssertNil(PodcastRepository.bestMatch(in: initial.episodes, for: article, requirePlayableAudio: true))
        payload = try JSONSerialization.data(withJSONObject: ["version": 1, "episodes": [current, old]])
        let conflicting = await service.refreshCatalog(force: true)
        XCTAssertFalse(conflicting.isFresh)
        XCTAssertEqual(conflicting.episodes, initial.episodes)
        XCTAssertEqual(try Data(contentsOf: path), oldPayload)
        XCTAssertNil(PodcastRepository.bestMatch(in: conflicting.episodes, for: article, requirePlayableAudio: true))
        // Correct only the producer data: keep the exact current entry, remove the superseded slug.
        let repairedPayload = try JSONSerialization.data(withJSONObject: ["version": 1, "episodes": [current]])
        payload = repairedPayload
        let repaired = await service.refreshCatalog(force: true)
        XCTAssertTrue(repaired.isFresh); XCTAssertEqual(repaired.episodes.count, 1)
        let selected = try XCTUnwrap(PodcastRepository.bestMatch(in: repaired.episodes, for: article, requirePlayableAudio: true))
        XCTAssertEqual(selected.id, episodeID); XCTAssertEqual(selected.articleSlug, canonicalSlug)
        XCTAssertEqual(selected.audioURL?.absoluteString, currentURL); XCTAssertNotEqual(selected.audioURL?.absoluteString, oldURL)
        XCTAssertEqual(selected.isAINarration, true); XCTAssertNil(selected.articleId); XCTAssertNil(selected.sourceContentRevision)
        XCTAssertEqual(try Data(contentsOf: path), repairedPayload)
        let restarted = PodcastManifestService(manifestURL: url, cacheURL: path, fallbackEpisodes: [],
            fetch: { _ in throw URLError(.notConnectedToInternet) })
        let cached = await restarted.refreshCatalog()
        XCTAssertFalse(cached.isFresh)
        XCTAssertEqual(PodcastRepository.bestMatch(in: cached.episodes, for: article, requirePlayableAudio: true), selected)
    }
}

extension PodcastManifestRefreshTests {
    @MainActor
    func testAIProvenancePersistsInActualManifestDiskCacheAcrossColdOfflineRestart() async throws {
        let path = try cachePath()
        let revision = "cms-sha256-v1:" + String(repeating: "a", count: 64)
        let data = try JSONSerialization.data(withJSONObject: ["version": 2, "episodes": [["id": "ai-A", "articleId": "A",
            "slug": "story", "title": "Story", "kind": "ai", "sourceContentRevision": revision,
            "audioUrl": "https://fixtures.example.invalid/a.mp3"]]])
        let service = PodcastManifestService(manifestURL: url, cacheURL: path, fallbackEpisodes: [], fetch: { [url] _ in
            (data, HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        })
        let fresh = await service.refreshEpisodes()
        XCTAssertEqual(fresh.first?.sourceContentRevision, revision)
        let restarted = PodcastManifestService(manifestURL: url, cacheURL: path, fallbackEpisodes: [],
                                               fetch: { _ in throw URLError(.notConnectedToInternet) })
        let cached = await restarted.refreshEpisodes()
        XCTAssertEqual(cached.first?.sourceContentRevision, revision)
        XCTAssertEqual(cached.first?.articleId, "A")
        XCTAssertEqual(cached.first?.isAINarration, true)
        let model = PodcastAvailabilityModel(approvedRevision: { _ in revision })
        model.acceptManifest(cached)
        XCTAssertTrue(model.allows(try XCTUnwrap(cached.first)))
    }
}

extension PodcastManifestRefreshTests {
    private func catalogEntry(_ id: String, title: String = "Story") -> [String: Any] {
        ["id": id, "articleSlug": id, "title": title,
         "audioURL": "https://fixtures.example.invalid/\(id).m4a"]
    }

    private func catalogData(_ rows: [Any]) throws -> Data {
        try JSONSerialization.data(withJSONObject: ["version": 1, "episodes": rows])
    }

    @MainActor
    func testMalformedSiblingDoesNotHideValidCatalogOrItsColdCache() async throws {
        let path = try cachePath()
        var malformedDate = catalogEntry("bad-date")
        malformedDate["publishedAt"] = "not-a-date"
        var malformedHosts = catalogEntry("bad-hosts")
        malformedHosts["hosts"] = 42
        let payload = try catalogData([catalogEntry("first"), malformedDate, NSNull(),
            ["title": "No stable identity"], malformedHosts, catalogEntry("last")])
        let service = PodcastManifestService(manifestURL: url, cacheURL: path, fallbackEpisodes: [], fetch: { [url] _ in
            (payload, HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        })
        let fresh = await service.refreshCatalog()
        XCTAssertTrue(fresh.isFresh)
        XCTAssertEqual(fresh.episodes.map(\.id), ["first", "last"])
        XCTAssertEqual(try Data(contentsOf: path), payload)
        let restarted = PodcastManifestService(manifestURL: url, cacheURL: path, fallbackEpisodes: [],
            fetch: { _ in throw URLError(.notConnectedToInternet) })
        let cached = await restarted.cachedEpisodesOffMain()
        XCTAssertEqual(cached, fresh.episodes)
        let offline = await restarted.refreshCatalog()
        XCTAssertFalse(offline.isFresh)
        XCTAssertEqual(offline.episodes.map(\.id), ["first", "last"])
    }

    @MainActor
    func testMalformedKnownIdentityPoisonsItsWholeGroupInEitherOrder() async throws {
        let path = try cachePath()
        var malformed = catalogEntry("poisoned")
        malformed["title"] = false
        let good = catalogEntry("poisoned")
        var payload = try catalogData([good, malformed, catalogEntry("unrelated")])
        let service = PodcastManifestService(manifestURL: url, cacheURL: path, fallbackEpisodes: [], fetch: { [url] _ in
            (payload, HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        })
        for rows in [[good, malformed, catalogEntry("unrelated")], [malformed, good, catalogEntry("unrelated")]] {
            payload = try catalogData(rows)
            let result = await service.refreshCatalog(force: true)
            XCTAssertTrue(result.isFresh)
            XCTAssertEqual(result.episodes.map(\.id), ["unrelated"], "A decode failure must not hide the duplicate conflict")
        }
        let restarted = PodcastManifestService(manifestURL: nil, cacheURL: path, fallbackEpisodes: [],
            fetch: { _ in XCTFail("No network expected"); throw URLError(.unknown) })
        let cached = await restarted.cachedEpisodesOffMain()
        XCTAssertEqual(cached?.map(\.id), ["unrelated"])
    }

    @MainActor
    func testConflictingDuplicateFieldsNeverSelectEitherRecording() async throws {
        let path = try cachePath()
        let original = catalogEntry("conflict")
        var payload = valid
        let service = PodcastManifestService(manifestURL: url, cacheURL: path, fallbackEpisodes: [], fetch: { [url] _ in
            (payload, HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        })
        for (field, value) in [("audioURL", "https://fixtures.example.invalid/replacement.m4a"),
                               ("title", "Changed title"), ("kind", "ai"),
                               ("articleId", "another-owner"), ("sourceContentRevision", "updated:other")] {
            var conflict = original
            conflict[field] = value
            payload = try catalogData([original, catalogEntry("unrelated"), conflict])
            let result = await service.refreshCatalog(force: true)
            XCTAssertTrue(result.isFresh, field)
            XCTAssertEqual(result.episodes.map(\.id), ["unrelated"], field)
        }
    }

    @MainActor
    func testIdenticalFullEpisodeDuplicatesCollapseAndSurviveColdCache() async throws {
        let path = try cachePath()
        var repeated = catalogEntry("repeated")
        repeated["hosts"] = ["A", "B"]
        repeated["publishedAt"] = "2026-10-27T10:25:13.805Z"
        let payload = try catalogData([repeated, catalogEntry("second"), repeated])
        let service = PodcastManifestService(manifestURL: url, cacheURL: path, fallbackEpisodes: [], fetch: { [url] _ in
            (payload, HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        })
        let result = await service.refreshCatalog()
        XCTAssertTrue(result.isFresh)
        XCTAssertEqual(result.episodes.map(\.id), ["repeated", "second"])
        XCTAssertEqual(result.episodes.first?.hosts, ["A", "B"])
        let restarted = PodcastManifestService(manifestURL: url, cacheURL: path, fallbackEpisodes: [],
            fetch: { _ in throw URLError(.notConnectedToInternet) })
        let cached = await restarted.refreshCatalog()
        XCTAssertFalse(cached.isFresh)
        XCTAssertEqual(cached.episodes, result.episodes)
    }

    @MainActor
    func testEntirelyRejectedNonemptyCatalogRetainsLastGoodAndAllowsImmediateRepair() async throws {
        let path = try cachePath()
        var payload = valid
        let service = PodcastManifestService(manifestURL: url, cacheURL: path, fallbackEpisodes: [],
            minimumRefreshInterval: 0, fetch: { [url] _ in
                (payload, HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!)
            })
        let original = await service.refreshCatalog()
        var conflict = catalogEntry("duplicate")
        conflict["audioURL"] = "https://fixtures.example.invalid/different.m4a"
        let rejectedRows: [[Any]] = [[NSNull(), ["title": false]], [catalogEntry("duplicate"), conflict]]
        for rows in rejectedRows {
            payload = try catalogData(rows)
            let rejected = await service.refreshCatalog()
            XCTAssertFalse(rejected.isFresh)
            XCTAssertEqual(rejected.episodes, original.episodes)
            XCTAssertEqual(try Data(contentsOf: path), valid)
        }
        payload = try catalogData([catalogEntry("repaired"), ["title": false]])
        let repaired = await service.refreshCatalog()
        XCTAssertTrue(repaired.isFresh)
        XCTAssertEqual(repaired.episodes.map(\.id), ["repaired"])
    }

    @MainActor
    func testPerEntryIsolationDoesNotAcceptMalformedOrUnsupportedEnvelope() async throws {
        let path = try cachePath()
        var payload = valid
        let service = PodcastManifestService(manifestURL: url, cacheURL: path, fallbackEpisodes: [], fetch: { [url] _ in
            (payload, HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        })
        let original = await service.refreshCatalog()
        let envelopes: [Any] = [[], ["episodes": NSNull()], ["episodes": "not-an-array"],
            ["version": "1", "episodes": [catalogEntry("new")]],
            ["version": 999, "episodes": [catalogEntry("new")]],
            ["updatedAt": "not-a-date", "episodes": [catalogEntry("new")]]]
        for envelope in envelopes {
            payload = try JSONSerialization.data(withJSONObject: envelope)
            let result = await service.refreshCatalog(force: true)
            XCTAssertFalse(result.isFresh)
            XCTAssertEqual(result.episodes, original.episodes)
            XCTAssertEqual(try Data(contentsOf: path), valid)
        }
    }

    @MainActor
    func testOversizedCatalogCannotReplaceLastGoodCache() async throws {
        let path = try cachePath()
        var payload = valid
        let service = PodcastManifestService(manifestURL: url, cacheURL: path, fallbackEpisodes: [], fetch: { [url] _ in
            (payload, HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        })
        let original = await service.refreshCatalog()
        let tooManyRows = try catalogData((0..<4_097).map { catalogEntry("row-\($0)") })
        let oversizedBytes = try catalogData([catalogEntry("oversized", title: String(repeating: "a", count: 8 * 1_024 * 1_024))])
        for data in [tooManyRows, oversizedBytes] {
            payload = data
            let result = await service.refreshCatalog(force: true)
            XCTAssertFalse(result.isFresh)
            XCTAssertEqual(result.episodes, original.episodes)
            XCTAssertEqual(try Data(contentsOf: path), valid)
        }
    }

    @MainActor
    func testIsolatedCatalogDoesNotInventLegacyOrMalformedAIOfflineProvenance() async throws {
        var legacy = catalogEntry("legacy-ai")
        legacy["kind"] = "ai"
        var partial = catalogEntry("partial-ai")
        partial["kind"] = "ai"
        partial["articleId"] = "partial-owner"
        var malformedSource = catalogEntry("malformed-ai")
        malformedSource["kind"] = "ai"
        malformedSource["articleId"] = "malformed-owner"
        malformedSource["sourceContentRevision"] = "bad-declared-source"
        var revisionWithoutID = catalogEntry("without-id-ai")
        revisionWithoutID["kind"] = "ai"
        revisionWithoutID["sourceContentRevision"] = "cms-sha256-v1:" + String(repeating: "a", count: 64)
        let payload = try catalogData([legacy, partial, malformedSource, revisionWithoutID, ["id": "bad", "title": false]])
        let service = PodcastManifestService(manifestURL: url, cacheURL: try cachePath(), fallbackEpisodes: [], fetch: { [url] _ in
            (payload, HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        })
        let result = await service.refreshCatalog()
        XCTAssertTrue(result.isFresh)
        let model = PodcastAvailabilityModel()
        model.acceptManifest(result.episodes)
        model.recordIdentities([("legacy-owner", "legacy-ai"), ("partial-owner", "partial-ai"),
            ("malformed-owner", "malformed-ai"), ("missing-id-owner", "without-id-ai")])
        let legacyEpisode = try XCTUnwrap(result.episodes.first { $0.id == "legacy-ai" })
        let partialEpisode = try XCTUnwrap(result.episodes.first { $0.id == "partial-ai" })
        XCTAssertTrue(model.allows(legacyEpisode), "Accepted legacy narration remains online-compatible")
        XCTAssertTrue(PodcastPlaybackPolicy.canStart(playbackURL: try XCTUnwrap(legacyEpisode.audioURL), isOnline: true))
        let legacyAsset = try XCTUnwrap(model.audioAsset(for: legacyEpisode))
        XCTAssertEqual(legacyAsset.binding, .acceptedRecording(articleID: nil, articleSlug: "legacy-ai"))
        XCTAssertEqual(legacyAsset.canonicalArticleID, "legacy-owner")
        XCTAssertEqual(legacyAsset.remoteURL, legacyEpisode.audioURL)
        XCTAssertNil(legacyEpisode.sourceContentRevision); XCTAssertNil(legacyAsset.sourceRevision)
        XCTAssertTrue(model.allows(partialEpisode), "A raw canonical recording association is separate from producer source proof")
        let partialAsset = try XCTUnwrap(model.audioAsset(for: partialEpisode))
        XCTAssertEqual(partialAsset.binding, .acceptedRecording(articleID: "partial-owner", articleSlug: "partial-ai"))
        XCTAssertEqual(partialAsset.canonicalArticleID, "partial-owner")
        XCTAssertEqual(partialAsset.remoteURL, partialEpisode.audioURL)
        XCTAssertNil(partialEpisode.sourceContentRevision); XCTAssertNil(partialAsset.sourceRevision)
        XCTAssertFalse(PodcastPlaybackPolicy.canStart(playbackURL: legacyAsset.remoteURL, isOnline: false), "A descriptor is not downloaded bytes")
        XCTAssertFalse(result.episodes.contains { $0.id == "bad" }, "The malformed row remains isolated")
        for id in ["malformed-ai", "without-id-ai"] {
            let invalid = try XCTUnwrap(result.episodes.first { $0.id == id })
            XCTAssertNotNil(invalid.sourceContentRevision)
            XCTAssertFalse(model.allows(invalid), "A declared bad or unbound source must not downgrade to recording-only")
            XCTAssertNil(model.audioAsset(for: invalid))
        }
    }

    @MainActor
    func testLatestArticlesRemainDiscoverableBesideReintroducedPlaceboConflict() async throws {
        // Public 2026-10-28 schema and identities; every media/artwork URL is
        // replaced with a local fixture endpoint. No public download tokens.
        let terminalSlug = "anmeldelse-the-terminal-list-saeson-1"
        let bookSlug = "anmeldelse-nogen-der-kender-nogen-laura-ringo"
        let placeboSlug = "placebo-sluk-telefonen-og-bliv-haengende-lidt-endnu"
        func publicShape(slug: String, title: String, host: String, date: String,
                         duration: Int, bytes: Int) -> [String: Any] {
            ["id": "ai-" + slug, "articleSlug": slug, "title": title, "subtitle": "Lyt til artiklen",
             "audioURL": "https://fixtures.example.invalid/\(slug).m4a", "hosts": [host],
             "publishedAt": date, "kind": "ai", "guid": "ai-" + slug,
             "imageURL": "https://fixtures.example.invalid/show-cover.jpg",
             "durationSeconds": duration, "audioBytes": bytes, "description": "Fixture description"]
        }
        let terminal = publicShape(slug: terminalSlug,
            title: "Anmeldelse: The Terminal List, sæson 1 på Prime Video", host: "Frederik Kragh",
            date: "2026-10-28T15:28:31.044Z", duration: 426, bytes: 10_935_515)
        let book = publicShape(slug: bookSlug,
            title: "Anmeldelse: Nogen der kender nogen – hvem har råd til et hjem?", host: "Liv Brandt",
            date: "2026-10-28T13:36:59.314Z", duration: 345, bytes: 8_783_654)
        let placebo = publicShape(slug: placeboSlug,
            title: "Anmeldelse: Placebo i K.B. Hallen – et langt farvel", host: "Peter Milo",
            date: "2026-10-27T10:25:13.805Z", duration: 348, bytes: 8_936_219)
        var oldPlacebo = publicShape(slug: "placebo---sluk-telefonen-og-bliv-haengende-lidt-endnu",
            title: "Placebo - Sluk telefonen, og bliv hængende lidt endnu", host: "Peter Milo",
            date: "2026-10-26T14:37:10.820Z", duration: 287, bytes: 7_369_584)
        oldPlacebo["id"] = "ai-" + placeboSlug
        oldPlacebo["guid"] = "ai-" + placeboSlug
        let payload = try catalogData([terminal, book, placebo, oldPlacebo])
        let path = try cachePath()
        let service = PodcastManifestService(manifestURL: url, cacheURL: path, fallbackEpisodes: [], fetch: { [url] _ in
            (payload, HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        })
        let fresh = await service.refreshCatalog()
        XCTAssertTrue(fresh.isFresh)
        XCTAssertEqual(fresh.episodes.map(\.id), ["ai-" + terminalSlug, "ai-" + bookSlug])
        let articles = [
            Article(id: "6ae1fb83b14bf576bb768fce", name: terminal["title"] as! String,
                    slug: terminalSlug, content: "Fixture", intro: "", topicID: "fixture"),
            Article(id: "6ae1f9da0e01d3d2ff34859f", name: book["title"] as! String,
                    slug: bookSlug, content: "Fixture", intro: "", topicID: "fixture")
        ]
        let model = PodcastAvailabilityModel()
        model.acceptManifest(fresh.episodes)
        model.recordIdentities(articles.map { ($0.id, $0.slug) })
        let visible = fresh.episodes.filter { model.allows($0) }
        for article in articles {
            let raw = try XCTUnwrap(PodcastRepository.bestMatch(in: visible, for: article, requirePlayableAudio: true))
            XCTAssertEqual(raw.articleSlug, article.slug)
            XCTAssertNil(raw.articleId)
            XCTAssertNil(raw.sourceContentRevision)
            let offered = PodcastRepository.enriched(raw, with: article)
            XCTAssertTrue(model.allows(offered, articleID: article.id))
            let asset = try XCTUnwrap(model.audioAsset(for: offered, articleID: article.id))
            XCTAssertEqual(asset.binding, .acceptedRecording(articleID: nil, articleSlug: article.slug))
            XCTAssertNil(asset.sourceRevision)
            XCTAssertEqual(asset.canonicalArticleID, article.id)
            XCTAssertEqual(asset.remoteURL, offered.audioURL)
            let audio = try XCTUnwrap(offered.audioURL)
            XCTAssertTrue(PodcastPlaybackPolicy.canStart(playbackURL: audio, isOnline: true))
            XCTAssertFalse(PodcastPlaybackPolicy.canStart(playbackURL: audio, isOnline: false))
        }
        let restarted = PodcastManifestService(manifestURL: url, cacheURL: path, fallbackEpisodes: [],
            fetch: { _ in throw URLError(.notConnectedToInternet) })
        let cached = await restarted.refreshCatalog()
        XCTAssertFalse(cached.isFresh)
        XCTAssertEqual(cached.episodes, fresh.episodes)
    }

    @MainActor
    func testUnplayableURLsAreIsolatedAndStillPoisonTheirKnownIdentity() async throws {
        var relative = catalogEntry("relative")
        relative["audioURL"] = "relative.m4a"
        var document = catalogEntry("document")
        document["audioURL"] = "https://fixtures.example.invalid/document.pdf"
        var poisoned = catalogEntry("poisoned-url")
        poisoned["audioURL"] = "https://fixtures.example.invalid/poisoned.pdf"
        let payload = try catalogData([catalogEntry("valid"), relative, document,
            catalogEntry("poisoned-url"), poisoned])
        let service = PodcastManifestService(manifestURL: url, cacheURL: try cachePath(), fallbackEpisodes: [], fetch: { [url] _ in
            (payload, HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        })
        let result = await service.refreshCatalog()
        XCTAssertTrue(result.isFresh)
        XCTAssertEqual(result.episodes.map(\.id), ["valid"])
        XCTAssertTrue(result.episodes.allSatisfy(\.hasPlayableAudioURL))
    }

    @MainActor
    func testEntirelyUnplayableCatalogCannotReplaceLastGoodDiskCache() async throws {
        let path = try cachePath()
        var payload = valid
        let service = PodcastManifestService(manifestURL: url, cacheURL: path, fallbackEpisodes: [], fetch: { [url] _ in
            (payload, HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        })
        let original = await service.refreshCatalog()
        var relative = catalogEntry("relative")
        relative["audioURL"] = "relative.m4a"
        var document = catalogEntry("document")
        document["audioURL"] = "https://fixtures.example.invalid/document.pdf"
        payload = try catalogData([relative, document])
        let rejected = await service.refreshCatalog(force: true)
        XCTAssertFalse(rejected.isFresh)
        XCTAssertEqual(rejected.episodes, original.episodes)
        XCTAssertEqual(try Data(contentsOf: path), valid)
        let restarted = PodcastManifestService(manifestURL: url, cacheURL: path, fallbackEpisodes: [],
            fetch: { _ in throw URLError(.notConnectedToInternet) })
        let cached = await restarted.refreshCatalog()
        XCTAssertFalse(cached.isFresh)
        XCTAssertEqual(cached.episodes, original.episodes)
    }
}
