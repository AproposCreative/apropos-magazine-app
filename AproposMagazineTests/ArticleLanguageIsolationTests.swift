import FirebaseCore
import Combine
import UIKit
import XCTest
@testable import Apropos

@MainActor
final class ArticleLanguageIsolationTests: XCTestCase {
    private let sourceID = "0123456789abcdef01234567"
    private enum Injected: Error { case unavailable }

    @MainActor private final class CacheFixture {
        let now = Date()
        var bytes: Data?
        var writes: [CacheData] = []
        var hold = false
        var entered: XCTestExpectation?
        var preparationReturned: XCTestExpectation?
        var continuation: CheckedContinuation<Void, Never>?
        let worker = ArticleCacheDecodeWorker()
        lazy var cache = ArticleCacheHydrationCoordinator(read: { [unowned self] in
            bytes.map(ArticleCacheHydrationCoordinator.Source.encoded)
        }, prepare: { [self] source, policy in
            await waitIfHeld()
            return await worker.prepare(source, policy: policy)
        }, now: { [unowned self] in now })

        func waitIfHeld() async {
            guard hold else { return }
            await withCheckedContinuation { continuation = $0; entered?.fulfill() }
        }
        func release() {
            hold = false
            let held = continuation; continuation = nil; held?.resume()
        }
        func seed(_ articles: [Article]) throws {
            bytes = try JSONEncoder().encode(CacheData(articles: articles,
                timestamp: now.addingTimeInterval(-3600), version: "1.3"))
        }
        func begin() -> ArticleViewModel.ReadEffects.CatalogPreparation {
            let original = cache.capture()
            return { [self] update, current, permission in
                defer { self.preparationReturned?.fulfill() }
                return try await ArticleFeedSnapshot.prepare(update, original: original,
                    load: { [self] in await self.cache.load($0, stillPermitted: $1) },
                    isCurrent: { [self] in self.cache.isCurrent($0) }, current: current,
                    now: { [self] in self.now }, stillPermitted: permission)
            }
        }
        func persist(_ update: ArticleFeedSnapshot.Update) {
            guard let date = update.cacheTimestamp else { return XCTFail("Expected a known cache age") }
            let value = CacheData(articles: update.articles.map { $0.strippingBodyContent() }, timestamp: date, version: "1.3")
            do { bytes = try JSONEncoder().encode(value); writes.append(value); cache.invalidate() }
            catch { XCTFail("Local codec failed: \(error)") }
        }
        func cold() async throws -> ArticleCacheHydrationCoordinator.Prepared {
            let decoded = await worker.prepare(.encoded(try XCTUnwrap(bytes)),
                policy: .init(version: "1.3", maximumAge: 7*24*3600, now: now))
            guard case .ready(let value) = decoded else { throw Injected.unavailable }
            return value
        }
    }

    override func setUp() { super.setUp(); XCTAssertNil(FirebaseApp.allApps) }
    override func tearDown() { XCTAssertNil(FirebaseApp.allApps); super.tearDown() }

    private func source(_ language: ArticleContentLanguage, title: String = "old", empty: Bool = false,
                        cached: Bool = false, pending: Bool = false, body: String = "<p>Body</p>") -> ArticleMirrorCatalog.Source {
        let id = language == .danish ? sourceID : "en_" + sourceID
        var data: [String: Any] = ["id": id, "isDraft": false, "isArchived": false,
            "createdOn": "2026-11-01T12:00:00Z", "lastPublished": "2026-11-03T12:00:00Z",
            "contentRevision": language.rawValue + title,
            "fieldData": ["name": title, "slug": "same-slug", "intro": "Intro", "content": body, "topic": "culture"]]
        if language == .english {
            data["contentLanguage"] = "en"; data["sourceArticleID"] = sourceID
            data["cmsLocaleId"] = ArticleContentLanguage.englishCMSLocaleID
        }
        return .init(language: language, documents: empty ? [] : [(id, data)],
                     isFromCache: cached, hasPendingWrites: pending)
    }
    private func article(_ language: ArticleContentLanguage) throws -> Article {
        let document = try XCTUnwrap(source(language).documents.first)
        return try CMSArticleDocumentCodec.decodeArticle(from: document.data, expectedID: document.id)
    }
    private func update(_ source: ArticleMirrorCatalog.Source, failed: ArticleContentLanguage) -> ArticleMirrorCatalog.Update {
        ArticleMirrorCatalog.decode(.init(sources: [source], failures: [failed: Injected.unavailable]))
    }
    private func vm(_ raw: ArticleMirrorCatalog.Update, fixture: CacheFixture,
                    preferences: PreferencesManager,
                    configure: (inout ArticleViewModel.ReadEffects) -> Void = { _ in }) -> ArticleViewModel {
        var effects = ArticleViewModel.ReadEffects()
        effects.catalog = { permission, done in XCTAssertTrue(permission()); done(.success(raw)) }
        effects.beginCatalogRead = fixture.begin
        effects.invalidateFeedCache = { fixture.cache.invalidate() }
        effects.cacheFeed = fixture.persist
        configure(&effects)
        let identity = CanonicalSessionState(); _ = identity.adopt(nil)
        return ArticleViewModel(startup: .application, identity: identity, featureIdentity: identity,
            actualUserID: { nil }, readEffects: effects,
            availabilityModel: ArticleAvailabilityModel(save: { _ in }, schedule: { _ in {} }),
            languagePreferences: preferences)
    }

    func testActualViewModelHeldColdCachePartialCommitAndColdDecodeBothDirections() async throws {
        for healthy in ArticleContentLanguage.allCases {
            let failed: ArticleContentLanguage = healthy == .danish ? .english : .danish
            let f = CacheFixture(); try f.seed([article(.danish), article(.english)])
            defer { f.release() }
            let suite = "language-isolation-" + UUID().uuidString
            let defaults = try XCTUnwrap(UserDefaults(suiteName: suite)); defer { defaults.removePersistentDomain(forName: suite) }
            let preferences = PreferencesManager(userDefaults: defaults); preferences.updateArticleLanguage(healthy)
            let model = vm(update(source(healthy, title: "fresh"), failed: failed), fixture: f, preferences: preferences)
            let held = expectation(description: "actual encoded cache held"); f.hold = true; f.entered = held
            model.fetchArticles(forceRefresh: true)
            await fulfillment(of: [held], timeout: 2)
            XCTAssertTrue(model.articles.isEmpty); XCTAssertTrue(f.writes.isEmpty)
            f.release(); await model.waitForArticleLoadCycle()

            XCTAssertEqual(model.articles.count, 2)
            XCTAssertEqual(model.visibleArticles.first?.name, "fresh")
            XCTAssertNil(model.fetchError)
            preferences.updateArticleLanguage(failed)
            XCTAssertEqual(model.visibleArticles.first?.name, "old")
            XCTAssertNotNil(model.fetchError)
            XCTAssertEqual(model.fetchError?.localizedDescription, failed == .english
                ? "Articles could not be updated. Try again." : "Artiklerne kunne ikke opdateres. Prøv igen.")
            XCTAssertEqual(f.writes.count, 1)
            XCTAssertEqual(f.writes[0].timestamp, f.now.addingTimeInterval(-3600))
            let cold = try await f.cold()
            XCTAssertEqual(Set(cold.articles.compactMap(\.contentLanguage)), [.danish, .english])
            XCTAssertEqual(cold.articles.first { $0.contentLanguage == healthy }?.name, "fresh")
            XCTAssertEqual(cold.articles.first { $0.contentLanguage == failed }?.name, "old")
            XCTAssertEqual(cold.timestamp, f.now.addingTimeInterval(-3600))
        }
    }

    func testFreshEmptyClearsOnlyItsLanguageCachedOrPendingEmptyPreservesBaseline() async throws {
        for mode in 0..<3 {
            let f = CacheFixture(); try f.seed([article(.danish), article(.english)])
            let prepare = f.begin()
            let raw = update(source(.danish, empty: true, cached: mode == 1, pending: mode == 2), failed: .english)
            let value = try await prepare(raw, { [] }, { true })
            XCTAssertEqual(Set(value.articles.compactMap(\.contentLanguage)), mode == 0 ? [.english] : [.danish, .english])
            XCTAssertEqual(value.hasAcceptedNamespace, mode == 0)
            XCTAssertEqual(value.freshLanguages, mode == 0 ? [.danish] : [])
            XCTAssertEqual(value.cacheTimestamp, f.now.addingTimeInterval(-3600))
            XCTAssertNotNil(value.displayError(for: .english))
            XCTAssertEqual(value.displayError(for: .danish) == nil, mode == 0)
        }
    }

    func testCurrentRevisionBeatsEqualDateDiskAndUnconfirmedSource() async throws {
        for mode in 0..<3 {
            let f = CacheFixture(); try f.seed([article(.danish), article(.english)])
            let document = try XCTUnwrap(source(.english, title: "current revision", body: "<p>Newer revision body</p>").documents.first)
            let newer = try CMSArticleDocumentCodec.decodeArticle(from: document.data, expectedID: document.id)
            XCTAssertEqual(newer.revisionDate, try article(.english).revisionDate)
            XCTAssertNotEqual(newer.content, try article(.english).content)
            let raw = mode == 0 ? update(source(.danish, title: "fresh"), failed: .english)
                : ArticleMirrorCatalog.decode(.init(sources: [source(.danish, title: "fresh"),
                    source(.english, cached: mode == 1, pending: mode == 2)], failures: [:]))
            let suite = "current-language-revision-" + UUID().uuidString
            let defaults = try XCTUnwrap(UserDefaults(suiteName: suite)); defer { defaults.removePersistentDomain(forName: suite) }
            let model = vm(raw, fixture: f, preferences: PreferencesManager(userDefaults: defaults))
            model.articles = [try article(.danish), newer]
            model.fetchArticles(forceRefresh: true); await model.waitForArticleLoadCycle()
            let retained = try XCTUnwrap(model.articles.first { $0.contentLanguage == .english })
            XCTAssertEqual(retained.bodyRevision, newer.bodyRevision)
            XCTAssertEqual(retained.content, newer.content)
            XCTAssertEqual(f.writes.count, 1)
            let cold = try await f.cold()
            XCTAssertEqual(cold.articles.first { $0.contentLanguage == .english }?.bodyRevision, newer.bodyRevision)
            XCTAssertEqual(cold.timestamp, f.now.addingTimeInterval(-3600))
        }
    }

    func testBothFailuresHydrateValidColdCacheWithoutWritingOrRenewingIt() async throws {
        let f = CacheFixture(); try f.seed([article(.danish), article(.english)])
        let bytes = f.bytes
        let suite = "both-language-failure-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite)); defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = PreferencesManager(userDefaults: defaults)
        let raw = ArticleMirrorCatalog.decode(.init(sources: [], failures: [.danish: Injected.unavailable, .english: Injected.unavailable]))
        let model = vm(raw, fixture: f, preferences: preferences)
        model.fetchArticles(forceRefresh: true); await model.waitForArticleLoadCycle()
        XCTAssertEqual(model.articles.count, 2); XCTAssertNotNil(model.fetchError)
        XCTAssertTrue(f.writes.isEmpty); XCTAssertEqual(f.bytes, bytes)
    }

    func testCacheReplacementDuringDecodeCannotBecomeAnEmptyOrBorrowedBaseline() async throws {
        let f = CacheFixture(); try f.seed([article(.danish), article(.english)])
        defer { f.release() }
        let prepare = f.begin(), held = expectation(description: "old decode held")
        f.hold = true; f.entered = held
        let raw = update(source(.danish, title: "obsolete"), failed: .english)
        let task = Task { try await prepare(raw, { [] }, { true }) }
        await fulfillment(of: [held], timeout: 2)
        f.cache.invalidate(); let replacement = Data("newer bytes not owned by old reader".utf8); f.bytes = replacement
        f.release()
        do { _ = try await task.value; XCTFail("Stale baseline must abort") }
        catch is CancellationError {} catch { XCTFail("Unexpected error: \(error)") }
        XCTAssertEqual(f.bytes, replacement); XCTAssertTrue(f.writes.isEmpty)
    }

    func testActualBackgroundAdapterUsesSamePartialMergeAndClosesQueryPermission() async throws {
        let f = CacheFixture(); try f.seed([article(.danish), article(.english)])
        let prepare = f.begin(), raw = update(source(.english, title: "fresh"), failed: .danish)
        var queryPermission: (@MainActor () -> Bool)?
        var results: [UIBackgroundFetchResult] = []
        let done = expectation(description: "OS completion")
        let delegate = AppDelegate()
        delegate.refreshBackgroundFeed(stillCurrent: { true }, fallbackFailure: .failed, onFailure: { XCTFail("Healthy namespace must commit") },
            fetch: { permission, reply in
                queryPermission = permission
                Task { @MainActor in
                    do { reply(.success(try await prepare(raw, { [] }, permission))) }
                    catch { reply(.failure(error)) }
                }
            }, fallback: { _, _ in XCTFail("Partial failure cannot start whole-CMS fallback") },
            cache: f.persist, completion: { results.append($0); done.fulfill() })
        await fulfillment(of: [done], timeout: 2)
        XCTAssertEqual(results, [.newData]); XCTAssertEqual(f.writes.count, 1)
        XCTAssertFalse(try XCTUnwrap(queryPermission)())
        let cold = try await f.cold()
        XCTAssertEqual(cold.articles.count, 2); XCTAssertEqual(cold.timestamp, f.now.addingTimeInterval(-3600))
        XCTAssertEqual(cold.articles.first { $0.contentLanguage == .danish }?.name, "old")
        XCTAssertEqual(cold.articles.first { $0.contentLanguage == .english }?.name, "fresh")
    }

    func testTypedBackgroundEmptyFailureAndForeignReplacementHaveDistinctEffects() async throws {
        for mode in 0..<3 {
            let f = CacheFixture(); try f.seed([article(.danish), article(.english)])
            let originalBytes = f.bytes, prepare = f.begin()
            let raw = mode == 1
                ? ArticleMirrorCatalog.decode(.init(sources: [], failures: [.danish: Injected.unavailable, .english: Injected.unavailable]))
                : update(source(.danish, empty: true), failed: .english)
            let done = expectation(description: "typed OS completion \(mode)")
            var results: [UIBackgroundFetchResult] = [], failureCount = 0
            AppDelegate().refreshBackgroundFeed(stillCurrent: { true }, fallbackFailure: .failed,
                onFailure: { failureCount += 1 }, fetch: { permission, reply in
                    Task { @MainActor in
                        do {
                            let prepared = try await prepare(raw, { [] }, permission)
                            if mode == 2 { f.cache.invalidate() }
                            reply(.success(prepared)); reply(.success(prepared))
                        } catch { reply(.failure(error)) }
                    }
                }, fallback: { _, _ in XCTFail("No whole-catalog fallback") }, cache: f.persist,
                completion: { results.append($0); done.fulfill() })
            await fulfillment(of: [done], timeout: 2)
            for _ in 0..<6 { await Task.yield() }
            XCTAssertEqual(results, [mode == 0 ? .newData : mode == 1 ? .failed : .noData])
            XCTAssertEqual(failureCount, mode == 1 ? 1 : 0)
            XCTAssertEqual(f.writes.count, mode == 0 ? 1 : 0)
            if mode == 0 {
                let cold = try await f.cold()
                XCTAssertEqual(cold.articles.compactMap(\.contentLanguage), [.english])
                XCTAssertEqual(cold.timestamp, f.now.addingTimeInterval(-3600))
            } else { XCTAssertEqual(f.bytes, originalBytes) }
        }
    }

    func testTypedViewModelOldAccountGenerationCannotCommitAfterAToBToA() async throws {
        let f = CacheFixture(); try f.seed([article(.danish), article(.english)]); defer { f.release() }
        let originalBytes = f.bytes
        let identity = CanonicalSessionState()
        func session(_ uid: String) -> ReaderAccountSession {
            .init(uid: uid, email: "reader@example.invalid", isEmailVerified: true)
        }
        var actualUID = "A"; _ = identity.adopt(session("A"))
        var effects = ArticleViewModel.ReadEffects()
        effects.catalog = { _, done in done(.success(self.update(self.source(.danish, title: "obsolete"), failed: .english))) }
        effects.beginCatalogRead = f.begin
        effects.invalidateFeedCache = { f.cache.invalidate() }; effects.cacheFeed = f.persist
        let model = ArticleViewModel(startup: .application, identity: identity, featureIdentity: identity,
            actualUserID: { actualUID }, readEffects: effects,
            availabilityModel: ArticleAvailabilityModel(save: { _ in }, schedule: { _ in {} }))
        model.articles = [try article(.english)]
        f.hold = true; let held = expectation(description: "A decode physically held"); f.entered = held
        let returned = expectation(description: "original typed prepare returned"); f.preparationReturned = returned
        model.fetchArticles(forceRefresh: true); await fulfillment(of: [held], timeout: 2)
        actualUID = "B"; _ = identity.adopt(session("B"))
        actualUID = "A"; _ = identity.adopt(session("A"))
        f.release(); await model.waitForArticleLoadCycle()
        await fulfillment(of: [returned], timeout: 2)
        XCTAssertEqual(model.articles.map(\.name), ["old"])
        XCTAssertTrue(f.writes.isEmpty); XCTAssertEqual(f.bytes, originalBytes)
    }

    func testEnglishSelectionLocalizesActualCoordinatorDeadline() async throws {
        let f = CacheFixture(); try f.seed([article(.danish), article(.english)])
        let suite = "english-feed-timeout-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite)); defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = PreferencesManager(userDefaults: defaults); preferences.updateArticleLanguage(.english)
        let queried = expectation(description: "actual typed coordinator started")
        var expiry: (() -> Void)?
        let model = vm(update(source(.danish), failed: .english), fixture: f, preferences: preferences) { effects in
            effects.catalog = { _, _ in queried.fulfill() }
            effects.scheduleFeedTimeout = { expiry = $0; return {} }
        }
        model.fetchArticles(forceRefresh: true); await fulfillment(of: [queried], timeout: 2)
        try XCTUnwrap(expiry)(); await model.waitForArticleLoadCycle()
        XCTAssertEqual(model.fetchError?.localizedDescription, "Articles could not be updated. Try again.")
        preferences.updateArticleLanguage(.danish)
        XCTAssertEqual(model.fetchError?.localizedDescription, "Artiklerne kunne ikke opdateres. Prøv igen.")
        XCTAssertTrue(f.writes.isEmpty)
    }

    func testActualCacheOwnerAndNormalAvailabilityObserverAllowOwnUIAndBackgroundEffects() async throws {
        for background in [false, true] {
            for withdrawal in [false, true] {
                let suite = "actual-language-cache-" + UUID().uuidString
                let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
                let directory = FileManager.default.temporaryDirectory.appendingPathComponent(suite)
                defer { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: directory) }
                let availability = ArticleAvailabilityModel(save: { _ in }, schedule: { _ in {} })
                let oldDate = Date().addingTimeInterval(-3600)
                let beforeRead = Date()
                var persisted: [[Article]] = []
                var persistedDates: [Date] = []
                let cache = CacheManager(userDefaults: defaults, cacheDirectory: directory, availabilityModel: availability,
                    feedPersistence: { articles, _, date in persisted.append(articles); persistedDates.append(date) })
                cache.cacheArticles([try article(.danish), try article(.english)], timestamp: oldDate)
                persisted.removeAll(); persistedDates.removeAll()
                let raw = update(source(withdrawal ? .english : .danish, title: "fresh"),
                    failed: withdrawal ? .danish : .english)
                let pruned = expectation(description: "normal observer pruned actual owner")
                var original: ArticleCacheHydrationCoordinator.Capture?
                let prepare: () -> ArticleViewModel.ReadEffects.CatalogPreparation = {
                    let capture = cache.captureArticlesHydration(); original = capture
                    return { update, current, permission in
                        try await cache.prepareFeedUpdate(update, original: capture, current: current, stillPermitted: permission)
                    }
                }
                let identity = CanonicalSessionState(); _ = identity.adopt(nil)
                var effects = ArticleViewModel.ReadEffects()
                effects.beginCatalogRead = prepare
                effects.cacheFeed = { update in
                    guard let date = update.cacheTimestamp else { return XCTFail("Known baseline lost its age") }
                    cache.cacheArticles(update.articles, articlesAreSorted: true, timestamp: date)
                }
                effects.invalidateFeedCache = cache.invalidateArticleReads
                effects.pruneFeedCache = { cache.pruneUnavailableArticleMetadata(); pruned.fulfill() }
                let fetch: ArticleFeedRefreshCoordinator.CatalogFetch = { permission, reply in
                    Task { @MainActor in
                        let ticket = availability.beginRead()
                        if withdrawal { availability.recordWithdrawals([self.sourceID], ticket: ticket) }
                        else {
                            availability.trackPublicationIDs([self.sourceID])
                            availability.recordPublications(raw.articles, ticket: ticket)
                        }
                        await self.fulfillment(of: [pruned], timeout: 2)
                        do {
                            let captured = try XCTUnwrap(original)
                            XCTAssertTrue(cache.isCurrentArticleRead(captured))
                            reply(.success(try await cache.prepareFeedUpdate(raw,
                                original: captured, current: { [] }, stillPermitted: permission)))
                        } catch { XCTFail("Own availability effect rejected: \(error)"); reply(.failure(error)) }
                    }
                }
                // Actual Firestore effects happen before its callback. Only its
                // transport is substituted; the cache and observer remain real.
                effects.catalog = { permission, done in
                    Task { @MainActor in
                        let ticket = availability.beginRead()
                        if withdrawal { availability.recordWithdrawals([self.sourceID], ticket: ticket) }
                        else {
                            availability.trackPublicationIDs([self.sourceID])
                            availability.recordPublications(raw.articles, ticket: ticket)
                        }
                        await self.fulfillment(of: [pruned], timeout: 2)
                        guard let captured = original else { XCTFail("Missing original capture"); done(.failure(Injected.unavailable)); return }
                        XCTAssertTrue(cache.isCurrentArticleRead(captured))
                        done(.success(raw))
                    }
                }
                let model = ArticleViewModel(startup: .application, identity: identity, featureIdentity: identity,
                    actualUserID: { nil }, readEffects: effects, availabilityModel: availability)
                model.articles = [try article(.danish), try article(.english)]
                model.installFeedAvailabilityObserver(stillCurrent: { true })
                if background {
                    _ = prepare() // Same pre-SDK capture as the real OS owner.
                    let done = expectation(description: "background applies after availability prune")
                    AppDelegate().refreshBackgroundFeed(stillCurrent: { true }, fallbackFailure: .failed,
                        onFailure: { XCTFail("Own denial must not cancel healthy source") }, fetch: fetch,
                        fallback: { _, _ in XCTFail("No fallback") }, cache: effects.cacheFeed,
                        completion: { XCTAssertEqual($0, .newData); done.fulfill() })
                    await fulfillment(of: [done], timeout: 2)
                } else {
                    model.fetchArticles(forceRefresh: true); await model.waitForArticleLoadCycle()
                    XCTAssertEqual(model.articles.count, withdrawal ? 1 : 2)
                    XCTAssertEqual(model.articles.first { $0.contentLanguage == (withdrawal ? .english : .danish) }?.name, "fresh")
                }
                XCTAssertEqual(persisted.count, 2) // Denial prune, then healthy source commit.
                XCTAssertEqual(persistedDates.first, oldDate)
                if withdrawal {
                    // Nothing unrefreshed remains after this denial. All final
                    // rows came from the healthy source, so a new date is valid.
                    XCTAssertGreaterThanOrEqual(try XCTUnwrap(persistedDates.last), beforeRead)
                } else { XCTAssertEqual(persistedDates.last, oldDate) }
                let finalCapture = cache.captureArticlesHydration()
                guard case .ready(let final) = await cache.loadCapturedArticles(finalCapture) else { return XCTFail("Actual cache unreadable") }
                XCTAssertEqual(final.articles.count, withdrawal ? 1 : 2)
                XCTAssertEqual(final.timestamp, persistedDates.last)
                XCTAssertEqual(final.articles.first { $0.contentLanguage == (withdrawal ? .english : .danish) }?.name, "fresh")
                let reopened = CacheManager(userDefaults: defaults, cacheDirectory: directory,
                    availabilityModel: availability, feedPersistence: { _, _, _ in })
                guard case .ready(let cold) = await reopened.loadCapturedArticles(reopened.captureArticlesHydration()) else {
                    return XCTFail("New cache owner could not decode the persisted bytes")
                }
                XCTAssertEqual(cold, final)
                cache.pruneUnavailableArticleMetadata()
                XCTAssertTrue(cache.isCurrentArticleRead(finalCapture)); XCTAssertEqual(persisted.count, 2)
                cache.cacheArticles(final.articles, timestamp: oldDate)
                XCTAssertFalse(cache.isCurrentArticleRead(finalCapture))
            }
        }
    }

    func testActualCacheReprojectsWithdrawalAfterReentrantPermission() async throws {
        for memoized in [false, true] {
            let suite = "actual-cache-permission-" + UUID().uuidString
            let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(suite)
            defer { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: directory) }
            let availability = ArticleAvailabilityModel(save: { _ in }, schedule: { _ in {} })
            let cache = CacheManager(userDefaults: defaults, cacheDirectory: directory,
                availabilityModel: availability, feedPersistence: { _, _, _ in })
            cache.cacheArticles([try article(.danish), try article(.english)], timestamp: Date().addingTimeInterval(-3600))
            let capture = cache.captureArticlesHydration()
            if memoized {
                guard case .ready(let warm) = await cache.loadCapturedArticles(capture) else { return XCTFail("Warmup failed") }
                XCTAssertEqual(warm.articles.count, 2)
            }
            var checks = 0, fired = false
            let outcome = await cache.loadCapturedArticles(capture, stillPermitted: {
                checks += 1
                // Force reentry specifically at the platform owner's final
                // check, after the decoder's three permission checks.
                if checks == 5 {
                    fired = true
                    availability.recordWithdrawals([self.sourceID], ticket: availability.beginRead())
                    cache.pruneUnavailableArticleMetadata()
                }
                return true
            })
            XCTAssertTrue(fired); XCTAssertTrue(cache.isCurrentArticleRead(capture))
            guard case .ready(let value) = outcome else { return XCTFail("Monotone prune is not a foreign write") }
            XCTAssertEqual(value.articles.compactMap(\.contentLanguage), [.english])
        }
    }

    func testUndatedRetainedDetailStaysInMemoryWithoutCacheWriteOrSourceAuthority() async throws {
        let f = CacheFixture()
        let suite = "undated-language-detail-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite)); defer { defaults.removePersistentDomain(forName: suite) }
        var recorded: [Article] = []
        let model = vm(update(source(.danish, title: "fresh"), failed: .english), fixture: f,
            preferences: PreferencesManager(userDefaults: defaults)) { effects in effects.recordFeedArticles = { recorded = $0 } }
        model.articles = [try article(.english)]
        model.fetchArticles(forceRefresh: true); await model.waitForArticleLoadCycle()
        XCTAssertEqual(model.articles.count, 2); XCTAssertEqual(recorded.map(\.name), ["fresh"])
        XCTAssertEqual(recorded.compactMap(\.contentLanguage), [.danish])
        XCTAssertTrue(f.writes.isEmpty); XCTAssertNil(f.bytes)
    }

    func testWithdrawalDuringFeedWillChangeRejectsStaleAdoptionAndCacheEffects() async throws {
        let f = CacheFixture(); try f.seed([article(.danish), article(.english)])
        let availability = ArticleAvailabilityModel(save: { _ in }, schedule: { _ in {} })
        let identity = CanonicalSessionState(); _ = identity.adopt(nil)
        var armed = false, fired = false
        var effects = ArticleViewModel.ReadEffects()
        let raw = update(source(.danish, title: "fresh"), failed: .english)
        effects.catalog = { _, done in done(.success(raw)) }
        effects.beginCatalogRead = f.begin; effects.cacheFeed = f.persist
        effects.invalidateFeedCache = { f.cache.invalidate() }
        effects.recordFeedArticles = { rows in
            XCTAssertEqual(rows.map(\.name), ["fresh"]); armed = true
        }
        let model = ArticleViewModel(startup: .application, identity: identity, featureIdentity: identity,
            actualUserID: { nil }, readEffects: effects, availabilityModel: availability)
        model.articles = [try article(.english)]
        let observation = model.objectWillChange.sink {
            guard armed else { return }; armed = false; fired = true
            availability.recordWithdrawals([self.sourceID], ticket: availability.beginRead())
        }
        defer { observation.cancel() }
        model.fetchArticles(forceRefresh: true); await model.waitForArticleLoadCycle()
        XCTAssertTrue(fired)
        XCTAssertEqual(model.articles.compactMap(\.contentLanguage), [.english])
        XCTAssertTrue(f.writes.isEmpty)
    }

    func testReadDeadlineRetainsHealthyNamespaceAndRejectsLateFailedNamespace() async throws {
        var expiry: (@MainActor () -> Void)?
        var late: CheckedContinuation<ArticleMirrorCatalog.Source, Error>?
        let held = expectation(description: "English read physically held")
        let task = Task {
            try await ArticleMirrorCatalog.loadIndependently(englishEnabled: true, stillCurrent: { true },
                scheduleDeadline: { expiry = $0; return {} }) { language in
                    if language == .danish { return self.source(.danish, title: "fresh") }
                    return try await withCheckedThrowingContinuation { late = $0; held.fulfill() }
                }
        }
        await fulfillment(of: [held], timeout: 2)
        try XCTUnwrap(expiry)()
        let batch = try await task.value
        XCTAssertEqual(batch.sources.map(\.language), [.danish])
        XCTAssertEqual((batch.failures[.english] as? URLError)?.code, .timedOut)
        try XCTUnwrap(late).resume(returning: source(.english, title: "late")); late = nil
        for _ in 0..<8 { await Task.yield() }
        XCTAssertEqual(ArticleMirrorCatalog.decode(batch).articles.map(\.name), ["fresh"])
    }

    func testIndependentReadCancellationAndOwnerLossCloseBeforeLateTransportReturn() async throws {
        for cancelTask in [false, true] {
            var permitted = true, expiry: (@MainActor () -> Void)?
            var late: CheckedContinuation<ArticleMirrorCatalog.Source, Error>?
            let entered = expectation(description: "physical transport held")
            let returned = expectation(description: "physical transport returned")
            let task = Task {
                try await ArticleMirrorCatalog.loadIndependently(englishEnabled: true, stillCurrent: { permitted },
                    scheduleDeadline: { expiry = $0; return {} }) { language in
                        if language == .danish { return self.source(.danish) }
                        defer { returned.fulfill() }
                        return try await withCheckedThrowingContinuation { late = $0; entered.fulfill() }
                    }
            }
            await fulfillment(of: [entered], timeout: 2)
            if cancelTask { task.cancel() }
            else { permitted = false; try XCTUnwrap(expiry)() }
            do { _ = try await task.value; XCTFail("Closed owner cannot receive catalog authority") }
            catch is CancellationError {} catch { XCTFail("Unexpected error: \(error)") }
            try XCTUnwrap(late).resume(returning: source(.english, title: "too late")); late = nil
            await fulfillment(of: [returned], timeout: 2)
        }
    }

    func testInvalidAndUnusableNamespacesCannotBecomeAuthoritativeEmpty() {
        let valid = source(.danish, title: "fresh")
        var data = source(.english).documents[0].data
        data["fieldData"] = ["name": 17, "slug": "broken", "intro": "Intro"]
        let broken = ArticleMirrorCatalog.Source(language: .english,
            documents: [("en_" + sourceID, data)], isFromCache: false, hasPendingWrites: false)
        let value = ArticleMirrorCatalog.decode(.init(sources: [valid, broken], failures: [:]))
        XCTAssertEqual(value.namespaces.map { $0.source.language }, [.danish])
        XCTAssertNotNil(value.failures[.english]); XCTAssertEqual(value.freshLanguages, [.danish])
        let duplicate = ArticleMirrorCatalog.decode(.init(sources: [valid, valid], failures: [:]))
        XCTAssertTrue(duplicate.validatedSources.isEmpty); XCTAssertTrue(duplicate.namespaces.isEmpty)
        XCTAssertNotNil(duplicate.failures[.danish])
    }
}
