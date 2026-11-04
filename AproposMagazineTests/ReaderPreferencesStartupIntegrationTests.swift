import Combine
import FirebaseCore
import XCTest
@testable import Apropos

/// Actual service, model, account actions and introduction preparation. Only
/// provider I/O and deadlines are local; startup permission is the real gate.
@MainActor
final class ReaderPreferencesStartupIntegrationTests: XCTestCase {
    private typealias Model = ReaderPreferencesModel
    private typealias Startup = ReaderStartupCoordinator
    private typealias Contract = ReaderAuthoritativeReadContract
    private enum Failure: Error { case offline }

    @MainActor private final class Lane<Input, Output> {
        private(set) var calls: [Input] = []
        private var pending: [Int: CheckedContinuation<Output, Error>] = [:]
        private var starts: [(Int, XCTestExpectation)] = []
        private var returns: [(Int, XCTestExpectation)] = []
        private var returned = 0
        var active: Int { pending.count }
        func perform(_ input: Input) async throws -> Output {
            defer {
                returned += 1
                let ready = returns.filter { $0.0 <= returned }
                returns.removeAll { $0.0 <= returned }; ready.forEach { $0.1.fulfill() }
            }
            return try await withCheckedThrowingContinuation { continuation in
                let index = calls.count; calls.append(input); pending[index] = continuation
                let ready = starts.filter { $0.0 <= calls.count }
                starts.removeAll { $0.0 <= calls.count }; ready.forEach { $0.1.fulfill() }
            }
        }
        func waitForStarts(_ count: Int, file: StaticString = #filePath, line: UInt = #line) async {
            if calls.count >= count { return }
            let value = XCTestExpectation(description: "Preference provider starts \(count)")
            starts.append((count, value))
            let result = await XCTWaiter.fulfillment(of: [value], timeout: 3)
            XCTAssertEqual(result, .completed, file: file, line: line)
        }
        func waitForReturns(_ count: Int, file: StaticString = #filePath, line: UInt = #line) async {
            if returned >= count { return }
            let value = XCTestExpectation(description: "Physical preference provider returns \(count)")
            returns.append((count, value))
            let result = await XCTWaiter.fulfillment(of: [value], timeout: 3)
            XCTAssertEqual(result, .completed, file: file, line: line)
        }
        func finish(_ index: Int, _ result: Result<Output, Error>) {
            pending.removeValue(forKey: index)?.resume(with: result)
        }
        func close() {
            let held = Array(pending.values); pending.removeAll()
            held.forEach { $0.resume(throwing: Failure.offline) }
        }
    }

    @MainActor private final class Deadlines {
        struct Entry { let fire: @MainActor () -> Void; var cancelled = false }
        var entries: [Entry] = []
        private var waiters: [(Int, XCTestExpectation)] = []
        func schedule(_ fire: @escaping @MainActor () -> Void) -> () -> Void {
            let index = entries.count; entries.append(.init(fire: fire))
            let ready = waiters.filter { $0.0 <= entries.count }
            waiters.removeAll { $0.0 <= entries.count }; ready.forEach { $0.1.fulfill() }
            return { [weak self] in self?.entries[index].cancelled = true }
        }
        func fire(_ index: Int) { if !entries[index].cancelled { entries[index].fire() } }
        func waitForSchedules(_ count: Int, file: StaticString = #filePath, line: UInt = #line) async {
            if entries.count >= count { return }
            let value = XCTestExpectation(description: "Preference UI deadline registered")
            waiters.append((count, value))
            let result = await XCTWaiter.fulfillment(of: [value], timeout: 3)
            XCTAssertEqual(result, .completed, file: file, line: line)
        }
    }

    @MainActor private final class Fixture {
        struct Read { let context: Model.ContextTicket; let original: Model.Guard }
        struct Write { let request: Model.SaveRequest; let original: Model.Guard }
        let canonical = CanonicalSessionState()
        let sdk: ReaderSDKStartupState
        let reads = Lane<Read, Model.ReadResult>()
        let writes = Lane<Write, Void>()
        let deadlines = Deadlines(), preparationDeadlines = Deadlines()
        var providerUID: String?
        var captures = 0, identities = 0, sdkStarts = 0
        var verification: [String] = [], refreshes: [String] = []
        lazy var service = ReaderPreferencesService(effects: .init(capturePermission: { [weak self] in
            guard let self else { return nil }
            self.captures += 1
            return self.sdk.captureReaderWork(identity: self.canonical, actualUserID: { [weak self] in self?.providerUID })
        }, identity: { [weak self] in
            guard let self else { return .init(actualUID: nil, canonicalUID: nil) }
            self.identities += 1
            return .init(actualUID: self.providerUID, canonicalUID: self.canonical.snapshot.userID)
        }, load: { [weak self] context, original in
            guard let self, original() else { throw CancellationError() }
            return try await self.reads.perform(.init(context: context, original: original))
        }, save: { [weak self] request, original in
            guard let self, original() else { throw CancellationError() }
            try await self.writes.perform(.init(request: request, original: original))
        }), schedule: { [deadlines] in deadlines.schedule($0) })
        var model: Model { service.model }
        lazy var actions = ReaderAccountActions(canonical: canonical, preferences: model,
            verify: { [weak self] context in self?.verification.append(context.userID ?? "guest") },
            refresh: { [weak self] context in self?.refreshes.append(context.userID ?? "guest") })
        init(guarded: Bool = false, uid: String? = "A") {
            sdk = guarded ? ReaderSDKStartupState() : .application
            providerUID = uid; _ = canonical.adopt(uid.map(Self.session))
        }
        static func session(_ uid: String) -> ReaderAccountSession {
            .init(uid: uid, email: "reader@example.invalid", isEmailVerified: false)
        }
        func start() {
            _ = service.changeAccountContext(userID: providerUID); service.start()
        }
        func select(_ uid: String?) {
            providerUID = uid
            _ = canonical.adopt(uid.map(Self.session))
            _ = service.changeAccountContext(userID: uid)
        }
        func load(parent: @escaping Model.Guard = { true }) -> Task<Void, Never> {
            let context = model.contextTicket(), service = service
            return Task { await service.loadCurrentContext(context, stillCurrent: parent) }
        }
        func read(_ index: Int, ids: [String]? = [], cached: Bool = false) {
            reads.finish(index, .success(.init(preferences: ids.map { ReaderPreferences(interestTopicIDs: $0) }, isFromCache: cached)))
        }
        func captureSave(_ ids: [String]) -> ReaderAccountActions.SaveAction? {
            actions.captureSave(ids: ids, userID: providerUID ?? "A", context: canonical.contextTicket())
        }
        func captureCommit(_ ids: [String]) -> (@MainActor () async -> Bool)? {
            actions.captureInterestCommit(ids: ids, userID: providerUID ?? "A", context: canonical.contextTicket(),
                scheduleLoadDeadline: { [preparationDeadlines] in preparationDeadlines.schedule($0) })
        }
        func close() { select(nil); reads.close(); writes.close() }
        func openGuardedStartup() async throws {
            let configuration = try Startup.Configuration(projectID: "local-preference-test", appID: "local-app",
                installationID: UUID(), writerFenceRevision: String(repeating: "a", count: 64),
                migrationRevision: String(repeating: "b", count: 64))
            let membership: @MainActor (Contract.MembershipRequest) async throws -> Contract.MembershipSnapshot = { request in
                let echo = try JSONSerialization.jsonObject(with: Contract.encode(request))
                let data = try JSONSerialization.data(withJSONObject: [
                    "schemaVersion": 1, "scope": Contract.membershipScope, "request": echo,
                    "membership": ["schemaVersion": 1, "ownerUID": request.expectedUID, "epoch": 4, "state": "active"],
                    "validUntilMs": 20_000
                ])
                return try Contract.decodeMembershipResponse(data: data, for: request)
            }
            let verify: Startup.Verifier = { challenge in
                .init(challenge: challenge, coverage: .allPersistedWritersIncludingPreviousAccounts,
                    writerFenceRevision: configuration.writerFenceRevision,
                    migrationRevision: configuration.migrationRevision, validUntilMs: 20_000)
            }
            let start: @MainActor (Startup.Receipt, @escaping Startup.StartAdmission) async throws -> Void = { [weak self] _, admit in
                try admit(); self?.sdkStarts += 1
            }
            let startup = Startup(canonical: canonical, sdkState: sdk, configuration: configuration,
                readMarker: { nil }, readMembership: membership, verify: verify, startSDK: start,
                now: { 10_000 }, schedule: { _ in {} })
            _ = try await startup.start(context: canonical.contextTicket())
        }
    }

    override func setUp() { super.setUp(); XCTAssertNil(FirebaseApp.allApps) }
    override func tearDown() { XCTAssertNil(FirebaseApp.allApps); super.tearDown() }
    private func loaded(_ f: Fixture, ids: [String] = ["before"]) async {
        let index = f.reads.calls.count, task = f.load()
        await f.reads.waitForStarts(index + 1)
        f.read(index, ids: ids); await task.value
        XCTAssertTrue(f.model.hasLoaded)
    }

    func testInertServiceAndClosedStartupDoNotPublishOrReadThenExplicitLoadUsesRealRelease() async throws {
        let f = Fixture(guarded: true); defer { f.close() }
        _ = f.service; _ = f.model
        XCTAssertEqual(f.captures, 0); XCTAssertEqual(f.identities, 0)
        f.start(); let before = f.model.snapshot
        await f.load().value
        XCTAssertEqual(f.model.snapshot, before); XCTAssertTrue(f.reads.calls.isEmpty)
        XCTAssertNil(f.captureSave(["music"])); XCTAssertNil(f.captureCommit(["music"]))
        XCTAssertTrue(f.writes.calls.isEmpty)
        try await f.openGuardedStartup()
        XCTAssertTrue(f.reads.calls.isEmpty, "Readiness does not manufacture a preference read")
        await loaded(f)
        XCTAssertEqual(f.sdkStarts, 1); XCTAssertEqual(f.reads.calls.count, 1)
        XCTAssertNotNil(f.captureSave(["music"]))
    }

    func testGuestCannotUsePreferenceProvidersWhileAuthOnlyActionsRemainUsableWithClosedReaderGate() async throws {
        let guest = Fixture(uid: nil); defer { guest.close() }; guest.start()
        await guest.load().value
        XCTAssertTrue(guest.reads.calls.isEmpty); XCTAssertNil(guest.captureSave(["music"]))
        let f = Fixture(guarded: true); defer { f.close() }; f.start()
        let owner = try XCTUnwrap(f.actions.captureOwner(userID: "A", context: f.canonical.contextTicket()))
        XCTAssertTrue(f.actions.isCurrent(owner)); XCTAssertFalse(f.actions.isCurrentReader(owner))
        let verified = await f.actions.sendVerification(owner), refreshed = try await f.actions.refresh(owner)
        XCTAssertTrue(verified); XCTAssertTrue(refreshed)
        XCTAssertEqual(f.verification, ["A"]); XCTAssertEqual(f.refreshes, ["A"])
        XCTAssertTrue(f.reads.calls.isEmpty); XCTAssertTrue(f.writes.calls.isEmpty)
        let retried = await f.actions.retry(owner)
        XCTAssertFalse(retried); XCTAssertTrue(f.reads.calls.isEmpty)
    }

    func testAuthParentDenialIsPreservedAcrossThePhysicalServiceRead() async throws {
        let f = Fixture(); defer { f.close() }; f.start()
        let before = f.model.snapshot, captures = f.captures
        await f.load(parent: { false }).value
        XCTAssertEqual(f.model.snapshot, before); XCTAssertEqual(f.captures, captures)
        var permitted = true
        let task = f.load(parent: { permitted }); await f.reads.waitForStarts(1)
        let original = try XCTUnwrap(f.reads.calls.first).original
        permitted = false; XCTAssertFalse(original()); permitted = true
        XCTAssertFalse(original()); XCTAssertEqual(f.reads.active, 1)
        f.read(0, ids: ["denied"]); await task.value
        XCTAssertFalse(f.model.hasLoaded); XCTAssertFalse(f.model.isLoading)
        XCTAssertTrue(f.model.preferences.interestTopicIDs.isEmpty); XCTAssertNil(f.model.errorMessage)
        XCTAssertTrue(f.writes.calls.isEmpty)
    }

    func testFormEventCannotRecaptureReaderAuthorityWhenItsTaskStartsLater() async throws {
        let f = Fixture(); defer { f.close() }; f.start(); await loaded(f)
        var selected = ["original"]
        let action = try XCTUnwrap(f.captureSave(selected)); selected = ["new-form"]
        f.providerUID = "B"
        let denied = await f.actions.save(action)
        XCTAssertFalse(denied); XCTAssertTrue(f.writes.calls.isEmpty)
        f.providerUID = "A"
        let replayed = await f.actions.save(action)
        XCTAssertFalse(replayed); XCTAssertFalse(f.actions.isCurrentReceipt(action))
        let fresh = try XCTUnwrap(f.captureSave(selected)), save = Task { await f.actions.save(fresh) }
        await f.writes.waitForStarts(1)
        XCTAssertEqual(f.writes.calls.first?.request.preferences.interestTopicIDs, ["new-form"])
        f.writes.finish(0, .success(())); let accepted = await save.value
        XCTAssertTrue(accepted); XCTAssertTrue(f.actions.isCurrentReceipt(fresh))
    }

    func testCacheAbsenceFailsWithoutFallbackAndExplicitRetryNeedsActualAuthoritativeResult() async throws {
        let f = Fixture(); defer { f.close() }; f.start()
        let first = f.load(); await f.reads.waitForStarts(1)
        f.read(0, ids: nil, cached: true); await first.value
        XCTAssertEqual(f.reads.calls.count, 1, "This adapter does not add a server fallback")
        XCTAssertFalse(f.model.hasLoaded); XCTAssertNotNil(f.model.errorMessage)
        XCTAssertNil(f.captureSave(["music"])); XCTAssertTrue(f.writes.calls.isEmpty)
        let owner = try XCTUnwrap(f.actions.captureOwner(userID: "A", context: f.canonical.contextTicket()))
        let retry = Task { await f.actions.retry(owner) }; await f.reads.waitForStarts(2)
        f.read(1, ids: nil, cached: false); let recovered = await retry.value
        XCTAssertTrue(recovered); XCTAssertTrue(f.model.hasLoaded)
        XCTAssertFalse(f.model.preferences.onboardingCompleted); XCTAssertTrue(f.writes.calls.isEmpty)
        XCTAssertNotNil(f.captureSave(["music"]))
    }

    func testFailedReloadKeepsLastValuesButExplicitRetryMustConfirmThemBeforeAnySave() async throws {
        let f = Fixture(); defer { f.close() }; f.start(); await loaded(f, ids: ["kept"])
        let owner = try XCTUnwrap(f.actions.captureOwner(userID: "A", context: f.canonical.contextTicket()))
        let failed = Task { await f.actions.retry(owner) }; await f.reads.waitForStarts(2)
        f.reads.finish(1, .failure(Failure.offline)); let failedResult = await failed.value
        XCTAssertFalse(failedResult); XCTAssertEqual(f.model.preferences.interestTopicIDs, ["kept"])
        XCTAssertFalse(f.model.hasLoaded); XCTAssertNotNil(f.model.errorMessage); XCTAssertNil(f.captureSave(["unsafe"]))
        let retry = Task { await f.actions.retry(owner) }; await f.reads.waitForStarts(3)
        f.read(2, ids: ["confirmed"]); let accepted = await retry.value
        XCTAssertTrue(accepted); XCTAssertNil(f.model.errorMessage)
        XCTAssertEqual(f.model.preferences.interestTopicIDs, ["confirmed"]); XCTAssertTrue(f.writes.calls.isEmpty)
    }

    func testCapturedIntroductionJoinsAuthReadAndWaitsForAcknowledgementOfOriginalSelection() async throws {
        let f = Fixture(); defer { f.close() }; f.start()
        let auth = f.load(); await f.reads.waitForStarts(1)
        var selected = ["music", "culture"]
        let operation = try XCTUnwrap(f.captureCommit(selected)); selected = ["film"]
        var result: Bool?
        let commit = Task { let value = await operation(); result = value; return value }
        await f.preparationDeadlines.waitForSchedules(1)
        XCTAssertEqual(f.reads.calls.count, 1); XCTAssertTrue(f.writes.calls.isEmpty)
        f.read(0, ids: nil); await auth.value; await f.writes.waitForStarts(1)
        XCTAssertNil(result); XCTAssertEqual(f.writes.calls.first?.request.preferences.interestTopicIDs, ["culture", "music"])
        XCTAssertEqual(f.writes.calls.first?.request.preferences.onboardingCompleted, true)
        f.writes.finish(0, .success(())); let accepted = await commit.value
        XCTAssertTrue(accepted); XCTAssertEqual(selected, ["film"])
        XCTAssertEqual(f.model.preferences.interestTopicIDs, ["culture", "music"])
        let replayed = await operation()
        XCTAssertFalse(replayed); XCTAssertEqual(f.writes.calls.count, 1)
    }

    func testCapturedIntroductionCannotAdoptAFreshPermitAfterObservedSameUIDDenial() async throws {
        let f = Fixture(); defer { f.close() }; f.start(); await loaded(f)
        let stale = try XCTUnwrap(f.captureCommit(["old-intro"]))
        f.providerUID = "B"; let first = await stale()
        XCTAssertFalse(first); XCTAssertTrue(f.writes.calls.isEmpty)
        f.providerUID = "A"; let replayed = await stale()
        XCTAssertFalse(replayed); XCTAssertTrue(f.writes.calls.isEmpty)
        let fresh = try XCTUnwrap(f.captureCommit(["fresh-intro"])), commit = Task { await fresh() }
        await f.writes.waitForStarts(1); f.writes.finish(0, .success(()))
        let accepted = await commit.value; XCTAssertTrue(accepted)
        XCTAssertEqual(f.model.preferences.interestTopicIDs, ["fresh-intro"])
    }

    func testPreparationRetainsDeniedOwnerEvenWhenIndependentAuthLoadSuccessfullyFinishes() async throws {
        let f = Fixture(); defer { f.close() }; f.start()
        let auth = f.load(); await f.reads.waitForStarts(1)
        let owner = try XCTUnwrap(f.actions.captureOwner(userID: "A", context: f.canonical.contextTicket()))
        let preparation = ReaderInterestCommitPreparation(canonical: f.canonical, preferences: f.model,
            actions: f.actions, owner: owner, schedule: { f.preparationDeadlines.schedule($0) })
        let waiting = Task { await preparation.prepare() }
        await f.preparationDeadlines.waitForSchedules(1)
        f.providerUID = "B"; XCTAssertFalse(f.actions.isCurrentReader(owner)); f.providerUID = "A"
        XCTAssertFalse(f.actions.isCurrentReader(owner))
        // Auth's separate read never observed the transient denial and may
        // validly load. It cannot lend its authority to the older UI operation.
        f.read(0, ids: ["auth-confirmed"]); await auth.value
        let ready = await waiting.value
        XCTAssertFalse(ready); XCTAssertTrue(f.model.hasLoaded)
        XCTAssertEqual(f.model.preferences.interestTopicIDs, ["auth-confirmed"])
        XCTAssertTrue(f.writes.calls.isEmpty); XCTAssertNotNil(f.captureCommit(["explicit-new-attempt"]))
    }

    func testWriteDeadlineDoesNotReleasePhysicalSlotOrCreateAReceipt() async throws {
        let f = Fixture(); defer { f.close() }; f.start(); await loaded(f)
        let first = try XCTUnwrap(f.captureSave(["timed-out"])), writing = Task { await f.actions.save(first) }
        await f.writes.waitForStarts(1); f.deadlines.fire(0)
        let timedOut = await writing.value
        // The form only queries receipt currency after a true save result.
        // A timeout is false, so it cannot create a stored success receipt.
        XCTAssertFalse(timedOut)
        XCTAssertTrue(f.model.activity.activeSave); XCTAssertEqual(f.writes.active, 1)
        XCTAssertEqual(f.model.preferences.interestTopicIDs, ["before"])
        let second = try XCTUnwrap(f.captureSave(["explicit-retry"])), retry = Task { await f.actions.save(second) }
        await f.deadlines.waitForSchedules(2)
        XCTAssertEqual(f.writes.calls.count, 1); XCTAssertTrue(f.model.activity.pendingSave)
        f.writes.finish(0, .success(())); await f.writes.waitForStarts(2)
        XCTAssertEqual(f.model.preferences.interestTopicIDs, ["before"])
        f.writes.finish(1, .success(())); let accepted = await retry.value
        XCTAssertTrue(accepted); XCTAssertTrue(f.actions.isCurrentReceipt(second))
        XCTAssertEqual(f.model.preferences.interestTopicIDs, ["explicit-retry"])
    }

    func testHeldOldReadCannotPublishAfterAccountRoundTripOrBorrowGuardedStartup() async throws {
        for guarded in [false, true] {
            let f = Fixture(guarded: guarded); defer { f.close() }; f.start()
            if guarded { try await f.openGuardedStartup() }
            let task = f.load(); await f.reads.waitForStarts(1)
            let original = try XCTUnwrap(f.reads.calls.first).original
            f.select("B"); f.select("A")
            XCTAssertFalse(original()); XCTAssertEqual(f.reads.active, 1)
            await task.value
            if guarded {
                await f.load().value
                XCTAssertEqual(f.reads.calls.count, 1)
                XCTAssertFalse(f.sdk.permitsReaderServices(identity: f.canonical))
            } else { await loaded(f, ids: ["new-A"]) }
            let current = f.model.snapshot
            f.read(0, ids: ["old-A"]); await f.reads.waitForReturns(guarded ? 1 : 2)
            XCTAssertEqual(f.model.snapshot, current); XCTAssertTrue(f.writes.calls.isEmpty)
        }
    }

    func testHeldOldWriteBlocksNewAccountRoundTripSaveUntilActualReturn() async throws {
        let f = Fixture(); defer { f.close() }; f.start(); await loaded(f)
        let old = try XCTUnwrap(f.captureSave(["old-A"])), oldTask = Task { await f.actions.save(old) }
        await f.writes.waitForStarts(1)
        f.select(nil); f.select("A"); await loaded(f, ids: ["new-owner"])
        let current = try XCTUnwrap(f.captureSave(["new-A"])), currentTask = Task { await f.actions.save(current) }
        await f.deadlines.waitForSchedules(2)
        let stale = await oldTask.value
        XCTAssertFalse(stale); XCTAssertEqual(f.writes.calls.count, 1); XCTAssertEqual(f.writes.active, 1)
        XCTAssertFalse(f.actions.isCurrentReceipt(old))
        f.writes.finish(0, .failure(Failure.offline)); await f.writes.waitForStarts(2)
        XCTAssertNil(f.model.errorMessage); XCTAssertEqual(f.model.preferences.interestTopicIDs, ["new-owner"])
        f.writes.finish(1, .success(())); let accepted = await currentTask.value
        XCTAssertTrue(accepted); XCTAssertTrue(f.actions.isCurrentReceipt(current))
    }

    func testWillChangeDenialCannotPublishReadValuesAndExplicitRetryIsStillPossible() async {
        let f = Fixture(); defer { f.close() }; f.start()
        let task = f.load(); await f.reads.waitForStarts(1)
        var changed = false
        let observation = f.model.objectWillChange.sink {
            if !changed { changed = true; f.providerUID = "B" }
        }
        f.read(0, ids: ["must-not-publish"]); await task.value
        XCTAssertTrue(changed); XCTAssertFalse(f.model.hasLoaded); XCTAssertFalse(f.model.isLoading)
        XCTAssertTrue(f.model.preferences.interestTopicIDs.isEmpty); XCTAssertNil(f.model.errorMessage)
        f.providerUID = "A"; await loaded(f, ids: ["fresh"])
        XCTAssertEqual(f.model.preferences.interestTopicIDs, ["fresh"])
        withExtendedLifetime(observation) {}
    }

    func testConfirmedReceiptIsRevokedByObservedProviderDenialAndByFreshLoad() async throws {
        for providerDenial in [false, true] {
            let f = Fixture(); defer { f.close() }; f.start(); await loaded(f)
            let action = try XCTUnwrap(f.captureSave(["saved"])), task = Task { await f.actions.save(action) }
            XCTAssertFalse(f.actions.isCurrentReceipt(action))
            await f.writes.waitForStarts(1); f.writes.finish(0, .success(()))
            let accepted = await task.value
            XCTAssertTrue(accepted); XCTAssertTrue(f.actions.isCurrentReceipt(action))
            if providerDenial {
                f.providerUID = "B"; XCTAssertFalse(f.actions.isCurrentReceipt(action)); f.providerUID = "A"
                XCTAssertFalse(f.actions.isCurrentReceipt(action), "An observed denied original receipt cannot revive")
            } else {
                await loaded(f, ids: ["new-load"])
                XCTAssertFalse(f.actions.isCurrentReceipt(action))
            }
        }
    }
    func testForegroundRefreshMovesAcknowledgedChoicesBetweenTwoLocalServiceInstances() async throws {
        let first = Fixture(), second = Fixture()
        defer { first.close(); second.close() }
        first.start(); second.start()
        await loaded(first, ids: ["original"]); await loaded(second, ids: ["original"])
        let save = try XCTUnwrap(first.captureSave(["music", "film"]))
        let writing = Task { await first.actions.save(save) }
        await first.writes.waitForStarts(1)
        let persisted = try XCTUnwrap(first.writes.calls.first).request.preferences
        first.writes.finish(0, .success(()))
        let accepted = await writing.value; XCTAssertTrue(accepted)
        XCTAssertEqual(second.model.preferences.interestTopicIDs, ["original"])
        let refresh = try XCTUnwrap(second.service.refreshAfterInterruption())
        await second.reads.waitForStarts(2)
        XCTAssertFalse(second.model.isLoading); XCTAssertTrue(second.model.hasLoaded)
        second.reads.finish(1, .success(.init(preferences: persisted, isFromCache: false)))
        await refresh.value
        XCTAssertEqual(second.model.preferences, persisted)
        XCTAssertTrue(second.writes.calls.isEmpty, "Refresh is read-only; no automatic save")
    }

    func testLifecycleRefreshIsInertWhenUnstartedGuestOrStartupClosed() {
        let unstarted = Fixture(), closed = Fixture(guarded: true), guest = Fixture(uid: nil)
        defer { unstarted.close(); closed.close(); guest.close() }
        closed.start(); guest.start()
        for f in [unstarted, closed, guest] {
            XCTAssertNil(f.service.refreshAfterInterruption())
            XCTAssertTrue(f.reads.calls.isEmpty); XCTAssertTrue(f.writes.calls.isEmpty)
        }
    }

    func testLifecycleRefreshCapturesAccountBeforeTaskAndCannotBorrowRoundTripIdentity() async throws {
        let f = Fixture(); defer { f.close() }; f.start(); await loaded(f)
        let refresh = try XCTUnwrap(f.service.refreshAfterInterruption())
        f.select("B"); f.select("A")
        await refresh.value
        XCTAssertEqual(f.reads.calls.count, 1, "No stale task may reach the provider")
        await loaded(f, ids: ["fresh-A"])
        XCTAssertEqual(f.model.preferences.interestTopicIDs, ["fresh-A"])
    }

    func testReconnectAndForegroundCoalesceAndCachedOrFailedRefreshPreservesLoadedSelection() async throws {
        let f = Fixture(); defer { f.close() }; f.start(); await loaded(f)
        let before = f.model.snapshot
        let refresh = try XCTUnwrap(f.service.refreshAfterInterruption())
        XCTAssertNil(f.service.refreshAfterInterruption())
        await f.reads.waitForStarts(2)
        XCTAssertNil(f.service.refreshAfterInterruption())
        f.read(1, ids: ["cached-old"], cached: true); await refresh.value
        XCTAssertEqual(f.model.snapshot, before)
        let retry = try XCTUnwrap(f.service.refreshAfterInterruption())
        await f.reads.waitForStarts(3)
        f.reads.finish(2, .failure(Failure.offline)); await retry.value
        XCTAssertEqual(f.model.snapshot, before)
    }

    func testLifecycleRefreshDoesNotClearTimedOutSaveOrReleasePhysicalWrite() async throws {
        let f = Fixture(); defer { f.close() }; f.start(); await loaded(f)
        let action = try XCTUnwrap(f.captureSave(["mine"]))
        XCTAssertNil(f.service.refreshAfterInterruption(), "Captured local save has priority before its Task")
        let task = Task { await f.actions.save(action) }
        await f.writes.waitForStarts(1); f.deadlines.fire(0)
        let saved = await task.value; XCTAssertFalse(saved)
        let before = f.model.snapshot
        XCTAssertNil(f.service.refreshAfterInterruption())
        XCTAssertEqual(f.model.snapshot, before); XCTAssertEqual(f.writes.active, 1)
        f.writes.finish(0, .failure(Failure.offline)); await f.writes.waitForReturns(1)
        XCTAssertNil(f.service.refreshAfterInterruption(), "Unconfirmed save stays explicit; background refresh cannot hide it")
        XCTAssertEqual(f.reads.calls.count, 1)
    }

    func testLifecycleRefreshCanRecoverInitialLoadFailureWithoutManualRetry() async throws {
        let f = Fixture(); defer { f.close() }; f.start()
        let first = f.load(); await f.reads.waitForStarts(1)
        f.reads.finish(0, .failure(Failure.offline)); await first.value
        XCTAssertFalse(f.model.hasLoaded); XCTAssertNotNil(f.model.errorMessage)
        let refresh = try XCTUnwrap(f.service.refreshAfterInterruption())
        await f.reads.waitForStarts(2)
        f.read(1, ids: ["recovered"]); await refresh.value
        XCTAssertTrue(f.model.hasLoaded); XCTAssertNil(f.model.errorMessage)
        XCTAssertEqual(f.model.preferences.interestTopicIDs, ["recovered"])
    }

    func testRejectedFormSaveRetiresOnlyItsCaptureSoLifecycleRefreshCanResume() async throws {
        let f = Fixture(); defer { f.close() }; f.start(); await loaded(f)
        let save = try XCTUnwrap(f.captureSave(["abandoned"]))
        f.providerUID = "B"
        let rejected = await f.actions.save(save); XCTAssertFalse(rejected)
        f.providerUID = "A"
        let refresh = try XCTUnwrap(f.service.refreshAfterInterruption())
        await f.reads.waitForStarts(2); f.read(1, ids: ["fresh"]); await refresh.value
        XCTAssertEqual(f.model.preferences.interestTopicIDs, ["fresh"])
        XCTAssertTrue(f.writes.calls.isEmpty)
    }

}
