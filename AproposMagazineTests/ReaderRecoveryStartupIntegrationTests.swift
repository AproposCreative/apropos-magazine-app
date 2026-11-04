import Combine
import FirebaseCore
import XCTest
@testable import Apropos

/// Actual startup/Auth/reader entry points plus the real marker and journal.
/// Only SDK/reference effects are injected; no Firebase, APNs or network starts.
@MainActor
final class ReaderRecoveryStartupIntegrationTests: XCTestCase {
    private enum Injected: Error { case readFailed, heldReadTimedOut }
    private final class Probe: @unchecked Sendable {
        private let lock = NSLock(), semaphore = DispatchSemaphore(value: 0)
        private var readCount = 0, legacyCount = 0, holdsFirst = false, fails = false, mainThread = false
        var reads: Int { lock.lock(); defer { lock.unlock() }; return readCount }
        var legacyReads: Int { lock.lock(); defer { lock.unlock() }; return legacyCount }
        var readOnMainThread: Bool { lock.lock(); defer { lock.unlock() }; return mainThread }
        func holdFirst() { lock.lock(); holdsFirst = true; lock.unlock() }
        func failReads() { lock.lock(); fails = true; lock.unlock() }
        func release() { semaphore.signal() }
        func read() throws {
            lock.lock()
            readCount += 1
            mainThread = mainThread || Thread.isMainThread
            let hold = holdsFirst && readCount == 1, fail = fails
            lock.unlock()
            if hold, semaphore.wait(timeout: .now() + 5) != .success { throw Injected.heldReadTimedOut }
            if fail { throw Injected.readFailed }
        }
        func legacy(_ namespace: FavoritesNamespace) throws -> Data? {
            lock.lock(); legacyCount += 1; lock.unlock()
            return try JSONSerialization.data(withJSONObject: ["schemaVersion": 1, "namespace": namespace.recordBinding,
                "entries": [["id": "legacy-story", "pressAccreditation": false]]])
        }
    }

    @MainActor private final class Fixture {
        let root: URL, probe: Probe, recovery: ReaderTransitionRecovery, sdk: ReaderSDKStartupState, auth: AuthService
        var actualUID: String?
        var events: [String] = [], published: [CanonicalSessionState.ContextTicket] = []
        var readerEffects: [String] = [], vmContexts: [CanonicalSessionState.ContextTicket] = []
        var readyContexts: [CanonicalSessionState.ContextTicket] = []
        var vmPermissions: [ArticleViewModel.ReadPermission] = []
        var topics: [ArticleViewModel.ReadCompletion<[Topic]>] = []
        var topicCacheWrites = 0, sdkWrites = 0, releaseAttempts = 0
        var onReaderStep: ((String) -> Void)?, onPublication: (() -> Void)?
        var tasks: [Task<Void, Never>] = []
        lazy var delegate = AppDelegate(startup: sdk, identity: auth.bootstrapIdentity,
            actualUserID: { [unowned self] in actualUID })
        lazy var writers = ReaderWriterDrainRuntime(canonical: auth.state,
            actualUID: { [unowned self] in actualUID }, makeDrain: { .init(wait: { $0(nil) }) },
            legacyAdmission: recovery.admission)
        lazy var journal = FavoritesFileJournal(rootDirectory: root.appendingPathComponent("journal"),
            legacyRead: { [probe] in try probe.legacy($0) }, legacyAdmission: recovery.admission)
        lazy var vm: ArticleViewModel = {
            var effects = ArticleViewModel.ReadEffects()
            effects.topics = { [unowned self] permitted, completion in
                XCTAssertTrue(permitted()); topics.append(completion)
            }
            effects.cacheTopics = { [unowned self] _ in topicCacheWrites += 1 }
            return ArticleViewModel(startup: sdk, identity: auth.bootstrapIdentity,
                actualUserID: { [unowned self] in actualUID }, readEffects: effects)
        }()

        init(root: URL, probe: Probe = Probe(), missingStorage: Bool = false) {
            self.root = root; self.probe = probe
            recovery = ReaderTransitionRecovery(store: .init(rootDirectory: missingStorage ? nil : root.appendingPathComponent("recovery"),
                beforeRead: { try probe.read() }))
            sdk = ReaderSDKStartupState(legacyRecovery: recovery)
            auth = AuthService(startup: sdk)
        }
        var context: CanonicalSessionState.ContextTicket { auth.bootstrapIdentity.contextTicket() }
        @discardableResult func observe(_ uid: String?) -> CanonicalSessionState.ContextTicket? {
            actualUID = uid
            let original = uid.map { ReaderAccountSession(uid: $0, email: "local@example.invalid", isEmailVerified: true) }
            return auth.observeIdentity(original, currentUserID: { [unowned self] in actualUID },
                revokeReader: { [unowned self] admitted in auth.state.suspend(stillPermitted: admitted) != nil },
                publishReader: { [unowned self] admitted in
                    guard let accepted = auth.state.adopt(original, stillPermitted: admitted) else { return nil }
                    published.append(accepted); events.append("publish:" + (uid ?? "guest")); onPublication?()
                    return accepted
                })
        }
        func requestReaderStart() {
            vm.start(readerSteps: [{ [unowned self] permitted in
                XCTAssertTrue(permitted()); vmContexts.append(context); vmPermissions.append(permitted)
            }])
        }
        func steps() -> [() -> Void] {
            ["reference", "profile", "favorites", "preferences", "FCM"].map { name in
                { [unowned self] in readerEffects.append(name); events.append(name); onReaderStep?(name) }
            }
        }
        @discardableResult func launch(_ uid: String? = "reader-A", observesIdentity: Bool = true) -> Task<Void, Never>? {
            let task = delegate.runAccountStartup(authOnly: { [unowned self] in events.append("auth") },
                readerSteps: steps(), observeAuth: { [unowned self] in
                    events.append("observe"); if observesIdentity { observe(uid) }
                }, releaseReader: { [unowned self] in releaseAttempts += 1; _ = auth.resumeReaderAfterLocalRecovery() },
                readyReader: { [unowned self] in readyContexts.append(context) })
            if let task { tasks.append(task) }
            return task
        }
        func read(_ namespace: FavoritesNamespace) async throws -> FavoritesRecord? {
            try await withCheckedThrowingContinuation { continuation in
                journal.storage.read(namespace) { continuation.resume(with: $0) }
            }
        }
        func captureWrite() -> ReaderWriterDrainRuntime.CapturedWrite? {
            writers.captureWrite(expectedUserID: "reader-A", stillCurrent: { true }, start: { [unowned self] current, complete in
                guard current() else { complete(CancellationError()); return }
                sdkWrites += 1; complete(nil)
            })
        }
        func close() async {
            onReaderStep = nil; onPublication = nil
            tasks.forEach { $0.cancel() }; probe.release()
            for task in tasks { await task.value }
        }
    }

    override func setUp() { super.setUp(); XCTAssertNil(FirebaseApp.allApps) }
    override func tearDown() { XCTAssertNil(FirebaseApp.allApps); super.tearDown() }
    private func fixture(root: URL? = nil, probe: Probe = Probe(), missingStorage: Bool = false) -> Fixture {
        let directory = root ?? FileManager.default.temporaryDirectory.appendingPathComponent("reader-restart-" + UUID().uuidString)
        if root == nil { addTeardownBlock { try? FileManager.default.removeItem(at: directory) } }
        let f = Fixture(root: directory, probe: probe, missingStorage: missingStorage)
        addTeardownBlock { @MainActor in await f.close() }
        return f
    }
    private func eventually(_ condition: () -> Bool, file: StaticString = #filePath, line: UInt = #line) async {
        for _ in 0..<2_000 { if condition() { return }; try? await Task.sleep(nanoseconds: 1_000_000) }
        XCTFail("Actual local stage did not finish", file: file, line: line)
    }
    private func assertClosed(_ f: Fixture, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertFalse(f.sdk.permitsReaderServices(identity: f.auth.bootstrapIdentity), file: file, line: line)
        XCTAssertFalse(f.delegate.readerWorkGuard()(), file: file, line: line)
        XCTAssertTrue(f.readerEffects.isEmpty, file: file, line: line)
        XCTAssertTrue(f.vmContexts.isEmpty, file: file, line: line)
        XCTAssertTrue(f.published.isEmpty, file: file, line: line)
        XCTAssertNil(f.captureWrite(), file: file, line: line)
        XCTAssertEqual(f.sdkWrites, 0, file: file, line: line)
    }
    private func assertJournalClosed(_ f: Fixture, _ namespace: FavoritesNamespace = .guest,
        file: StaticString = #filePath, line: UInt = #line) async {
        do { _ = try await f.read(namespace); XCTFail("Legacy journal was admitted", file: file, line: line) }
        catch { XCTAssertEqual(error as? FavoritesFileJournal.TransitionFailure, .frozen, file: file, line: line) }
    }
    private func binding(_ owner: String = "reader-A") throws -> ReaderMembershipContract.Binding {
        try .init(ownerUID: owner, epoch: 7)
    }

    func testConstructionAndClosedDisplayEntryPointsPerformNoMarkerOrLegacyIO() async {
        let f = fixture()
        f.requestReaderStart(); f.vm.fetchTopics()
        XCTAssertTrue(f.sdk.localRecovery === f.recovery)
        XCTAssertEqual(f.probe.reads, 0); XCTAssertEqual(f.probe.legacyReads, 0)
        assertClosed(f); await assertJournalClosed(f)
        XCTAssertEqual(f.probe.legacyReads, 0); XCTAssertTrue(f.topics.isEmpty)
    }

    func testHeldActualMarkerReadAllowsAuthOnlyButZeroReaderReferencesAndJournalIO() async throws {
        let probe = Probe(); probe.holdFirst()
        let f = fixture(probe: probe); f.requestReaderStart()
        let task = try XCTUnwrap(f.launch())
        await eventually { probe.reads == 1 }
        XCTAssertEqual(f.events, ["auth", "observe"])
        XCTAssertEqual(f.auth.bootstrapIdentity.snapshot.context, .account("reader-A"))
        XCTAssertEqual(f.auth.state.snapshot.context, .unresolved)
        f.vm.fetchTopics(); assertClosed(f); await assertJournalClosed(f)
        XCTAssertEqual(probe.legacyReads, 0); XCTAssertFalse(probe.readOnMainThread)
        probe.release(); await task.value
        await eventually { f.vmContexts.count == 1 }
        XCTAssertEqual(f.published.count, 1); XCTAssertEqual(f.vmContexts, [f.context])
    }

    func testMissingMarkerReleasesOriginalAccountAfterPreparationAndStartsRequestedVMExactlyOnce() async throws {
        let f = fixture(); f.requestReaderStart()
        let task = try XCTUnwrap(f.launch()); await task.value
        await eventually { f.vmContexts.count == 1 }
        XCTAssertEqual(f.events, ["auth", "observe", "reference", "profile", "favorites", "preferences", "FCM", "publish:reader-A"])
        XCTAssertEqual(f.auth.state.snapshot.context, .account("reader-A"))
        XCTAssertEqual(f.published.count, 1); XCTAssertEqual(f.releaseAttempts, 1)
        XCTAssertEqual(f.vmContexts, [f.context]); XCTAssertEqual(f.probe.reads, 1)
        XCTAssertFalse(f.auth.resumeReaderAfterLocalRecovery())
        f.sdk.publishLocalReadiness(); f.requestReaderStart()
        XCTAssertEqual(f.vmContexts.count, 1); XCTAssertEqual(f.published.count, 1)
        let write = try XCTUnwrap(f.captureWrite()); try await write()
        XCTAssertEqual(f.sdkWrites, 1)
        let owner = try XCTUnwrap(FavoritesContext.confirmed(userID: "reader-A").namespace)
        let restored = try await f.read(owner)
        XCTAssertEqual(restored?.articles.map(\.id), ["legacy-story"]); XCTAssertEqual(f.probe.legacyReads, 1)
    }

    func testMissingMarkerPreservesExplicitGuestReadingWithoutInventingAccountWriteAuthority() async throws {
        let f = fixture(); f.requestReaderStart()
        let task = try XCTUnwrap(f.launch(nil)); await task.value
        await eventually { f.vmContexts.count == 1 }
        XCTAssertEqual(f.auth.state.snapshot.context, .guest)
        XCTAssertEqual(f.published.count, 1); XCTAssertEqual(f.vmContexts, [f.context])
        XCTAssertTrue(f.delegate.readerWorkGuard()()); XCTAssertNil(f.captureWrite())
        let restored = try await f.read(.guest)
        XCTAssertEqual(restored?.articles.map(\.id), ["legacy-story"])
        XCTAssertEqual(f.sdkWrites, 0); XCTAssertEqual(f.probe.reads, 1)
    }

    func testFailedPhysicalMarkerReadDoesNotReleasePendingAccountOrFallbackToLegacy() async throws {
        let probe = Probe(); probe.failReads()
        let f = fixture(probe: probe); f.requestReaderStart()
        let task = try XCTUnwrap(f.launch()); await task.value
        assertClosed(f); await assertJournalClosed(f)
        XCTAssertEqual(probe.reads, 1); XCTAssertEqual(probe.legacyReads, 0)
        XCTAssertEqual(f.recovery.status, .unavailable); XCTAssertEqual(f.releaseAttempts, 0)
        XCTAssertNil(f.launch()); XCTAssertEqual(probe.reads, 1)
    }

    func testMissingApplicationSupportLocationFailsClosedWithoutTemporaryStorageFallback() async throws {
        let f = fixture(missingStorage: true); f.requestReaderStart()
        let task = try XCTUnwrap(f.launch()); await task.value
        assertClosed(f); await assertJournalClosed(f)
        XCTAssertEqual(f.recovery.status, .unavailable)
        XCTAssertFalse(FileManager.default.fileExists(atPath: f.root.path))
    }

    func testCorruptPersistedMarkerBlocksReaderAndLegacyMigration() async throws {
        let f = fixture(), folder = f.root.appendingPathComponent("recovery")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data("{invalid-marker".utf8).write(to: folder.appendingPathComponent("reader-transition-v1.json"))
        f.requestReaderStart(); let task = try XCTUnwrap(f.launch()); await task.value
        assertClosed(f); await assertJournalClosed(f)
        XCTAssertEqual(f.probe.reads, 1); XCTAssertEqual(f.probe.legacyReads, 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: f.root.appendingPathComponent("journal").path))
    }

    func testCancelledHeldReadWaitsForPhysicalReadAndCannotPublishLateReadiness() async throws {
        let probe = Probe(); probe.holdFirst()
        let f = fixture(probe: probe); f.requestReaderStart()
        let task = try XCTUnwrap(f.launch()); await eventually { probe.reads == 1 }
        task.cancel(); assertClosed(f)
        XCTAssertTrue(f.recovery.isBusy)
        probe.release(); await task.value
        assertClosed(f); await assertJournalClosed(f)
        XCTAssertFalse(f.recovery.isBusy); XCTAssertFalse(f.recovery.admission.isAllowed)
        XCTAssertNil(f.launch()); XCTAssertEqual(probe.reads, 1)
    }

    func testAccountRoundTripDuringReadReleasesOnlyLatestOriginalObservation() async throws {
        let probe = Probe(); probe.holdFirst()
        let f = fixture(probe: probe); f.requestReaderStart()
        let task = try XCTUnwrap(f.launch()); await eventually { probe.reads == 1 }
        let original = f.context
        XCTAssertNil(f.observe("reader-B")); XCTAssertNil(f.observe("reader-A"))
        let latest = f.context; XCTAssertNotEqual(original, latest)
        XCTAssertNil(f.auth.releaseReaderSession(context: original)); assertClosed(f)
        probe.release(); await task.value
        await eventually { f.vmContexts.count == 1 }
        XCTAssertEqual(f.published.count, 1); XCTAssertEqual(f.vmContexts, [latest])
        XCTAssertEqual(f.auth.state.snapshot.context, .account("reader-A"))
        XCTAssertNil(f.auth.releaseReaderSession(context: original))
        XCTAssertNil(f.auth.releaseReaderSession(context: latest))
    }

    func testProviderChangesBeforeItsObservationCannotReleaseOldAuthOrReaderSteps() async throws {
        let probe = Probe(); probe.holdFirst()
        let f = fixture(probe: probe); f.requestReaderStart()
        let task = try XCTUnwrap(f.launch()); await eventually { probe.reads == 1 }
        f.actualUID = "reader-B"
        probe.release(); await task.value
        assertClosed(f)
        XCTAssertEqual(f.auth.state.snapshot.context, .unresolved)
        XCTAssertEqual(f.releaseAttempts, 0); XCTAssertFalse(f.auth.resumeReaderAfterLocalRecovery())
    }

    func testReentrantAccountRoundTripDuringPreparationStopsRemainingOldReaderSteps() async throws {
        let f = fixture(); f.requestReaderStart()
        var oldPermission: (@MainActor () -> Bool)?
        f.onReaderStep = { name in
            guard name == "reference" else { return }
            oldPermission = f.delegate.readerWorkGuard()
            f.observe("reader-B"); f.observe("reader-A")
        }
        let task = try XCTUnwrap(f.launch()); await task.value
        XCTAssertEqual(f.readerEffects, ["reference"])
        XCTAssertEqual(f.releaseAttempts, 0); XCTAssertTrue(f.published.isEmpty)
        XCTAssertFalse(try XCTUnwrap(oldPermission)())
        XCTAssertFalse(f.sdk.permitsReaderServices(identity: f.auth.bootstrapIdentity))
    }

    func testDuplicateLaunchWhileReadIsHeldDoesNotRepeatPhysicalReadOrReaderPreparation() async throws {
        let probe = Probe(); probe.holdFirst()
        let f = fixture(probe: probe); f.requestReaderStart()
        let first = try XCTUnwrap(f.launch()); await eventually { probe.reads == 1 }
        let second = try XCTUnwrap(f.launch("reader-B"))
        XCTAssertEqual(f.events, ["auth", "observe"]); XCTAssertEqual(f.context.userID, "reader-A")
        probe.release(); await first.value; await second.value
        await eventually { f.vmContexts.count == 1 }
        XCTAssertEqual(probe.reads, 1); XCTAssertEqual(f.readerEffects.count, 5)
        XCTAssertEqual(f.releaseAttempts, 1); XCTAssertEqual(f.published.count, 1); XCTAssertEqual(f.vmContexts.count, 1)
        XCTAssertNil(f.launch()); XCTAssertEqual(probe.reads, 1)
    }

    func testDeferredServicesWaitWhenAuthArrivesBeforeMarkerRead() async throws {
        let probe = Probe(); probe.holdFirst()
        let f = fixture(probe: probe)
        let task = try XCTUnwrap(f.launch()); await eventually { probe.reads == 1 }
        XCTAssertTrue(f.readyContexts.isEmpty); XCTAssertTrue(f.published.isEmpty)
        probe.release(); await task.value
        await eventually { f.readyContexts.count == 1 }
        XCTAssertEqual(f.readyContexts, [f.context]); XCTAssertEqual(f.published.count, 1)
        f.sdk.publishLocalReadiness()
        for _ in 0..<10 { await Task.yield() }
        XCTAssertEqual(f.readyContexts.count, 1)
    }

    func testDeferredServicesResumeWhenConfirmedGuestArrivesAfterMarkerRead() async throws {
        let f = fixture(); f.requestReaderStart()
        let task = try XCTUnwrap(f.launch(nil, observesIdentity: false)); await task.value
        XCTAssertEqual(f.auth.bootstrapIdentity.snapshot.context, .unresolved)
        XCTAssertTrue(f.readyContexts.isEmpty); XCTAssertTrue(f.published.isEmpty)
        XCTAssertNotNil(f.observe(nil))
        await eventually { f.readyContexts.count == 1 && f.vmContexts.last == f.context }
        XCTAssertEqual(f.auth.state.snapshot.context, .guest)
        XCTAssertEqual(f.readyContexts, [f.context]); XCTAssertEqual(f.published.count, 1)
        XCTAssertEqual(f.vmContexts.last, f.context)
        XCTAssertNil(f.captureWrite()); XCTAssertEqual(f.probe.reads, 1)
    }

    func testDelayedReadyTaskForBDoesNotBorrowFollowingAGeneration() async throws {
        let f = fixture(); let task = try XCTUnwrap(f.launch()); await task.value
        await eventually { f.readyContexts.count == 1 }
        let originalA = f.context
        XCTAssertNotNil(f.observe("reader-B")); let b = f.context
        XCTAssertNotNil(f.observe("reader-A")); let latestA = f.context
        XCTAssertNotEqual(originalA, latestA)
        await eventually { f.readyContexts.count == 2 }
        XCTAssertEqual(f.readyContexts, [originalA, latestA]); XCTAssertFalse(f.readyContexts.contains(b))
        XCTAssertEqual(f.probe.reads, 1)
    }

    func testMarkerSealRevokesPreviouslyCapturedReadAndWriteAndLateVMResult() async throws {
        let f = fixture(); f.requestReaderStart()
        let task = try XCTUnwrap(f.launch()); await task.value
        await eventually { f.vmPermissions.count == 1 }
        let readPermission = try XCTUnwrap(f.vmPermissions.first)
        let write = try XCTUnwrap(f.captureWrite())
        f.vm.fetchTopics(); XCTAssertEqual(f.topics.count, 1)
        let marker = try await f.recovery.seal(binding: binding())
        XCTAssertEqual(marker.binding, try binding())
        XCTAssertFalse(readPermission()); XCTAssertFalse(write.isCurrent())
        do { try await write(); XCTFail("Captured old write survived marker seal") } catch { }
        f.topics[0](.success([Topic(id: "old", name: "Old account data")]))
        XCTAssertTrue(f.vm.topics.isEmpty); XCTAssertEqual(f.topicCacheWrites, 0)
        XCTAssertEqual(f.sdkWrites, 0); XCTAssertFalse(f.delegate.readerWorkGuard()())
        await assertJournalClosed(f)
    }

    func testNewProcessWithSameSealedFilesKeepsAllAccountsAndGuestClosed() async throws {
        let original = fixture()
        let task = try XCTUnwrap(original.launch()); await task.value
        let marker = try await original.recovery.seal(binding: binding())
        let path = original.root.appendingPathComponent("recovery/reader-transition-v1.json")
        let bytes = try Data(contentsOf: path)
        let identities: [String?] = ["reader-A", "reader-B", nil]
        for uid in identities {
            let restarted = fixture(root: original.root); restarted.requestReaderStart()
            let startup = try XCTUnwrap(restarted.launch(uid)); await startup.value
            assertClosed(restarted); await assertJournalClosed(restarted)
            XCTAssertEqual(restarted.recovery.status, .sealed(marker))
            XCTAssertEqual(restarted.probe.legacyReads, 0)
            XCTAssertEqual(try Data(contentsOf: path), bytes)
        }
    }

    func testDeletedMarkerCannotReopenPreviouslySealedProcess() async throws {
        let f = fixture(); let task = try XCTUnwrap(f.launch()); await task.value
        _ = try await f.recovery.seal(binding: binding())
        try FileManager.default.removeItem(at: f.root.appendingPathComponent("recovery/reader-transition-v1.json"))
        do { try await f.recovery.bootstrap(); XCTFail("A missing file revived observed seal") }
        catch { XCTAssertEqual(error as? ReaderTransitionRecovery.Failure, .missingSeal) }
        XCTAssertFalse(f.recovery.admission.isAllowed)
        XCTAssertFalse(f.sdk.permitsReaderServices(identity: f.auth.bootstrapIdentity))
        XCTAssertNil(f.captureWrite()); await assertJournalClosed(f)
    }

    func testStartedSDKWriteKeepsPhysicalSlotAfterSealUntilItsOwnCallback() async throws {
        let f = fixture(); let startup = try XCTUnwrap(f.launch()); await startup.value
        var completion: ReaderWriterDrainCoordinator.Completion?, finished = false
        defer { completion?(CancellationError()) }
        let task = Task { @MainActor in
            defer { finished = true }
            do {
                try await f.writers.performWrite(expectedUserID: "reader-A", stillCurrent: { true }, start: { current, callback in
                    guard current() else { callback(CancellationError()); return }
                    completion = callback
                })
                XCTFail("Old write published after recovery denial")
            } catch { }
        }
        await eventually { completion != nil }
        _ = try await f.recovery.seal(binding: binding())
        XCTAssertFalse(finished); XCTAssertFalse(f.writers.isPhysicallyIdle); XCTAssertNil(f.captureWrite())
        try XCTUnwrap(completion)(nil); await task.value
        XCTAssertTrue(finished); XCTAssertTrue(f.writers.isPhysicallyIdle)
        XCTAssertFalse(f.recovery.admission.isAllowed)
    }
}
