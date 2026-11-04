import Combine
import FirebaseCore
import XCTest
@testable import Apropos

/// Actual coordinator -> shared writer/source barrier -> physical marker/readback
/// -> existing HTTP transport. Provider, SDK drain and HTTP effects are local.
@MainActor
final class ReaderDeletionRecoveryIntegrationTests: XCTestCase {
    private typealias Model = ReaderAccountDeletionCoordinator
    private typealias Contract = ReaderAccountDeletionContract
    private typealias Recovery = ReaderTransitionRecovery
    private typealias Store = ReaderTransitionRecoveryStore
    private enum Injected: Error { case markerWrite, malformedRequest }

    private final class Disk: @unchecked Sendable {
        enum Mode { case commit, failBeforeWrite, acknowledgeWithoutFile, commitThenThrow }
        private let lock = NSLock()
        private let releaseGate = DispatchSemaphore(value: 0)
        private var shouldHold = false
        private var mode: Mode = .commit
        private var replacements = 0
        private var active = 0
        private var sourceReadFails = false
        var calls: Int { lock.lock(); defer { lock.unlock() }; return replacements }
        var isBusy: Bool { lock.lock(); defer { lock.unlock() }; return active > 0 }
        func configure(_ mode: Mode = .commit, hold: Bool = false) {
            lock.lock(); self.mode = mode; shouldHold = hold; lock.unlock()
        }
        func setSourceReadFailure(_ value: Bool) { lock.lock(); sourceReadFails = value; lock.unlock() }
        func readSource() throws -> Data? {
            lock.lock(); let fails = sourceReadFails; lock.unlock()
            if fails { throw FavoritesJournalFailure.readFailed }
            return nil
        }
        func release() { releaseGate.signal() }
        func replace(_ data: Data, _ url: URL) throws {
            // This older probe measures only the immutable transition marker.
            // The checkpoint sibling has its own physical failure/readback suite.
            guard url.lastPathComponent == "reader-transition-v1.json" else {
                try data.write(to: url, options: .atomic); return
            }
            lock.lock()
            let held = shouldHold, behavior = mode
            shouldHold = false; replacements += 1; active += 1
            lock.unlock()
            defer { lock.lock(); active -= 1; lock.unlock() }
            if held, releaseGate.wait(timeout: .now() + 5) != .success { throw Injected.markerWrite }
            switch behavior {
            case .failBeforeWrite: throw Injected.markerWrite
            case .acknowledgeWithoutFile: return
            case .commit: try data.write(to: url, options: .atomic)
            case .commitThenThrow:
                try data.write(to: url, options: .atomic)
                throw Injected.markerWrite
            }
        }
    }

    @MainActor private final class Fixture {
        let canonical = CanonicalSessionState()
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("deletion-recovery-" + UUID().uuidString)
        let disk = Disk()
        var uid = "reader-A"
        var epoch: Int64? = 7
        var now: Int64 = 1_800_000_000_123
        var actions: [Model.ActionTicket] = []
        var drainCount = 0, credentialCount = 0
        var requests: [URLRequest] = []
        var deadlines: [@MainActor () -> Void] = []
        var pendingFirst = false
        lazy var recovery = Recovery(store: Store(rootDirectory: markerRoot,
            replace: { [disk] in try disk.replace($0, $1) }))
        lazy var journal = FavoritesFileJournal(rootDirectory: root.appendingPathComponent("favorites"),
            legacyRead: { [disk] _ in try disk.readSource() }, legacyAdmission: recovery.admission)
        lazy var writers = ReaderWriterDrainRuntime(canonical: canonical, actualUID: { [unowned self] in uid },
            makeDrain: { [unowned self] in
                drainCount += 1
                return .init(wait: { completion in completion(nil) })
            }, legacyAdmission: recovery.admission)
        lazy var model = Model(canonical: canonical, currentMembershipEpoch: { [unowned self] _ in epoch },
            reauthenticate: { [unowned self] action in
                actions.append(action)
                return .init(action: action, authenticatedUID: action.request.expectedUID,
                             authTimeMs: (now / 1_000) * 1_000, kind: .reauthenticated)
            }, send: { [unowned self] request, proof in
                let transport = try await prepare(proof)
                return try await transport.send(request)
            }, sendLedger: { [unowned self] request, proof in
                let transport = try await prepare(proof)
                return try await transport.sendLedger(request)
            }, writeBarrier: .init(writers: writers, journal: journal, recovery: recovery),
            configurationDigest: ReaderTransitionRecoveryStore.deletionConfigurationDigest(projectID: "local-deletion",
                appID: "1:123456789:ios:abcdef123456", endpoint: URL(string: "https://deletion.example.invalid/reader")!),
            nowMilliseconds: { [unowned self] in now }, scheduleTimeout: { [unowned self] _, fire in
                deadlines.append(fire); return {}
            })

        init() { select("reader-A") }
        var context: CanonicalSessionState.ContextTicket { canonical.contextTicket() }
        var markerRoot: URL { root.appendingPathComponent("reader-transition") }
        var markerURL: URL { markerRoot.appendingPathComponent("reader-transition-v1.json") }
        var binding: ReaderMembershipContract.Binding { try! .init(ownerUID: "reader-A", epoch: 7) }
        func select(_ next: String) {
            uid = next
            canonical.adopt(.init(uid: next, email: "reader@example.invalid", isEmailVerified: true))
        }
        func begin() -> Bool { model.begin(context: context, membershipEpoch: epoch ?? 7, userConfirmed: true) }
        func prepare(_ proof: Model.ReauthenticationResult) async throws -> ReaderDeletionHTTPTransport {
            let original = proof.action.context, originalUID = proof.authenticatedUID
            let identity: @MainActor () -> Bool = { [unowned self] in
                canonical.isCurrent(original) && uid == originalUID
            }
            let current: @MainActor () -> Bool = { [unowned self] in
                identity() && model.permitsTransport(action: proof.action)
            }
            try await model.prepareWritesForDeletion(action: proof.action, stillCurrent: current,
                                                     originalUserIsCurrent: identity)
            let configuration = try ReaderDeletionHTTPTransport.Configuration(projectID: "local-deletion",
                appID: "1:123456789:ios:abcdef123456", endpointURL: URL(string: "https://deletion.example.invalid/reader")!)
            return ReaderDeletionHTTPTransport(configuration: configuration, action: proof.action, proof: proof,
                credentials: { [unowned self] admitted in
                    guard admitted() else { throw CancellationError() }
                    credentialCount += 1
                    XCTAssertTrue(recovery.hasVerifiedSeal(binding: binding))
                    return .init(ownerUID: proof.authenticatedUID, projectID: configuration.projectID,
                        appID: configuration.appID, idToken: "local.id", appCheckToken: "local.app",
                        authTimeMs: proof.authTimeMs, authValidUntilMs: now + 60_000, appCheckValidUntilMs: now + 60_000)
                }, isCurrent: current, execute: { [unowned self] request in
                    requests.append(request)
                    return try reply(request)
                }, now: { [unowned self] in now })
        }
        func reply(_ request: URLRequest) throws -> (Data, HTTPURLResponse) {
            guard let data = request.httpBody, let value = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let owner = value["expectedUID"] as? String, let epoch = value["membershipEpoch"] as? Int64,
                  let url = request.url else { throw Injected.malformedRequest }
            let parent = try Contract.Request(expectedUID: owner, membershipEpoch: epoch)
            let isLedger = value["scope"] as? String == Contract.ledgerScope
            let requestID = isLedger ? try Contract.LedgerRequest(expectedUID: owner, membershipEpoch: epoch,
                parentRequestID: parent.requestID).requestID : parent.requestID
            var body: [String: Any] = ["requestID": requestID, "scope": isLedger ? Contract.ledgerScope : Contract.scope,
                "status": isLedger ? "ledgerDataRemoved" : (pendingFirst && requests.count == 1 ? "pending" : "scopedCloudDataRemoved"),
                "accountDeletionComplete": false, "unresolved": isLedger ? Contract.ledgerUnresolved : Contract.unresolved]
            if isLedger {
                body["parentRequestID"] = parent.requestID; body["removedReceiptDocuments"] = 2; body["removedRevisionDocuments"] = 1
            } else if !(pendingFirst && requests.count == 1) { body["removedFavoriteDocuments"] = 2 }
            let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1",
                                           headerFields: ["Content-Type": "application/json"])!
            return (try JSONSerialization.data(withJSONObject: body), response)
        }
        func close() async {
            model.cancel(); disk.release()
            for _ in 0..<3_000 {
                if !model.hasPhysicalFlight && !recovery.isBusy && !disk.isBusy { break }
                try? await Task.sleep(for: .milliseconds(1))
            }
            XCTAssertFalse(model.hasPhysicalFlight); XCTAssertFalse(recovery.isBusy); XCTAssertFalse(disk.isBusy)
            try? FileManager.default.removeItem(at: root)
        }
    }

    override func setUp() { super.setUp(); XCTAssertNil(FirebaseApp.allApps) }
    override func tearDown() { XCTAssertNil(FirebaseApp.allApps); super.tearDown() }
    private func withFixture(_ body: (Fixture) async throws -> Void) async throws {
        let fixture = Fixture()
        do { try await body(fixture) }
        catch { await fixture.close(); throw error }
        await fixture.close()
    }
    private func eventually(_ predicate: () -> Bool, file: StaticString = #filePath, line: UInt = #line) async {
        for _ in 0..<2_000 {
            if predicate() { return }
            try? await Task.sleep(for: .milliseconds(1))
        }
        XCTFail("Expected physical recovery state was not reached", file: file, line: line)
    }

    func testMissingRootFailsClosedWithoutReadHookOrReplacement() async {
        let recovery = Recovery(store: Store(rootDirectory: nil,
            replace: { _, _ in XCTFail("No fallback write location is permitted") },
            beforeRead: { XCTFail("No physical read may start without an application root") }))
        XCTAssertEqual(recovery.status, .unresolved); XCTAssertFalse(recovery.admission.isAllowed)
        do { try await recovery.bootstrap(); XCTFail("A missing root is not a missing marker") }
        catch { XCTAssertEqual(error as? Store.Failure, .readFailed) }
        XCTAssertEqual(recovery.status, .unavailable); XCTAssertFalse(recovery.legacyWritesPermitted)
    }

    func testUnresolvedRecoveryCannotAcquireDeletionBarrierOrStartCredentialWork() async throws {
        try await withFixture { f in
            XCTAssertTrue(f.begin())
            await eventually { !f.model.hasPhysicalFlight }
            XCTAssertEqual(f.model.status, .unavailable); XCTAssertFalse(f.model.hasWriteBarrier)
            XCTAssertEqual(f.drainCount, 0); XCTAssertEqual(f.disk.calls, 0)
            XCTAssertEqual(f.credentialCount, 0); XCTAssertTrue(f.requests.isEmpty)
        }
    }

    func testHeldPhysicalMarkerBlocksCredentialsAndHTTPUntilExactReadback() async throws {
        try await withFixture { f in
            try await f.recovery.bootstrap(); XCTAssertTrue(f.recovery.admission.isAllowed)
            f.disk.configure(hold: true)
            XCTAssertTrue(f.begin()); await eventually { f.disk.isBusy }
            XCTAssertEqual(f.drainCount, 1); XCTAssertEqual(f.credentialCount, 0); XCTAssertTrue(f.requests.isEmpty)
            XCTAssertTrue(f.model.hasPhysicalFlight); XCTAssertTrue(f.model.hasWriteBarrier)
            XCTAssertFalse(f.recovery.admission.isAllowed); XCTAssertFalse(f.model.abortBeforeSubmission())
            XCTAssertFalse(FileManager.default.fileExists(atPath: f.markerURL.path))
            f.disk.release()
            await eventually { f.model.status == .scopedCloudDataRemoved && !f.model.hasPhysicalFlight }
            XCTAssertTrue(f.recovery.hasVerifiedSeal(binding: f.binding)); XCTAssertEqual(f.credentialCount, 1)
            XCTAssertEqual(f.requests.count, 1); XCTAssertFalse(f.model.accountDeletionComplete)
            XCTAssertFalse(f.model.abortBeforeSubmission())
        }
    }

    func testAcknowledgedWriteWithoutFileCannotSendAndExplicitRetryKeepsOriginalBinding() async throws {
        try await withFixture { f in
            try await f.recovery.bootstrap(); f.disk.configure(.acknowledgeWithoutFile)
            XCTAssertTrue(f.begin()); await eventually { !f.model.hasPhysicalFlight }
            XCTAssertEqual(f.model.status, .unavailable); XCTAssertTrue(f.model.hasWriteBarrier)
            XCTAssertEqual(f.credentialCount, 0); XCTAssertTrue(f.requests.isEmpty)
            XCTAssertFalse(f.recovery.admission.isAllowed); XCTAssertFalse(f.model.abortBeforeSubmission())
            XCTAssertFalse(FileManager.default.fileExists(atPath: f.markerURL.path))
            f.disk.configure(); f.now += 1_000
            XCTAssertTrue(f.model.retry(userConfirmed: true))
            await eventually { f.model.status == .scopedCloudDataRemoved && !f.model.hasPhysicalFlight }
            XCTAssertEqual(f.disk.calls, 2); XCTAssertEqual(f.drainCount, 2); XCTAssertEqual(f.requests.count, 1)
            XCTAssertTrue(f.recovery.hasVerifiedSeal(binding: f.binding))
        }
    }

    func testFailureBeforeReplacementNeverReopensEitherWriterAndCanRetryOriginalMarker() async throws {
        try await withFixture { f in
            try await f.recovery.bootstrap(); f.disk.configure(.failBeforeWrite)
            XCTAssertTrue(f.begin()); await eventually { !f.model.hasPhysicalFlight }
            XCTAssertEqual(f.credentialCount, 0); XCTAssertTrue(f.requests.isEmpty)
            XCTAssertFalse(f.model.abortBeforeSubmission()); XCTAssertTrue(f.recovery.hasSealAttempt)
            XCTAssertNil(f.writers.captureWrite(expectedUserID: "reader-A", stillCurrent: { true }, start: { _, _ in
                XCTFail("Stopped writer must not start")
            }))
            f.disk.configure(); f.now += 1_000
            XCTAssertTrue(f.model.retry(userConfirmed: true))
            await eventually { f.model.status == .scopedCloudDataRemoved && !f.model.hasPhysicalFlight }
            XCTAssertEqual(f.disk.calls, 2); XCTAssertEqual(f.requests.count, 1)
        }
    }

    func testCommitThenThrowIsAcceptedOnlyAfterReadbackAndRestartRemainsClosed() async throws {
        try await withFixture { f in
            try await f.recovery.bootstrap(); f.disk.configure(.commitThenThrow)
            XCTAssertTrue(f.begin())
            await eventually { f.model.status == .scopedCloudDataRemoved && !f.model.hasPhysicalFlight }
            let originalBytes = try Data(contentsOf: f.markerURL)
            let restarted = Recovery(store: Store(rootDirectory: f.markerRoot,
                replace: { _, _ in XCTFail("Restart must preserve the existing immutable marker") }))
            XCTAssertFalse(restarted.admission.isAllowed)
            try await restarted.bootstrap()
            XCTAssertFalse(restarted.admission.isAllowed); XCTAssertTrue(restarted.hasVerifiedSeal(binding: f.binding))
            let repeated = try await restarted.seal(binding: f.binding)
            XCTAssertEqual(repeated.binding, f.binding); XCTAssertEqual(try Data(contentsOf: f.markerURL), originalBytes)
            XCTAssertFalse(restarted.canPrepare(binding: try .init(ownerUID: "reader-B", epoch: 7)))
            XCTAssertFalse(restarted.canPrepare(binding: try .init(ownerUID: "reader-A", epoch: 8)))
            XCTAssertEqual(f.credentialCount, 1); XCTAssertEqual(f.disk.calls, 1)
        }
    }

    func testCancellationAndDeadlineRetainPhysicalMarkerUntilReturnAndNeverSend() async throws {
        for timeout in [false, true] {
            try await withFixture { f in
                try await f.recovery.bootstrap(); f.disk.configure(hold: true)
                XCTAssertTrue(f.begin()); await eventually { f.disk.isBusy }
                if timeout { try XCTUnwrap(f.deadlines.first)() } else { f.model.cancel() }
                XCTAssertTrue(f.model.hasPhysicalFlight); XCTAssertFalse(f.model.abortBeforeSubmission())
                XCTAssertFalse(f.model.retry(userConfirmed: true)); XCTAssertFalse(f.begin())
                f.disk.release(); await eventually { !f.model.hasPhysicalFlight }
                XCTAssertEqual(f.credentialCount, 0); XCTAssertTrue(f.requests.isEmpty)
                XCTAssertTrue(FileManager.default.fileExists(atPath: f.markerURL.path))
                XCTAssertFalse(f.recovery.admission.isAllowed); XCTAssertFalse(f.model.abortBeforeSubmission())
                let restarted = Recovery(store: Store(rootDirectory: f.markerRoot))
                try await restarted.bootstrap()
                XCTAssertTrue(restarted.hasVerifiedSeal(binding: f.binding)); XCTAssertFalse(restarted.admission.isAllowed)
            }
        }
    }

    func testAccountRoundTripAndNewEpochRejectOldMarkerReturnWithoutBorrowingNewAuthority() async throws {
        for changesEpoch in [false, true] {
            try await withFixture { f in
                try await f.recovery.bootstrap(); f.disk.configure(hold: true)
                let originalContext = f.context
                XCTAssertTrue(f.begin()); await eventually { f.disk.isBusy }
                if changesEpoch { f.epoch = 8 } else { f.select("reader-B"); f.select("reader-A") }
                f.disk.release(); await eventually { !f.model.hasPhysicalFlight }
                XCTAssertEqual(f.credentialCount, 0); XCTAssertTrue(f.requests.isEmpty); XCTAssertNil(f.model.receipt)
                XCTAssertFalse(f.model.abortBeforeSubmission()); XCTAssertFalse(f.begin())
                if !changesEpoch { XCTAssertNotEqual(f.context, originalContext) }
                let restarted = Recovery(store: Store(rootDirectory: f.markerRoot))
                try await restarted.bootstrap()
                XCTAssertTrue(restarted.hasVerifiedSeal(binding: f.binding))
                XCTAssertFalse(restarted.admission.isAllowed)
            }
        }
    }

    func testPendingAndLedgerRetriesReuseImmutableMarkerButRequireFreshDrainAndProof() async throws {
        try await withFixture { f in
            try await f.recovery.bootstrap(); f.pendingFirst = true
            XCTAssertTrue(f.begin()); await eventually { f.model.status == .pending && !f.model.hasPhysicalFlight }
            let firstBytes = try Data(contentsOf: f.markerURL), firstRequest = try XCTUnwrap(f.requests.first)
            f.now += 1_000; XCTAssertTrue(f.model.retry(userConfirmed: true))
            await eventually { f.model.status == .scopedCloudDataRemoved && !f.model.hasPhysicalFlight }
            XCTAssertEqual(f.requests.last?.httpBody, firstRequest.httpBody)
            f.now += 1_000; XCTAssertTrue(f.model.beginLedgerCleanup(userConfirmed: true))
            await eventually { f.model.status == .ledgerDataRemoved && !f.model.hasPhysicalFlight }
            XCTAssertEqual(f.drainCount, 3); XCTAssertEqual(f.credentialCount, 3); XCTAssertEqual(f.disk.calls, 1)
            XCTAssertEqual(Set(f.actions.map(\.actionID)).count, 3)
            XCTAssertEqual(f.actions.map(\.phase), [.cloudSlice, .cloudSlice, .mutationLedger])
            XCTAssertEqual(try Data(contentsOf: f.markerURL), firstBytes); XCTAssertFalse(f.model.accountDeletionComplete)
        }
    }

    func testOtherTransitionSealAttemptPreventsAbortingAnEarlierSourceReadFailure() async throws {
        try await withFixture { f in
            try await f.recovery.bootstrap(); f.disk.setSourceReadFailure(true)
            XCTAssertTrue(f.begin()); await eventually { !f.model.hasPhysicalFlight }
            XCTAssertEqual(f.model.status, .unavailable); XCTAssertTrue(f.model.hasWriteBarrier)
            XCTAssertFalse(f.recovery.hasSealAttempt); XCTAssertTrue(f.recovery.legacyWritesPermitted)
            XCTAssertEqual(f.disk.calls, 0); XCTAssertEqual(f.credentialCount, 0)
            // Another existing transition uses the same installation recovery.
            // It must make even this earlier owner's otherwise pre-seal abort illegal.
            _ = try await f.recovery.seal(binding: f.binding)
            XCTAssertTrue(f.recovery.hasVerifiedSeal(binding: f.binding))
            XCTAssertFalse(f.model.abortBeforeSubmission()); XCTAssertTrue(f.model.hasWriteBarrier)
            XCTAssertNil(f.writers.captureWrite(expectedUserID: "reader-A", stillCurrent: { true }, start: { _, _ in
                XCTFail("Shared recovery seal must preserve the earlier writer stop")
            }))
            XCTAssertTrue(f.requests.isEmpty)
        }
    }

    func testAdmissionObserverSeesClosedValueBeforeReentrantCancellation() async throws {
        try await withFixture { f in
            try await f.recovery.bootstrap()
            var notifications = 0
            let observation = f.recovery.changes.sink {
                notifications += 1
                XCTAssertFalse(f.recovery.admission.isAllowed)
                f.model.cancel()
            }
            XCTAssertTrue(f.begin()); await eventually { !f.model.hasPhysicalFlight }
            XCTAssertEqual(notifications, 1); XCTAssertEqual(f.credentialCount, 0); XCTAssertTrue(f.requests.isEmpty)
            XCTAssertFalse(f.model.abortBeforeSubmission()); XCTAssertTrue(f.recovery.hasSealAttempt)
            XCTAssertFalse(f.recovery.admission.isAllowed)
            withExtendedLifetime(observation) {}
        }
    }
}
