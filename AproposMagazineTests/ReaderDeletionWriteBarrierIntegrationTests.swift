import Combine
import FirebaseCore
import XCTest
@testable import Apropos

/// Actual Auth composition, writer runtime, and file journal. The SDK's
/// physical completions and HTTP reply are injected; no service is initialized.
@MainActor
final class ReaderDeletionWriteBarrierIntegrationTests: XCTestCase {
    private typealias Model = ReaderAccountDeletionCoordinator
    private typealias Contract = ReaderAccountDeletionContract
    private typealias Bridge = ReaderAccountReauthentication<String>
    private enum Failure: Error { case local, malformedRequest }
    private enum Stage: Hashable { case provider, credentials, http }

    private final class User {
        let uid: String
        init(_ uid: String) { self.uid = uid }
    }

    /// Holds only the actual utility-queue file replacement, never MainActor.
    private final class DiskControl: @unchecked Sendable {
        private let lock = NSLock(), semaphore = DispatchSemaphore(value: 0)
        private var armed = false, failRead = false, count = 0, active = 0, failedReads = 0
        var starts: Int { lock.lock(); defer { lock.unlock() }; return count }
        var isIdle: Bool { lock.lock(); defer { lock.unlock() }; return active == 0 }
        var readFailures: Int { lock.lock(); defer { lock.unlock() }; return failedReads }
        func arm() { lock.lock(); armed = true; lock.unlock() }
        func setReadFailure(_ value: Bool) { lock.lock(); failRead = value; lock.unlock() }
        func legacy() throws -> Data? {
            lock.lock(); let fails = failRead; if fails { failedReads += 1 }; lock.unlock()
            if fails { throw FavoritesJournalFailure.readFailed }
            return nil
        }
        func release() { semaphore.signal() }
        func replace(_ data: Data, _ url: URL) throws {
            lock.lock(); let hold = armed; armed = false; count += 1; active += 1; lock.unlock()
            defer { lock.lock(); active -= 1; lock.unlock() }
            if hold, semaphore.wait(timeout: .now() + 5) != .success { throw FavoritesJournalFailure.writeFailed }
            try data.write(to: url, options: .atomic)
        }
    }

    @MainActor private final class Gate {
        var entered = false
        private var continuation: CheckedContinuation<Void, Never>?
        func wait() async { await withCheckedContinuation { continuation = $0; entered = true } }
        func release() { let original = continuation; continuation = nil; original?.resume() }
    }

    @MainActor private final class Fixture {
        let auth = AuthService()
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("deletion-barrier-" + UUID().uuidString)
        let disk = DiskControl()
        lazy var recovery = ReaderTransitionRecovery(store: .init(rootDirectory: directory.appendingPathComponent("transition")))
        let configuration: ReaderDeletionHTTPTransport.Configuration
        var user: User? = User("reader-A")
        var epoch: Int64? = 7
        var now: Int64 = 1_800_000_000_123
        var actions: [Model.ActionTicket] = []
        var reauths = 0, credentialCalls = 0, drainFactories = 0
        var writes: [ReaderWriterDrainCoordinator.Completion] = []
        var drains: [ReaderWriterDrainCoordinator.Completion] = []
        var drainDeadlines: [@MainActor () -> Void] = []
        var deadlines: [@MainActor () -> Void] = []
        var requests: [URLRequest] = []
        var models: [Model] = []
        var holds: [Stage: Gate] = [:], gates: [Gate] = []
        var replyStatuses: [Int: String] = [:]
        var httpError: Error?
        var onHeldUser: (() -> Void)?, onActualUID: (() -> Void)?
        var onReauthenticated: (() -> Void)?, onDrainFactory: (() -> Void)?
        lazy var journal = FavoritesFileJournal(rootDirectory: directory,
            legacyRead: { [disk] _ in try disk.legacy() }, replace: { [disk] in try disk.replace($0, $1) })
        lazy var writers = ReaderWriterDrainRuntime(canonical: auth.state, actualUID: { [unowned self] in
            let original = user?.uid; onActualUID?(); return original
        },
            schedule: { [unowned self] fire in drainDeadlines.append(fire); return {} },
            makeDrain: { [unowned self] in
                drainFactories += 1; onDrainFactory?()
                return .init(wait: { [unowned self] completion in drains.append(completion) })
            })
        lazy var operations = AuthOperationCoordinator(canonical: auth.state, actualUserID: { [unowned self] in user?.uid })
        lazy var bridge = Bridge(canonical: auth.state, operations: operations, captureUser: { [unowned self] in
            guard let original = user else { return nil }
            return .init(uid: original.uid, isCurrent: { [unowned self] in
                let current = user === original; onHeldUser?(); return current
            }, reauthenticate: { [unowned self] _, admitted in
                guard admitted() else { throw CancellationError() }
                reauths += 1
                return .init(uid: original.uid, authTimeMs: (now / 1_000) * 1_000)
            }, deletionCredentials: { [unowned self] proof, _ in
                credentialCalls += 1; await pass(.credentials)
                return .init(ownerUID: original.uid, projectID: "local-deletion", appID: "1:123456789:ios:abcdef123456",
                    idToken: "local.id." + proof.action.actionID.uuidString,
                    appCheckToken: "local.app." + proof.action.actionID.uuidString,
                    authTimeMs: proof.authTimeMs, authValidUntilMs: now + 60_000, appCheckValidUntilMs: now + 60_000)
            })
        }, nowMilliseconds: { [unowned self] in now })

        init() throws {
            configuration = try .init(projectID: "local-deletion", appID: "1:123456789:ios:abcdef123456",
                endpointURL: URL(string: "https://deletion.example.invalid/reader")!)
            select("reader-A")
        }
        var context: CanonicalSessionState.ContextTicket { auth.state.contextTicket() }
        var namespace: FavoritesNamespace { FavoritesContext.confirmed(userID: "reader-A").namespace! }
        func select(_ uid: String?) {
            if user?.uid != uid { user = uid.map(User.init) }
            auth.state.adopt(uid.map { .init(uid: $0, email: "local@example.invalid", isEmailVerified: true) })
        }
        func roundTrip() { select("reader-B"); select("reader-A") }
        func hold(_ stage: Stage) -> Gate {
            let gate = Gate(); holds[stage] = gate; gates.append(gate); return gate
        }
        func pass(_ stage: Stage) async { if let gate = holds.removeValue(forKey: stage) { await gate.wait() } }
        func make(includeBarrier: Bool = true) -> Model? {
            let model = auth.makeReaderAccountDeletion(configuration: configuration,
                currentMembershipEpoch: { [unowned self] _ in epoch },
                reauthentication: bridge, obtainCredential: { [unowned self] action in
                    actions.append(action); await pass(.provider); return "local-credential"
                }, reauthenticationFinished: { [unowned self] _, error in if error == nil { onReauthenticated?() } },
                execute: { [unowned self] request in
                    let index = requests.count; requests.append(request); await pass(.http)
                    if let httpError { throw httpError }
                    return try response(request, index: index)
                }, now: { [unowned self] in now }, scheduleTimeout: { [unowned self] _, fire in
                    deadlines.append(fire); return {}
                }, writeBarrier: includeBarrier ? .init(writers: writers, journal: journal, recovery: recovery) : nil)
            if let model { models.append(model) }
            return model
        }
        func begin(_ model: Model) -> Bool { model.begin(context: context, membershipEpoch: epoch ?? 7, userConfirmed: true) }
        func startWrite() -> Task<Bool, Never> {
            let original = context
            return Task { @MainActor [self] in
                do {
                    try await writers.performWrite(expectedUserID: original.userID!,
                        stillCurrent: { self.auth.state.isCurrent(original) }, start: { [self] admitted, complete in
                            guard admitted() else { complete(CancellationError()); return }
                            writes.append(complete)
                        })
                    return true
                } catch { return false }
            }
        }
        func captureNewWrite() -> ReaderWriterDrainRuntime.CapturedWrite? {
            writers.captureWrite(expectedUserID: "reader-A", stillCurrent: { true }, start: { _, _ in
                XCTFail("An unexecuted capture must not start a write")
            })
        }
        func read(_ namespace: FavoritesNamespace? = nil) async throws -> FavoritesRecord? {
            try await withCheckedThrowingContinuation { continuation in
                journal.storage.read(namespace ?? self.namespace) { continuation.resume(with: $0) }
            }
        }
        func write(_ record: FavoritesRecord, expected: UUID?, namespace: FavoritesNamespace? = nil) async throws {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                journal.storage.write(namespace ?? self.namespace, record, expected) { continuation.resume(with: $0) }
            }
        }
        func file(_ namespace: FavoritesNamespace? = nil) -> URL {
            directory.appendingPathComponent((namespace ?? self.namespace).recordBinding + ".json")
        }
        func response(_ request: URLRequest, index: Int) throws -> (Data, HTTPURLResponse) {
            guard let data = request.httpBody, let body = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let uid = body["expectedUID"] as? String, let epoch = body["membershipEpoch"] as? Int64,
                  let url = request.url else { throw Failure.malformedRequest }
            let parent = try Contract.Request(expectedUID: uid, membershipEpoch: epoch)
            let ledger = body["scope"] as? String == Contract.ledgerScope
            let status = replyStatuses[index] ?? (ledger ? "ledgerDataRemoved" : "scopedCloudDataRemoved")
            let requestID: String
            if ledger {
                requestID = try Contract.LedgerRequest(expectedUID: uid, membershipEpoch: epoch,
                    parentRequestID: try XCTUnwrap(body["parentRequestID"] as? String)).requestID
            } else { requestID = parent.requestID }
            var reply: [String: Any] = ["requestID": requestID, "scope": ledger ? Contract.ledgerScope : Contract.scope,
                "status": status, "accountDeletionComplete": false,
                "unresolved": ledger ? Contract.ledgerUnresolved : Contract.unresolved]
            if status == "scopedCloudDataRemoved" { reply["removedFavoriteDocuments"] = 3 }
            if status == "ledgerDataRemoved" {
                reply["parentRequestID"] = parent.requestID
                reply["removedReceiptDocuments"] = 2; reply["removedRevisionDocuments"] = 1
            }
            guard let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]) else { throw Failure.malformedRequest }
            return (try JSONSerialization.data(withJSONObject: reply), response)
        }
        func close() async {
            onHeldUser = nil; onActualUID = nil; onReauthenticated = nil; onDrainFactory = nil
            models.forEach { $0.cancel() }; gates.forEach { $0.release() }; disk.release()
            writes.forEach { $0(CancellationError()) }; drains.forEach { $0(CancellationError()) }
            for _ in 0..<2_000 {
                if models.allSatisfy({ !$0.hasPhysicalFlight }) && writers.isPhysicallyIdle && disk.isIdle { break }
                try? await Task.sleep(nanoseconds: 1_000_000)
            }
            try? FileManager.default.removeItem(at: directory)
        }
    }

    override func setUp() { super.setUp(); XCTAssertNil(FirebaseApp.allApps) }
    override func tearDown() { XCTAssertNil(FirebaseApp.allApps); super.tearDown() }
    private func fixture() async throws -> Fixture {
        let f = try Fixture()
        try await f.recovery.bootstrap()
        addTeardownBlock { @MainActor in await f.close() }
        let initial = try await f.read(); XCTAssertNil(initial)
        return f
    }
    private func eventually(_ condition: () -> Bool, file: StaticString = #filePath, line: UInt = #line) async {
        for _ in 0..<2_000 { if condition() { return }; try? await Task.sleep(nanoseconds: 1_000_000) }
        XCTFail("Injected physical stage was not reached", file: file, line: line)
    }
    private func assertFrozen(_ f: Fixture, file: StaticString = #filePath, line: UInt = #line) async {
        do { _ = try await f.read(); XCTFail("Original journal reopened", file: file, line: line) }
        catch { XCTAssertEqual(error as? FavoritesFileJournal.TransitionFailure, .frozen, file: file, line: line) }
    }
    private func record(_ id: String) -> FavoritesRecord {
        .init(articles: [.init(id: id, name: "Private favorite", slug: id, content: "", intro: "", topicID: "topic", contentRevision: "r1")])
    }

    func testMissingBarrierIsClosedBeforeReauthenticationOrSDKLookup() async throws {
        let f = try await fixture()
        XCTAssertNil(f.make(includeBarrier: false))
        XCTAssertTrue(f.actions.isEmpty); XCTAssertEqual(f.reauths, 0)
        XCTAssertTrue(f.requests.isEmpty); XCTAssertEqual(f.drainFactories, 0)
        XCTAssertNotNil(f.captureNewWrite())
    }

    func testActualSDKWriteAndDrainBothReturnBeforeFirstDeletionHTTP() async throws {
        let f = try await fixture(), write = f.startWrite()
        await eventually { f.writes.count == 1 }
        let model = try XCTUnwrap(f.make()); XCTAssertTrue(f.begin(model))
        await eventually { model.hasWriteBarrier }
        XCTAssertNil(f.captureNewWrite()); await assertFrozen(f)
        XCTAssertTrue(f.requests.isEmpty); XCTAssertTrue(f.drains.isEmpty)
        f.writes[0](nil)
        let writeSucceeded = await write.value; XCTAssertTrue(writeSucceeded)
        await eventually { f.drains.count == 1 }
        XCTAssertTrue(f.requests.isEmpty); XCTAssertFalse(model.abortBeforeSubmission())
        f.drains[0](nil)
        await eventually { model.status == .scopedCloudDataRemoved && !model.hasPhysicalFlight }
        XCTAssertEqual(f.requests.count, 1); XCTAssertTrue(model.hasWriteBarrier)
        XCTAssertNil(f.captureNewWrite()); XCTAssertFalse(model.abortBeforeSubmission())
        XCTAssertFalse(model.accountDeletionComplete)
    }

    func testQueuedRealJournalWritesFinishBeforeSnapshotDrainAndHTTPWithoutPurgingBytes() async throws {
        let f = try await fixture(), first = record("first"), second = record("second")
        f.disk.arm()
        var firstDone = false, secondDone = false
        f.journal.storage.write(f.namespace, first, nil) { result in
            if case .failure(let error) = result { XCTFail("Journal write failed: \(error)") }; firstDone = true
        }
        await eventually { f.disk.starts == 1 }
        f.journal.storage.write(f.namespace, second, first.recordRevision) { result in
            if case .failure(let error) = result { XCTFail("Journal write failed: \(error)") }; secondDone = true
        }
        let model = try XCTUnwrap(f.make()); XCTAssertTrue(f.begin(model))
        await eventually { model.hasWriteBarrier }
        XCTAssertFalse(firstDone); XCTAssertFalse(secondDone)
        XCTAssertTrue(f.drains.isEmpty); XCTAssertTrue(f.requests.isEmpty)
        await assertFrozen(f)
        f.disk.release()
        await eventually { firstDone && secondDone && f.drains.count == 1 }
        XCTAssertEqual(try FavoritesRecordCodec.decode(Data(contentsOf: f.file()), namespace: f.namespace), second)
        f.drains[0](nil)
        await eventually { model.status == .scopedCloudDataRemoved && !model.hasPhysicalFlight }
        XCTAssertEqual(try FavoritesRecordCodec.decode(Data(contentsOf: f.file()), namespace: f.namespace), second)
        XCTAssertFalse(model.accountDeletionComplete)
    }

    func testJournalFreezeRejectsNewWriteBeforeItsPhysicalReplacement() async throws {
        let f = try await fixture(), model = try XCTUnwrap(f.make())
        XCTAssertTrue(f.begin(model)); await eventually { f.drains.count == 1 }
        do { try await f.write(record("late"), expected: nil); XCTFail("Frozen source accepted new data") }
        catch { XCTAssertEqual(error as? FavoritesFileJournal.TransitionFailure, .frozen) }
        XCTAssertEqual(f.disk.starts, 0); XCTAssertTrue(f.requests.isEmpty)
        f.drains[0](nil)
        await eventually { !model.hasPhysicalFlight }
    }

    func testDrainDeadlineKeepsPhysicalSlotAndExplicitAbortWaitsForActualCallback() async throws {
        let f = try await fixture(), model = try XCTUnwrap(f.make())
        XCTAssertTrue(f.begin(model)); await eventually { f.drains.count == 1 }
        try XCTUnwrap(f.drainDeadlines.last)()
        for _ in 0..<10 { await Task.yield() }
        XCTAssertTrue(model.hasPhysicalFlight); XCTAssertFalse(model.canRetry)
        XCTAssertTrue(model.hasWriteBarrier); XCTAssertFalse(f.writers.isPhysicallyIdle)
        XCTAssertFalse(model.abortBeforeSubmission()); XCTAssertNil(f.make())
        XCTAssertTrue(f.requests.isEmpty); XCTAssertNil(f.captureNewWrite())
        f.drains[0](nil); await eventually { f.writers.isPhysicallyIdle && !model.hasPhysicalFlight }
        XCTAssertTrue(model.abortBeforeSubmission()); XCTAssertFalse(model.hasWriteBarrier)
        XCTAssertNotNil(f.captureNewWrite()); let restored = try await f.read(); XCTAssertNil(restored)
    }

    func testCoordinatorCancellationDuringPhysicalDrainCannotPrematurelyReopenEitherBoundary() async throws {
        let f = try await fixture(), model = try XCTUnwrap(f.make())
        XCTAssertTrue(f.begin(model)); await eventually { f.drains.count == 1 }
        model.cancel(); for _ in 0..<10 { await Task.yield() }
        XCTAssertTrue(model.hasPhysicalFlight); XCTAssertFalse(model.canRetry)
        XCTAssertTrue(model.hasWriteBarrier); XCTAssertFalse(model.abortBeforeSubmission())
        XCTAssertNil(f.captureNewWrite()); await assertFrozen(f)
        f.drains[0](nil); await eventually { f.writers.isPhysicallyIdle && !model.hasPhysicalFlight }
        XCTAssertTrue(model.abortBeforeSubmission()); let restored = try await f.read(); XCTAssertNil(restored)
        XCTAssertTrue(f.requests.isEmpty)
    }

    func testWholeActionDeadlineDuringDrainLeavesClosedResourcesUntilResolvedExplicitAbort() async throws {
        let f = try await fixture(), model = try XCTUnwrap(f.make())
        XCTAssertTrue(f.begin(model)); await eventually { f.drains.count == 1 }
        try XCTUnwrap(f.deadlines.last)()
        await eventually { model.status == .timedOut }
        XCTAssertTrue(model.hasPhysicalFlight); XCTAssertFalse(model.canRetry)
        XCTAssertTrue(model.hasWriteBarrier); XCTAssertFalse(model.abortBeforeSubmission())
        var retirementPublications = 0, publishedRetry = false
        let observation = model.objectWillChange.sink {
            if !model.hasPhysicalFlight {
                retirementPublications += 1
                publishedRetry = model.canRetry
            }
        }
        f.drains[0](nil)
        await eventually { retirementPublications > 0 }
        XCTAssertTrue(f.writers.isPhysicallyIdle); XCTAssertFalse(model.hasPhysicalFlight)
        XCTAssertTrue(publishedRetry); XCTAssertTrue(model.canRetry)
        XCTAssertEqual(model.status, .timedOut)
        XCTAssertTrue(model.abortBeforeSubmission()); XCTAssertTrue(f.requests.isEmpty)
        withExtendedLifetime(observation) {}
    }

    func testCancellationDuringHeldJournalWorkWaitsForActualSnapshotAndPreservesCommittedRecord() async throws {
        let f = try await fixture(), original = record("held")
        f.disk.arm()
        f.journal.storage.write(f.namespace, original, nil) { result in if case .failure(let error) = result { XCTFail("Journal write failed: \(error)") } }
        await eventually { f.disk.starts == 1 }
        let model = try XCTUnwrap(f.make()); XCTAssertTrue(f.begin(model))
        await eventually { model.hasWriteBarrier }
        model.cancel()
        XCTAssertTrue(model.hasPhysicalFlight); XCTAssertFalse(model.abortBeforeSubmission())
        f.disk.release(); await eventually { !model.hasPhysicalFlight }
        XCTAssertTrue(model.abortBeforeSubmission())
        let restored = try await f.read(); XCTAssertEqual(restored, original)
        XCTAssertTrue(f.requests.isEmpty); XCTAssertTrue(f.drains.isEmpty)
    }

    func testAccountRoundTripCannotUseOldDrainOrAbortOldBarrierForNewAGeneration() async throws {
        let f = try await fixture(), model = try XCTUnwrap(f.make())
        XCTAssertTrue(f.begin(model)); await eventually { f.drains.count == 1 }
        let original = f.context; f.roundTrip(); XCTAssertNotEqual(original, f.context)
        f.drains[0](nil); await eventually { !model.hasPhysicalFlight && f.writers.isPhysicallyIdle }
        XCTAssertTrue(f.requests.isEmpty); XCTAssertNil(model.receipt)
        XCTAssertTrue(model.hasWriteBarrier); XCTAssertFalse(model.abortBeforeSubmission())
        XCTAssertNil(f.make()); XCTAssertNil(f.captureNewWrite()); await assertFrozen(f)
    }

    func testChangedEpochCannotSendAfterOriginalDrainOrReopenOldGeneration() async throws {
        let f = try await fixture(), model = try XCTUnwrap(f.make())
        XCTAssertTrue(f.begin(model)); await eventually { f.drains.count == 1 }
        f.epoch = 8
        f.drains[0](nil); await eventually { !model.hasPhysicalFlight }
        XCTAssertTrue(f.requests.isEmpty); XCTAssertFalse(model.abortBeforeSubmission())
        XCTAssertTrue(model.hasWriteBarrier); XCTAssertNil(f.captureNewWrite())
    }

    func testSameUIDSDKInstanceReplacementBeforeBarrierStartsNoDrainOrHTTP() async throws {
        let f = try await fixture(), model = try XCTUnwrap(f.make())
        f.onReauthenticated = { f.user = User("reader-A") }
        XCTAssertTrue(f.begin(model)); await eventually { !model.hasPhysicalFlight }
        XCTAssertEqual(f.reauths, 1); XCTAssertTrue(f.requests.isEmpty); XCTAssertTrue(f.drains.isEmpty)
        XCTAssertFalse(model.hasWriteBarrier); XCTAssertNotNil(f.captureNewWrite())
    }

    func testLastHeldUserHookDuringDrainCompletionCannotBorrowReplacementUser() async throws {
        let f = try await fixture(), model = try XCTUnwrap(f.make())
        XCTAssertTrue(f.begin(model)); await eventually { f.drains.count == 1 }
        f.onHeldUser = { f.onHeldUser = nil; f.user = User("reader-A") }
        f.drains[0](nil); await eventually { !model.hasPhysicalFlight }
        XCTAssertTrue(f.requests.isEmpty); XCTAssertEqual(f.credentialCalls, 0)
        XCTAssertTrue(model.hasWriteBarrier); XCTAssertFalse(model.abortBeforeSubmission())
    }

    func testSnapshotReadFailureRequiresExplicitOriginalAbortAndStartsNoSDKDrain() async throws {
        let f = try await fixture(), model = try XCTUnwrap(f.make())
        f.disk.setReadFailure(true)
        XCTAssertTrue(f.begin(model)); await eventually { !model.hasPhysicalFlight }
        XCTAssertTrue(model.hasWriteBarrier); XCTAssertTrue(f.drains.isEmpty); XCTAssertTrue(f.requests.isEmpty)
        f.disk.setReadFailure(false)
        XCTAssertTrue(model.abortBeforeSubmission()); let restored = try await f.read(); XCTAssertNil(restored)
        XCTAssertNotNil(f.captureNewWrite())
    }

    func testSnapshotFailureKeepsPreStopSDKWriteFlightUntilActualCallbackAndPublishesRetirement() async throws {
        let f = try await fixture(), write = f.startWrite()
        await eventually { f.writes.count == 1 }
        let model = try XCTUnwrap(f.make())
        var retirementPublications = 0
        let observation = model.objectWillChange.sink {
            if model.hasWriteBarrier && !model.hasPhysicalFlight { retirementPublications += 1 }
        }
        f.disk.setReadFailure(true)
        XCTAssertTrue(f.begin(model))
        await eventually { f.disk.readFailures == 1 }
        for _ in 0..<10 { await Task.yield() }
        XCTAssertTrue(model.hasPhysicalFlight); XCTAssertTrue(model.hasWriteBarrier)
        XCTAssertFalse(model.canRetry); XCTAssertFalse(model.abortBeforeSubmission())
        XCTAssertEqual(retirementPublications, 0); XCTAssertNil(f.captureNewWrite())
        XCTAssertTrue(f.drains.isEmpty); XCTAssertTrue(f.requests.isEmpty)
        await assertFrozen(f)
        f.writes[0](nil)
        let writeSucceeded = await write.value; XCTAssertTrue(writeSucceeded)
        await eventually { retirementPublications > 0 && !model.hasPhysicalFlight }
        XCTAssertTrue(model.canRetry); XCTAssertTrue(f.writers.isPhysicallyIdle)
        f.disk.setReadFailure(false)
        XCTAssertTrue(model.abortBeforeSubmission()); XCTAssertFalse(model.hasWriteBarrier)
        XCTAssertNotNil(f.captureNewWrite())
        let restored = try await f.read(); XCTAssertNil(restored)
        XCTAssertTrue(f.requests.isEmpty)
        withExtendedLifetime(observation) {}
    }

    func testAbortRejectsEpochChangedInsideOriginalHeldUserGetter() async throws {
        let f = try await fixture(), model = try XCTUnwrap(f.make())
        f.disk.setReadFailure(true)
        XCTAssertTrue(f.begin(model)); await eventually { !model.hasPhysicalFlight }
        let original = f.context
        f.onHeldUser = { f.onHeldUser = nil; f.epoch = 8 }
        XCTAssertFalse(model.abortBeforeSubmission())
        XCTAssertEqual(f.context, original); XCTAssertEqual(f.epoch, 8)
        XCTAssertTrue(model.hasWriteBarrier); XCTAssertNil(f.captureNewWrite())
        await assertFrozen(f)
        XCTAssertTrue(f.requests.isEmpty); XCTAssertTrue(f.drains.isEmpty)
    }

    func testAbortRejectsEpochChangedInsideLastRuntimeUIDGetter() async throws {
        let f = try await fixture(), model = try XCTUnwrap(f.make())
        f.disk.setReadFailure(true)
        XCTAssertTrue(f.begin(model)); await eventually { !model.hasPhysicalFlight }
        let original = f.context
        f.onActualUID = { f.onActualUID = nil; f.epoch = 8 }
        XCTAssertFalse(model.abortBeforeSubmission())
        XCTAssertEqual(f.context, original); XCTAssertEqual(f.epoch, 8)
        XCTAssertTrue(model.hasWriteBarrier); XCTAssertNil(f.captureNewWrite())
        await assertFrozen(f)
        XCTAssertTrue(f.requests.isEmpty); XCTAssertTrue(f.drains.isEmpty)
    }

    func testFailedDrainExplicitRetryUsesFreshReauthenticationAndNewPhysicalDrain() async throws {
        let f = try await fixture(), model = try XCTUnwrap(f.make())
        XCTAssertTrue(f.begin(model)); await eventually { f.drains.count == 1 }
        f.drains[0](Failure.local); await eventually { model.canRetry }
        XCTAssertTrue(model.hasWriteBarrier); XCTAssertTrue(f.requests.isEmpty)
        f.now += 5_000; XCTAssertTrue(model.retry(userConfirmed: true))
        await eventually { f.drains.count == 2 }
        XCTAssertEqual(f.actions.count, 2); XCTAssertNotEqual(f.actions[0].actionID, f.actions[1].actionID)
        XCTAssertEqual(f.actions[0].request, f.actions[1].request)
        f.drains[1](nil); await eventually { model.status == .scopedCloudDataRemoved && !model.hasPhysicalFlight }
        XCTAssertEqual(f.requests.count, 1); XCTAssertFalse(model.abortBeforeSubmission())
    }

    func testPendingRetryAndLedgerUseSameFamilyWithFreshDrainEachTimeAndNeverPurgeLocalOrOtherOwnerData() async throws {
        let f = try await fixture(), original = record("reader-local"), foreign = record("other-local")
        let other = try XCTUnwrap(FavoritesContext.confirmed(userID: "reader-B").namespace)
        try await f.write(original, expected: nil)
        _ = try await f.read(other); try await f.write(foreign, expected: nil, namespace: other)
        _ = try await f.read(.guest); try await f.write(record("guest"), expected: nil, namespace: .guest)
        let foreignBytes = try Data(contentsOf: f.file(other)), guestBytes = try Data(contentsOf: f.file(.guest))
        let model = try XCTUnwrap(f.make()); f.replyStatuses[0] = "pending"
        XCTAssertTrue(f.begin(model)); await eventually { f.drains.count == 1 }
        f.drains[0](nil); await eventually { model.canRetry }
        XCTAssertFalse(model.abortBeforeSubmission()); XCTAssertNil(f.make())
        f.now += 5_000; XCTAssertTrue(model.retry(userConfirmed: true))
        await eventually { f.drains.count == 2 }; f.drains[1](nil)
        await eventually { model.canBeginLedgerCleanup }
        f.now += 5_000; XCTAssertTrue(model.beginLedgerCleanup(userConfirmed: true))
        await eventually { f.drains.count == 3 }; f.drains[2](nil)
        await eventually { model.status == .ledgerDataRemoved && !model.hasPhysicalFlight }
        XCTAssertEqual(f.reauths, 3); XCTAssertEqual(f.requests.count, 3)
        XCTAssertEqual(f.requests[0].httpBody, f.requests[1].httpBody)
        XCTAssertEqual(f.actions.map(\.phase), [.cloudSlice, .cloudSlice, .mutationLedger])
        XCTAssertEqual(try FavoritesRecordCodec.decode(Data(contentsOf: f.file()), namespace: f.namespace), original)
        XCTAssertEqual(try Data(contentsOf: f.file(other)), foreignBytes)
        XCTAssertEqual(try Data(contentsOf: f.file(.guest)), guestBytes)
        XCTAssertFalse(model.accountDeletionComplete); XCTAssertTrue(model.hasWriteBarrier)
        XCTAssertFalse(model.abortBeforeSubmission()); XCTAssertNil(f.captureNewWrite())
    }

    func testUnknownHTTPOutcomeKeepsSealedBarrierAndNeverAutomaticallyResendsOrReopens() async throws {
        let f = try await fixture(), model = try XCTUnwrap(f.make())
        let http = f.hold(.http); f.httpError = Failure.local
        XCTAssertTrue(f.begin(model)); await eventually { f.drains.count == 1 }
        f.drains[0](nil); await eventually { http.entered }
        XCTAssertTrue(model.hasWriteBarrier); XCTAssertFalse(model.abortBeforeSubmission())
        http.release(); await eventually { model.canRetry }
        XCTAssertEqual(f.requests.count, 1); XCTAssertFalse(model.abortBeforeSubmission())
        XCTAssertNil(f.make()); XCTAssertNil(f.captureNewWrite()); await assertFrozen(f)
        XCTAssertNil(model.receipt); XCTAssertFalse(model.accountDeletionComplete)
    }

    func testCancellationDuringCredentialsAfterSealCannotUsePreSubmissionAbort() async throws {
        let f = try await fixture(), model = try XCTUnwrap(f.make()), credentials = f.hold(.credentials)
        XCTAssertTrue(f.begin(model)); await eventually { f.drains.count == 1 }
        f.drains[0](nil); await eventually { credentials.entered }
        model.cancel(); XCTAssertFalse(model.abortBeforeSubmission())
        credentials.release(); await eventually { !model.hasPhysicalFlight }
        XCTAssertTrue(f.requests.isEmpty); XCTAssertTrue(model.hasWriteBarrier)
        XCTAssertFalse(model.abortBeforeSubmission()); XCTAssertNil(f.captureNewWrite())
    }

    func testReplacementCompositionIsAllowedOnlyAfterSuccessfulExplicitPreSendAbort() async throws {
        let f = try await fixture(), model = try XCTUnwrap(f.make())
        XCTAssertTrue(f.begin(model)); await eventually { f.drains.count == 1 }
        f.drains[0](Failure.local); await eventually { !model.hasPhysicalFlight }
        XCTAssertNil(f.make()); XCTAssertTrue(model.abortBeforeSubmission())
        let replacement = try XCTUnwrap(f.make())
        XCTAssertFalse(replacement === model); XCTAssertTrue(f.begin(replacement))
        await eventually { f.drains.count == 2 }; f.drains[1](nil)
        await eventually { replacement.status == .scopedCloudDataRemoved && !replacement.hasPhysicalFlight }
        XCTAssertEqual(f.requests.count, 1)
    }
}
