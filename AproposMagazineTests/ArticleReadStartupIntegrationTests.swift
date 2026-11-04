import Combine
import FirebaseCore
import XCTest
@testable import Apropos

/// Real VM/startup/Series entry points. Every transport and cache effect is local;
/// no live observer installation or normal app pipeline is started by this file.
@MainActor
final class ArticleReadStartupIntegrationTests: XCTestCase {
    private typealias VM = ArticleViewModel
    private typealias Startup = ReaderStartupCoordinator
    private typealias Contract = ReaderAuthoritativeReadContract
    private enum Injected: Error { case failed }

    @MainActor private final class Gate<Value> {
        let entered: XCTestExpectation
        private var continuation: CheckedContinuation<Value, Never>?
        init(_ entered: XCTestExpectation) { self.entered = entered }
        func wait() async -> Value {
            await withCheckedContinuation { continuation in
                self.continuation = continuation
                entered.fulfill()
            }
        }
        func release(_ value: Value) {
            guard let continuation else { return XCTFail("No physical operation to finish") }
            self.continuation = nil
            continuation.resume(returning: value)
        }
    }

    @MainActor private final class Fixture {
        let sdk: ReaderSDKStartupState
        let identity = CanonicalSessionState()
        var actualUID: String?
        var uidHook: (() -> Void)?
        var feed: [VM.ReadCompletion<[Article]>] = []
        var feedFallback: [VM.ReadCompletion<[Article]>] = []
        var topics: [VM.ReadCompletion<[Topic]>] = []
        var sections: [VM.ReadCompletion<[WebflowSection]>] = []
        var authors: [VM.ReadCompletion<[Author]>] = []
        var stars: [([String: String]?) -> Void] = []
        var fallbackCalls: [String] = []
        var cacheCalls: [String] = []
        var incomingCalls: [String] = []
        var incoming: @MainActor (String, VM.ReadPermission) async -> Result<Article, Error> = { _, _ in
            .failure(FirestoreArticleError.empty)
        }
        var sdkStarts = 0
        lazy var vm = makeVM()

        init(guarded: Bool = false, uid: String? = "A", resolved: Bool = true) {
            sdk = guarded ? ReaderSDKStartupState() : .application
            actualUID = uid
            if resolved { _ = identity.adopt(uid.map(Self.session)) }
        }
        static func session(_ uid: String) -> ReaderAccountSession {
            .init(uid: uid, email: "reader@example.invalid", isEmailVerified: true)
        }
        func select(_ uid: String?) {
            actualUID = uid
            _ = identity.adopt(uid.map(Self.session))
        }
        private func makeVM() -> VM {
            var effects = VM.ReadEffects()
            effects.feed = { [unowned self] permission, done in
                XCTAssertTrue(permission()); self.feed.append(done)
            }
            effects.feedFallback = { [unowned self] permission, done in
                XCTAssertTrue(permission()); self.feedFallback.append(done)
            }
            effects.topics = { [unowned self] permission, done in
                XCTAssertTrue(permission()); self.topics.append(done)
            }
            effects.sections = { [unowned self] permission, done in
                XCTAssertTrue(permission()); self.sections.append(done)
            }
            effects.authors = { [unowned self] permission, done in
                XCTAssertTrue(permission()); self.authors.append(done)
            }
            effects.stars = { [unowned self] permission, done in
                XCTAssertTrue(permission()); self.stars.append(done)
            }
            effects.topicsFallback = { [unowned self] permission, done in
                XCTAssertTrue(permission()); self.fallbackCalls.append("topics"); done(.success([]))
            }
            effects.sectionsFallback = { [unowned self] permission, done in
                XCTAssertTrue(permission()); self.fallbackCalls.append("sections"); done(.success([]))
            }
            effects.authorsFallback = { [unowned self] permission, done in
                XCTAssertTrue(permission()); self.fallbackCalls.append("authors"); done(.success([]))
            }
            effects.starsFallback = { [unowned self] permission, done in
                XCTAssertTrue(permission()); self.fallbackCalls.append("stars"); done([:])
            }
            effects.cacheTopics = { [unowned self] _ in self.cacheCalls.append("topics") }
            effects.cacheSections = { [unowned self] _ in self.cacheCalls.append("sections") }
            effects.cacheAuthors = { [unowned self] _ in self.cacheCalls.append("authors") }
            effects.cacheStars = { [unowned self] _ in self.cacheCalls.append("stars") }
            effects.incoming = { [unowned self] identifier, permission in
                XCTAssertTrue(permission()); self.incomingCalls.append(identifier)
                return await self.incoming(identifier, permission)
            }
            return VM(startup: sdk, identity: identity, actualUserID: { [unowned self] in
                self.uidHook?(); return self.actualUID
            }, readEffects: effects)
        }
        func requestMetadata() {
            vm.fetchTopics(); vm.fetchSections(); vm.fetchAuthors(); vm.fetchStars()
        }
        func openGuardedStartup() async throws {
            let configuration = try Startup.Configuration(projectID: "local-read-fixture", appID: "local-app",
                installationID: UUID(), writerFenceRevision: String(repeating: "a", count: 64),
                migrationRevision: String(repeating: "b", count: 64))
            let marker: @MainActor () async throws -> Startup.Marker? = { nil }
            let membership: @MainActor (Contract.MembershipRequest) async throws -> Contract.MembershipSnapshot = { request in
                let echoed = try JSONSerialization.jsonObject(with: Contract.encode(request))
                let data = try JSONSerialization.data(withJSONObject: [
                    "schemaVersion": 1, "scope": Contract.membershipScope, "request": echoed,
                    "membership": ["schemaVersion": 1, "ownerUID": request.expectedUID, "epoch": 4, "state": "active"],
                    "validUntilMs": 20_000
                ])
                return try Contract.decodeMembershipResponse(data: data, for: request)
            }
            let verifier: Startup.Verifier = { challenge in
                .init(challenge: challenge, coverage: .allPersistedWritersIncludingPreviousAccounts,
                    writerFenceRevision: configuration.writerFenceRevision,
                    migrationRevision: configuration.migrationRevision, validUntilMs: 20_000)
            }
            let starter: @MainActor (Startup.Receipt, @escaping Startup.StartAdmission) async throws -> Void = { [unowned self] _, admit in
                try admit(); self.sdkStarts += 1
            }
            let coordinator = Startup(canonical: identity, sdkState: sdk, configuration: configuration,
                readMarker: marker, readMembership: membership, verify: verifier, startSDK: starter,
                now: { 10_000 }, schedule: { _ in {} })
            _ = try await coordinator.start(context: identity.contextTicket())
        }
    }

    override func setUp() { super.setUp(); XCTAssertNil(FirebaseApp.allApps) }
    override func tearDown() { XCTAssertNil(FirebaseApp.allApps); super.tearDown() }

    private func article(_ id: String = "article") -> Article {
        Article(id: id, name: "En lokal historie", slug: id, content: "<p>Tekst</p>", intro: "Intro", topicID: "culture")
    }
    /// Drain the finite MainActor callback hops used by the existing VM. No
    /// timer, service or wall-clock delay is used to manufacture readiness.
    private func flushCallbacks() async { for _ in 0..<12 { await Task.yield() } }
    private func expectCancelled<T>(_ result: Result<T, Error>?, file: StaticString = #filePath, line: UInt = #line) {
        guard case .failure(let error) = result else { return XCTFail("Expected cancellation", file: file, line: line) }
        XCTAssertTrue(error is CancellationError, file: file, line: line)
    }

    func testClosedActualVMReadEntrypointsNeverInvokeEffects() async {
        let f = Fixture(guarded: true)
        var steps = 0
        f.vm.start(readerSteps: [{ _ in steps += 1 }])
        var feedResult: Result<[Article], Error>?
        f.vm.fetchRemoteArticles { feedResult = $0 }
        f.requestMetadata()
        let incoming = await f.vm.fetchIncomingArticle("old", fallback: "slug")
        await flushCallbacks()
        XCTAssertEqual(steps, 0); expectCancelled(feedResult); XCTAssertNil(incoming)
        XCTAssertTrue(f.feed.isEmpty); XCTAssertTrue(f.feedFallback.isEmpty)
        XCTAssertTrue(f.topics.isEmpty); XCTAssertTrue(f.sections.isEmpty)
        XCTAssertTrue(f.authors.isEmpty); XCTAssertTrue(f.stars.isEmpty)
        XCTAssertTrue(f.incomingCalls.isEmpty); XCTAssertTrue(f.cacheCalls.isEmpty)
        XCTAssertFalse(f.vm.isLoadingTopics); XCTAssertEqual(f.sdkStarts, 0)
    }

    func testInjectedGuardedStartupWithoutProviderGetterFailsClosed() async {
        let identity = CanonicalSessionState()
        _ = identity.adopt(Fixture.session("A"))
        var effects = VM.ReadEffects()
        var calls = 0
        effects.feed = { _, _ in calls += 1 }
        effects.topics = { _, _ in calls += 1 }
        effects.incoming = { _, _ in calls += 1; return .failure(Injected.failed) }
        let vm = VM(startup: ReaderSDKStartupState(), identity: identity, readEffects: effects)
        var result: Result<[Article], Error>?
        vm.start(readerSteps: [{ _ in calls += 1 }])
        vm.fetchRemoteArticles { result = $0 }
        vm.fetchTopics()
        let incoming = await vm.fetchIncomingArticle("old", fallback: "fallback")
        expectCancelled(result); XCTAssertNil(incoming)
        XCTAssertNil(vm.captureReadPermission()); XCTAssertEqual(calls, 0)
        XCTAssertFalse(vm.isLoadingTopics)
    }

    func testClosedStartCanResumeOnceAfterActualCoordinatorAcceptance() async throws {
        let f = Fixture(guarded: true)
        var steps: [String] = []
        f.vm.start(readerSteps: [
            { permission in XCTAssertTrue(permission()); steps.append("bind") },
            { permission in XCTAssertTrue(permission()); steps.append("load") }
        ])
        XCTAssertTrue(steps.isEmpty)
        try await f.openGuardedStartup()
        f.vm.resumeReaderStartup(); f.vm.resumeReaderStartup()
        XCTAssertEqual(steps, ["bind", "load"]); XCTAssertEqual(f.sdkStarts, 1)
        f.requestMetadata()
        XCTAssertEqual(f.topics.count, 1); XCTAssertEqual(f.sections.count, 1)
        XCTAssertEqual(f.authors.count, 1); XCTAssertEqual(f.stars.count, 1)
    }

    func testLegacyUnresolvedToGuestResumesWithFreshPermissionWithoutDuplicateStart() async {
        let f = Fixture(uid: nil, resolved: false)
        var contexts: [CanonicalSessionState.Context] = []
        var permissions: [VM.ReadPermission] = []
        f.vm.start(readerSteps: [{ permission in
            contexts.append(f.identity.snapshot.context); permissions.append(permission)
        }])
        XCTAssertEqual(contexts, [.unresolved]); XCTAssertTrue(permissions[0]())
        f.select(nil)
        XCTAssertFalse(permissions[0]())
        await flushCallbacks()
        f.vm.resumeReaderStartup()
        XCTAssertEqual(contexts, [.unresolved, .guest])
        XCTAssertTrue(permissions[1]())
    }

    func testStartStepReentryDropsOldTailAndResumesNewestAccountOnce() async {
        let f = Fixture()
        var first = 0, tail = 0
        var oldPermission: VM.ReadPermission?
        f.vm.start(readerSteps: [
            { permission in
                first += 1
                if first == 1 { oldPermission = permission; f.select("B"); f.select("A") }
            },
            { permission in XCTAssertTrue(permission()); tail += 1 }
        ])
        XCTAssertEqual(tail, 0); XCTAssertEqual(oldPermission?(), false)
        await flushCallbacks()
        f.vm.resumeReaderStartup()
        XCTAssertEqual(first, 2); XCTAssertEqual(tail, 1)
    }

    func testProviderChangeBeforeObservationRejectsEveryReadEntrypoint() async {
        let f = Fixture(); _ = f.vm
        f.actualUID = "B" // The Auth callback has not arrived; canonical still says A.
        var result: Result<[Article], Error>?
        f.vm.fetchRemoteArticles { result = $0 }; f.requestMetadata()
        let incoming = await f.vm.fetchIncomingArticle("old", fallback: "slug")
        XCTAssertNil(incoming)
        expectCancelled(result)
        XCTAssertTrue(f.feed.isEmpty); XCTAssertTrue(f.topics.isEmpty); XCTAssertTrue(f.sections.isEmpty)
        XCTAssertTrue(f.authors.isEmpty); XCTAssertTrue(f.stars.isEmpty); XCTAssertTrue(f.incomingCalls.isEmpty)
    }

    func testReentrantProviderGetterCannotAdmitReadUnderOriginalA() {
        let f = Fixture(); _ = f.vm
        f.uidHook = { f.uidHook = nil; f.select("B"); f.select("A") }
        var result: Result<[Article], Error>?
        f.vm.fetchRemoteArticles { result = $0 }
        expectCancelled(result); XCTAssertTrue(f.feed.isEmpty)
    }

    func testLateFeedSuccessAfterAccountRoundTripIsCancellationNotNewAccountData() async {
        let f = Fixture()
        let done = expectation(description: "Original physical feed callback retires")
        var result: Result<[Article], Error>?
        f.vm.fetchRemoteArticles { result = $0; done.fulfill() }
        XCTAssertEqual(f.feed.count, 1)
        f.select("B"); f.select("A")
        f.feed[0](.success([article("old")]))
        await fulfillment(of: [done], timeout: 3)
        expectCancelled(result); XCTAssertTrue(f.feedFallback.isEmpty)
    }

    func testLateEmptyFeedCannotStartFallbackAfterProviderChanges() async {
        let f = Fixture()
        let done = expectation(description: "Stale empty feed returned")
        var result: Result<[Article], Error>?
        f.vm.fetchRemoteArticles { result = $0; done.fulfill() }
        f.actualUID = "B"
        f.feed[0](.failure(FirestoreArticleError.empty))
        await fulfillment(of: [done], timeout: 3)
        expectCancelled(result); XCTAssertTrue(f.feedFallback.isEmpty)
    }

    func testFallbackKeepsOriginalPermissionThroughItsOwnDelayedReturn() async {
        let f = Fixture()
        let done = expectation(description: "Fallback physical result returned")
        var result: Result<[Article], Error>?
        f.vm.fetchRemoteArticles { result = $0; done.fulfill() }
        f.feed[0](.failure(FirestoreArticleError.empty))
        await flushCallbacks()
        XCTAssertEqual(f.feedFallback.count, 1)
        guard let callback = f.feedFallback.first else { return }
        f.select("B"); f.select("A")
        callback(.success([article("stale-fallback")]))
        await fulfillment(of: [done], timeout: 3)
        expectCancelled(result)
    }

    func testFreshGuestCanReceiveFeedFallbackAndMetadataWithoutAuthOrSDK() async throws {
        let f = Fixture(uid: nil)
        let done = expectation(description: "Guest feed accepted")
        var result: Result<[Article], Error>?
        f.vm.fetchRemoteArticles { result = $0; done.fulfill() }
        f.feed[0](.failure(FirestoreArticleError.empty))
        await flushCallbacks()
        XCTAssertEqual(f.feedFallback.count, 1)
        guard let callback = f.feedFallback.first else { return }
        callback(.success([article("guest")]))
        await fulfillment(of: [done], timeout: 3)
        let received = try XCTUnwrap(result).get()
        XCTAssertEqual(received.map(\.id), ["guest"])
        f.requestMetadata()
        f.topics[0](.success([Topic(id: "culture", name: "Kultur")]))
        f.sections[0](.success([WebflowSection(id: "stories", name: "Historier")]))
        f.authors[0](.success([Author(id: "author", name: "Forfatter", bio: nil, imageURL: nil, position: "", photoURL: "")]))
        f.stars[0](["five": "5"])
        await flushCallbacks()
        XCTAssertEqual(f.vm.topics.map(\.id), ["culture"])
        XCTAssertEqual(f.vm.sections.map(\.id), ["stories"])
        XCTAssertEqual(f.vm.authors.map(\.id), ["author"])
        XCTAssertEqual(f.vm.starsMapping, ["five": "5"])
        XCTAssertEqual(Set(f.cacheCalls), Set(["topics", "sections", "authors", "stars"]))
        XCTAssertFalse(f.vm.isLoadingTopics); XCTAssertNil(f.vm.topicsError)
    }

    func testOldMetadataCallbacksCannotClearNewRequestSpinnerOrCacheOldValues() async {
        let f = Fixture(); f.requestMetadata()
        f.select("B"); f.select("A")
        f.requestMetadata()
        XCTAssertEqual(f.topics.count, 2); XCTAssertTrue(f.vm.isLoadingTopics)
        f.topics[0](.success([Topic(id: "old", name: "Gammelt")]))
        f.sections[0](.success([WebflowSection(id: "old", name: "Gammelt")]))
        f.authors[0](.success([Author(id: "old", name: "Gammel", bio: nil, imageURL: nil, position: "", photoURL: "")]))
        f.stars[0](["old": "1"])
        await flushCallbacks()
        XCTAssertTrue(f.vm.isLoadingTopics)
        XCTAssertTrue(f.vm.topics.isEmpty); XCTAssertTrue(f.vm.sections.isEmpty)
        XCTAssertTrue(f.vm.authors.isEmpty); XCTAssertTrue(f.vm.starsMapping.isEmpty)
        XCTAssertTrue(f.cacheCalls.isEmpty)
        f.topics[1](.success([Topic(id: "new", name: "Nyt")]))
        f.sections[1](.success([])); f.authors[1](.success([])); f.stars[1](["new": "5"])
        await flushCallbacks()
        XCTAssertFalse(f.vm.isLoadingTopics); XCTAssertEqual(f.vm.topics.map(\.id), ["new"])
        XCTAssertEqual(f.vm.starsMapping, ["new": "5"])
        XCTAssertEqual(f.cacheCalls.count, 4)
    }

    func testLateEmptyMetadataCannotStartAnyFallbackAfterOwnerChanges() async {
        let f = Fixture(); f.requestMetadata()
        f.select("B")
        f.topics[0](.failure(FirestoreMetadataError.empty))
        f.sections[0](.failure(FirestoreMetadataError.empty))
        f.authors[0](.failure(FirestoreMetadataError.empty)); f.stars[0](nil)
        await flushCallbacks()
        XCTAssertTrue(f.fallbackCalls.isEmpty); XCTAssertTrue(f.cacheCalls.isEmpty)
        XCTAssertFalse(f.vm.isLoadingTopics); XCTAssertNil(f.vm.topicsError)
    }

    func testMetadataPublicationReentryCannotCommitOrCacheOldAccountValues() async {
        for kind in ["topics", "sections", "authors", "stars"] {
            let f = Fixture()
            switch kind {
            case "topics": f.vm.fetchTopics()
            case "sections": f.vm.fetchSections()
            case "authors": f.vm.fetchAuthors()
            default: f.vm.fetchStars()
            }
            var once = false
            let observer = f.vm.objectWillChange.sink {
                // Subscription starts after admission/loading publication, so
                // the next event is the actual attempted metadata commit.
                if !once { once = true; f.select("B") }
            }
            switch kind {
            case "topics": f.topics[0](.success([Topic(id: "old", name: "Gammelt")]))
            case "sections": f.sections[0](.success([WebflowSection(id: "old", name: "Gammelt")]))
            case "authors": f.authors[0](.success([Author(id: "old", name: "Gammel", bio: nil, imageURL: nil, position: "", photoURL: "")]))
            default: f.stars[0](["old": "1"])
            }
            await flushCallbacks()
            XCTAssertTrue(once, kind); XCTAssertTrue(f.cacheCalls.isEmpty, kind)
            XCTAssertTrue(f.vm.topics.isEmpty, kind); XCTAssertTrue(f.vm.sections.isEmpty, kind)
            XCTAssertTrue(f.vm.authors.isEmpty, kind); XCTAssertTrue(f.vm.starsMapping.isEmpty, kind)
            XCTAssertFalse(f.vm.isLoadingTopics)
            withExtendedLifetime(observer) {}
        }
    }

    func testTopicsFailureFinishesOriginalLoadingAndAllowsExplicitRetry() async {
        let f = Fixture(); f.vm.fetchTopics(); f.vm.fetchTopics()
        XCTAssertEqual(f.topics.count, 1)
        f.topics[0](.failure(Injected.failed)); await flushCallbacks()
        XCTAssertFalse(f.vm.isLoadingTopics); XCTAssertNotNil(f.vm.topicsError)
        f.vm.fetchTopics(); XCTAssertEqual(f.topics.count, 2); XCTAssertTrue(f.vm.isLoadingTopics)
        f.topics[1](.success([Topic(id: "retry", name: "Igen")]))
        await flushCallbacks()
        XCTAssertNil(f.vm.topicsError); XCTAssertFalse(f.vm.isLoadingTopics)
        XCTAssertEqual(f.vm.topics.map(\.id), ["retry"]); XCTAssertEqual(f.cacheCalls, ["topics"])
    }

    func testLateIncomingEmptyAfterRoundTripCannotIssueFallback() async {
        let f = Fixture()
        let gate = Gate<Result<Article, Error>>(expectation(description: "Incoming physical read held"))
        f.incoming = { _, _ in await gate.wait() }
        let task = Task { @MainActor in await f.vm.fetchIncomingArticle("old", fallback: "fallback") }
        await fulfillment(of: [gate.entered], timeout: 3)
        f.select("B"); f.select("A"); gate.release(.failure(FirestoreArticleError.empty))
        let result = await task.value
        XCTAssertNil(result); XCTAssertEqual(f.incomingCalls, ["old"])
    }

    func testIncomingCallerRevocationAndTaskCancelRejectLateSuccess() async {
        for cancel in [false, true] {
            let f = Fixture()
            let gate = Gate<Result<Article, Error>>(expectation(description: "Incoming result held"))
            var current = true
            f.incoming = { _, _ in await gate.wait() }
            let task = Task { @MainActor in
                await f.vm.fetchIncomingArticle("old", fallback: "fallback", stillCurrent: { current })
            }
            await fulfillment(of: [gate.entered], timeout: 3)
            if cancel { task.cancel() } else { current = false }
            gate.release(.success(article("old")))
            let result = await task.value
            XCTAssertNil(result); XCTAssertEqual(f.incomingCalls, ["old"])
        }
    }

    func testFreshIncomingFallbackUsesSameOwnerAndReturnsAcceptedArticle() async {
        let f = Fixture(uid: nil), accepted = article("found")
        f.incoming = { identifier, permission in
            XCTAssertTrue(permission())
            return identifier == "old" ? .failure(FirestoreArticleError.empty) : .success(accepted)
        }
        let result = await f.vm.fetchIncomingArticle("old", fallback: "slug")
        XCTAssertEqual(result?.id, "found"); XCTAssertEqual(f.incomingCalls, ["old", "slug"])
    }

    func testSeriesAccountChangeRetainsPhysicalSlotRejectsOldResultAndAllowsRetry() async {
        let f = Fixture()
        let gate = Gate<[ContentSeries]>(expectation(description: "Original Series operation held"))
        var calls = 0
        let fresh = ContentSeries(slug: "new", name: "Ny", description: "", articleIds: [], generatedAt: nil)
        let service = SeriesService(transport: { permission in
            XCTAssertTrue(permission()); calls += 1
            if calls == 1 { return await gate.wait() }
            return [fresh]
        })
        guard let original = f.vm.captureReadPermission() else { return XCTFail("Expected A admission") }
        let task = Task { @MainActor in await service.fetchSeries(stillCurrent: original) }
        await fulfillment(of: [gate.entered], timeout: 3)
        f.select("B")
        guard let current = f.vm.captureReadPermission() else { return XCTFail("Expected B admission") }
        await service.fetchSeries(stillCurrent: current)
        XCTAssertEqual(calls, 1); XCTAssertTrue(service.isLoading)
        gate.release([ContentSeries(slug: "old", name: "Gammel", description: "", articleIds: [], generatedAt: nil)])
        await task.value
        XCTAssertTrue(service.series.isEmpty); XCTAssertFalse(service.isLoading); XCTAssertNil(service.errorMessage)
        await service.fetchSeries(stillCurrent: current)
        XCTAssertEqual(calls, 2); XCTAssertEqual(service.series, [fresh]); XCTAssertFalse(service.isLoading)
    }

    func testSeriesCancellationCannotPublishOrRetirePhysicalWaitEarly() async {
        let gate = Gate<[ContentSeries]>(expectation(description: "Physical Series wait"))
        var calls = 0
        let service = SeriesService(transport: { _ in calls += 1; return await gate.wait() })
        let task = Task { @MainActor in await service.fetchSeries(stillCurrent: { true }) }
        await fulfillment(of: [gate.entered], timeout: 3)
        task.cancel(); await flushCallbacks()
        await service.fetchSeries(stillCurrent: { true })
        XCTAssertEqual(calls, 1); XCTAssertTrue(service.isLoading)
        gate.release([ContentSeries(slug: "cancelled", name: "Gammel", description: "", articleIds: [], generatedAt: nil)])
        await task.value
        XCTAssertTrue(service.series.isEmpty); XCTAssertNil(service.errorMessage); XCTAssertFalse(service.isLoading)
    }
}
