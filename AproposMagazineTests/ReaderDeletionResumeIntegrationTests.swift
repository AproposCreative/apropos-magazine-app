import FirebaseCore
import XCTest
@testable import Apropos

/// New real Auth/startup/recovery instances reuse only local files. Provider,
/// held-user SDK calls and HTTP are injected; reader services stay unopened.
@MainActor
final class ReaderDeletionResumeIntegrationTests: XCTestCase {
    private typealias Model = ReaderAccountDeletionCoordinator
    private typealias Contract = ReaderAccountDeletionContract
    private typealias Bridge = ReaderAccountReauthentication<String>
    private enum Failure: Error { case lostResponse, invalidFixture, checkpointWrite, heldIO }
    private enum Stage: Hashable { case provider, sdk, credentials, http }
    private final class User { let uid: String; init(_ uid: String) { self.uid = uid } }
    @MainActor private final class Gate {
        var entered = false
        private var continuation: CheckedContinuation<Void, Never>?
        func wait() async { await withCheckedContinuation { continuation = $0; entered = true } }
        func release() { let value = continuation; continuation = nil; value?.resume() }
    }
    private final class FileControl: @unchecked Sendable {
        private let lock = NSLock(), semaphore = DispatchSemaphore(value: 0)
        private var held = false, fails = false, checkpointCount = 0
        var checkpointWrites: Int { lock.lock(); defer { lock.unlock() }; return checkpointCount }
        func holdCheckpoint() { lock.lock(); held = true; lock.unlock() }
        func failCheckpoint() { lock.lock(); fails = true; lock.unlock() }
        func repairCheckpoint() { lock.lock(); fails = false; lock.unlock() }
        func release() { semaphore.signal() }
        func replace(_ bytes: Data, _ url: URL) throws {
            lock.lock()
            let checkpoint = url.lastPathComponent == "reader-deletion-v1.json"
            if checkpoint { checkpointCount += 1 }
            let hold = checkpoint && held, fail = checkpoint && fails
            if checkpoint { held = false }
            lock.unlock()
            if hold, semaphore.wait(timeout: .now() + 5) != .success { throw Failure.heldIO }
            if fail { throw Failure.checkpointWrite }
            try bytes.write(to: url, options: .atomic)
        }
    }

    @MainActor private final class Process {
        let root: URL, files: FileControl, configuration: ReaderDeletionHTTPTransport.Configuration
        let recovery: ReaderTransitionRecovery, startup: ReaderSDKStartupState, auth: AuthService
        var user: User? = User("reader-A")
        var epoch: Int64? = 7, now: Int64 = 1_800_000_000_123
        var readerEffects = 0, publications = 0, vmStarts = 0, drainFactories = 0
        var reauths = 0, credentials = 0, epochReads = 0
        var actions: [Model.ActionTicket] = [], requests: [URLRequest] = [], models: [Model] = []
        var lostResponses: Set<Int> = [], statuses: [Int: String] = [:]
        var invalidResponse = false
        var holds: [Stage: Gate] = [:], gates: [Gate] = [], launchTasks: [Task<Void, Never>] = []
        var onHeldUser: (() -> Void)?, onReauthenticated: (() -> Void)?
        lazy var delegate = AppDelegate(startup: startup, identity: auth.bootstrapIdentity,
            actualUserID: { [unowned self] in user?.uid })
        lazy var vm = ArticleViewModel(startup: startup, identity: auth.bootstrapIdentity,
            actualUserID: { [unowned self] in user?.uid }, readEffects: .init())
        lazy var operations = AuthOperationCoordinator(canonical: auth.state,
            actualUserID: { [unowned self] in user?.uid }, reauthenticationIdentity: auth.bootstrapIdentity)
        lazy var readerBridge = makeBridge(auth.state)
        lazy var authOnlyBridge = makeBridge(auth.bootstrapIdentity)
        lazy var writers = ReaderWriterDrainRuntime(canonical: auth.state,
            actualUID: { [unowned self] in user?.uid }, makeDrain: { [unowned self] in
                drainFactories += 1; return .init(wait: { $0(nil) })
            }, legacyAdmission: recovery.admission)
        lazy var journal = FavoritesFileJournal(rootDirectory: root.appendingPathComponent("favorites"),
            legacyAdmission: recovery.admission)

        init(root: URL, files: FileControl = FileControl(), endpoint: String = "https://deletion.example.invalid/reader",
             projectID: String = "local-deletion", appID: String = "1:123456789:ios:abcdef123456") throws {
            self.root = root; self.files = files
            configuration = try .init(projectID: projectID, appID: appID, endpointURL: try XCTUnwrap(URL(string: endpoint)))
            recovery = ReaderTransitionRecovery(store: .init(rootDirectory: root.appendingPathComponent("transition"),
                replace: { try files.replace($0, $1) }))
            startup = ReaderSDKStartupState(legacyRecovery: recovery)
            auth = AuthService(startup: startup)
        }
        var readerContext: CanonicalSessionState.ContextTicket { auth.state.contextTicket() }
        var authContext: CanonicalSessionState.ContextTicket { auth.bootstrapIdentity.contextTicket() }
        var markerFile: URL { root.appendingPathComponent("transition/reader-transition-v1.json") }
        var checkpointFile: URL { root.appendingPathComponent("transition/reader-deletion-v1.json") }
        func observe(_ uid: String?) {
            if user?.uid != uid { user = uid.map(User.init) }
            let session = uid.map { ReaderAccountSession(uid: $0, email: "local@example.invalid", isEmailVerified: true) }
            _ = auth.observeIdentity(session, currentUserID: { [unowned self] in user?.uid },
                revokeReader: { [unowned self] current in auth.state.suspend(stillPermitted: current) != nil },
                publishReader: { [unowned self] current in
                    guard let accepted = auth.state.adopt(session, stillPermitted: current) else { return nil }
                    publications += 1; return accepted
                })
        }
        func launch(_ uid: String? = "reader-A") async {
            vm.start(readerSteps: [{ [unowned self] current in XCTAssertTrue(current()); vmStarts += 1 }])
            if let task = delegate.runAccountStartup(authOnly: {}, readerSteps: [{ [unowned self] in readerEffects += 1 }],
                observeAuth: { [unowned self] in observe(uid) },
                releaseReader: { [unowned self] in _ = auth.resumeReaderAfterLocalRecovery() }) {
                launchTasks.append(task); await task.value
            }
        }
        func hold(_ stage: Stage) -> Gate {
            let gate = Gate(); holds[stage] = gate; gates.append(gate); return gate
        }
        func pass(_ stage: Stage) async { if let gate = holds.removeValue(forKey: stage) { await gate.wait() } }
        func makeBridge(_ identity: CanonicalSessionState) -> Bridge {
            Bridge(canonical: identity, operations: operations, captureUser: { [unowned self] in
                guard let original = user else { return nil }
                return .init(uid: original.uid, isCurrent: { [unowned self] in
                    let current = user === original; onHeldUser?(); return current
                }, reauthenticate: { [unowned self] _, permitted in
                    guard permitted() else { throw CancellationError() }
                    reauths += 1; await pass(.sdk)
                    return .init(uid: original.uid, authTimeMs: (now / 1_000) * 1_000)
                }, deletionCredentials: { [unowned self] proof, _ in
                    credentials += 1; await pass(.credentials)
                    return .init(ownerUID: original.uid, projectID: configuration.projectID, appID: configuration.appID,
                        idToken: "local.id." + proof.action.actionID.uuidString,
                        appCheckToken: "local.app." + proof.action.actionID.uuidString, authTimeMs: proof.authTimeMs,
                        authValidUntilMs: now + 60_000, appCheckValidUntilMs: now + 60_000)
                })
            }, nowMilliseconds: { [unowned self] in now })
        }
        func make(resume: Bool) -> Model? {
            let epoch: Model.EpochReader?
            if resume { epoch = nil }
            else { epoch = { [unowned self] _ in self.epochReads += 1; return self.epoch } }
            let model = auth.makeReaderAccountDeletion(configuration: configuration, currentMembershipEpoch: epoch,
                reauthentication: resume ? authOnlyBridge : readerBridge,
                obtainCredential: { [unowned self] action in actions.append(action); await pass(.provider); return "fresh-provider" },
                reauthenticationFinished: { [unowned self] _, error in if error == nil { onReauthenticated?() } },
                execute: { [unowned self] request in
                    let index = requests.count; requests.append(request); await pass(.http)
                    if lostResponses.contains(index) { throw Failure.lostResponse }
                    return try response(request, index: index)
                }, now: { [unowned self] in now }, scheduleTimeout: { _, _ in {} },
                writeBarrier: resume ? nil : .init(writers: writers, journal: journal, recovery: recovery),
                resumingAfterRestart: resume)
            if let model { models.append(model) }
            return model
        }
        func begin(_ model: Model) -> Bool { model.begin(context: readerContext, membershipEpoch: 7, userConfirmed: true) }
        func resume(_ model: Model, confirmed: Bool = true) -> Bool {
            model.beginResumption(context: authContext, userConfirmed: confirmed)
        }
        func response(_ request: URLRequest, index: Int) throws -> (Data, HTTPURLResponse) {
            guard let bytes = request.httpBody, let body = try JSONSerialization.jsonObject(with: bytes) as? [String: Any],
                  let uid = body["expectedUID"] as? String, let epoch = body["membershipEpoch"] as? Int64,
                  let url = request.url else { throw Failure.invalidFixture }
            let parent = try Contract.Request(expectedUID: uid, membershipEpoch: epoch)
            let ledger = body["scope"] as? String == Contract.ledgerScope
            let status = statuses[index] ?? (ledger ? "ledgerDataRemoved" : "scopedCloudDataRemoved")
            let id: String
            if ledger {
                id = try Contract.LedgerRequest(expectedUID: uid, membershipEpoch: epoch,
                    parentRequestID: try XCTUnwrap(body["parentRequestID"] as? String)).requestID
            } else { id = parent.requestID }
            var value: [String: Any] = ["requestID": id, "scope": ledger ? Contract.ledgerScope : Contract.scope,
                "status": status, "accountDeletionComplete": false, "unresolved": ledger ? Contract.ledgerUnresolved : Contract.unresolved]
            if status == "scopedCloudDataRemoved" { value["removedFavoriteDocuments"] = 2 }
            if status == "ledgerDataRemoved" {
                value["parentRequestID"] = parent.requestID; value["removedReceiptDocuments"] = 1; value["removedRevisionDocuments"] = 1
            }
            if invalidResponse { value["accountDeletionComplete"] = true }
            return (try JSONSerialization.data(withJSONObject: value), try XCTUnwrap(HTTPURLResponse(url: url,
                statusCode: 200, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"])))
        }
        func close() async {
            onHeldUser = nil; onReauthenticated = nil
            models.forEach { $0.cancel() }; gates.forEach { $0.release() }; files.release()
            for task in launchTasks { task.cancel(); await task.value }
            for _ in 0..<2_000 {
                if models.allSatisfy({ !$0.hasPhysicalFlight }) && !recovery.isBusy { break }
                try? await Task.sleep(nanoseconds: 1_000_000)
            }
        }
    }

    override func setUp() { super.setUp(); XCTAssertNil(FirebaseApp.allApps) }
    override func tearDown() { XCTAssertNil(FirebaseApp.allApps); super.tearDown() }
    private func process(root: URL? = nil, files: FileControl = FileControl(),
        endpoint: String = "https://deletion.example.invalid/reader", projectID: String = "local-deletion",
        appID: String = "1:123456789:ios:abcdef123456") throws -> Process {
        let directory = root ?? FileManager.default.temporaryDirectory.appendingPathComponent("deletion-resume-" + UUID().uuidString)
        if root == nil { addTeardownBlock { try? FileManager.default.removeItem(at: directory) } }
        let value = try Process(root: directory, files: files, endpoint: endpoint, projectID: projectID, appID: appID)
        addTeardownBlock { @MainActor in await value.close() }; return value
    }
    private func eventually(_ condition: () -> Bool, file: StaticString = #filePath, line: UInt = #line) async {
        for _ in 0..<2_000 { if condition() { return }; try? await Task.sleep(nanoseconds: 1_000_000) }
        XCTFail("Actual composed stage did not finish", file: file, line: line)
    }
    private func assertAuthOnly(_ process: Process, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(process.auth.state.snapshot.context, .unresolved, file: file, line: line)
        XCTAssertEqual(process.readerEffects, 0, file: file, line: line)
        XCTAssertEqual(process.publications, 0, file: file, line: line)
        XCTAssertEqual(process.vmStarts, 0, file: file, line: line)
        XCTAssertEqual(process.drainFactories, 0, file: file, line: line)
        XCTAssertEqual(process.epochReads, 0, file: file, line: line)
        XCTAssertFalse(process.recovery.admission.isAllowed, file: file, line: line)
        XCTAssertFalse(process.startup.permitsReaderServices(identity: process.auth.bootstrapIdentity), file: file, line: line)
    }
    private func lostParent() async throws -> (Process, Model) {
        let first = try process(); await first.launch(); first.lostResponses = [0]
        let model = try XCTUnwrap(first.make(resume: false)); XCTAssertTrue(first.begin(model))
        await eventually { model.canRetry }
        XCTAssertEqual(first.requests.count, 1); XCTAssertEqual(first.drainFactories, 1)
        XCTAssertEqual(first.recovery.deletionCheckpoint?.phase, .parent)
        XCTAssertFalse(model.accountDeletionComplete)
        return (first, model)
    }
    private func restarted(_ first: Process, uid: String? = "reader-A") async throws -> Process {
        let next = try process(root: first.root); next.now = first.now + 10_000
        await next.launch(uid); assertAuthOnly(next); return next
    }

    func testLostParentResponseResumesExactOriginalRequestWithFreshAuthOnlyIdentityAndReauth() async throws {
        let (first, _) = try await lostParent(), next = try await restarted(first)
        XCTAssertEqual(next.recovery.deletionCheckpoint, first.recovery.deletionCheckpoint)
        XCTAssertTrue(next.requests.isEmpty); XCTAssertTrue(next.actions.isEmpty)
        let model = try XCTUnwrap(next.make(resume: true))
        XCTAssertTrue(next.requests.isEmpty); XCTAssertFalse(model.canBeginLedgerCleanup)
        XCTAssertTrue(next.resume(model)); await eventually { model.canBeginLedgerCleanup }
        XCTAssertEqual(next.requests.count, 1); XCTAssertEqual(next.requests[0].httpBody, first.requests[0].httpBody)
        XCTAssertEqual(next.actions[0].context, next.authContext)
        XCTAssertNotEqual(next.actions[0].context, first.actions[0].context)
        XCTAssertNotEqual(next.actions[0].actionID, first.actions[0].actionID)
        XCTAssertEqual(next.reauths, 1); assertAuthOnly(next); XCTAssertFalse(model.accountDeletionComplete)
    }

    func testRestartConstructionLoginAndCheckpointReadNeverAutomaticallySubmitOrConfirmDeletion() async throws {
        let (first, _) = try await lostParent(), next = try await restarted(first)
        let model = try XCTUnwrap(next.make(resume: true))
        XCTAssertFalse(next.resume(model, confirmed: false)); XCTAssertFalse(model.retry(userConfirmed: true))
        XCTAssertFalse(model.beginLedgerCleanup(userConfirmed: true))
        XCTAssertTrue(next.requests.isEmpty); XCTAssertTrue(next.actions.isEmpty); XCTAssertEqual(next.reauths, 0)
        XCTAssertNil(model.receipt); XCTAssertNil(model.ledgerReceipt); XCTAssertFalse(model.accountDeletionComplete)
        assertAuthOnly(next)
    }

    func testResumeCoordinatorCannotStartNewEpochOrUseNormalReaderBegin() async throws {
        let (first, _) = try await lostParent(), next = try await restarted(first)
        let model = try XCTUnwrap(next.make(resume: true))
        XCTAssertFalse(model.begin(context: next.authContext, membershipEpoch: 8, userConfirmed: true))
        XCTAssertFalse(model.begin(context: next.authContext, membershipEpoch: 7, userConfirmed: true))
        XCTAssertTrue(next.requests.isEmpty); XCTAssertEqual(next.epochReads, 0)
        XCTAssertTrue(next.resume(model)); await eventually { model.canBeginLedgerCleanup }
        XCTAssertEqual(next.actions.first?.request.membershipEpoch, 7); assertAuthOnly(next)
    }

    func testLostLedgerResponseReconfirmsParentBeforeSeparateFreshLedgerActionAfterRestart() async throws {
        let first = try process(); await first.launch()
        let original = try XCTUnwrap(first.make(resume: false)); XCTAssertTrue(first.begin(original))
        await eventually { original.canBeginLedgerCleanup }
        first.lostResponses = [1]; first.now += 5_000
        XCTAssertTrue(original.beginLedgerCleanup(userConfirmed: true)); await eventually { original.canRetry }
        XCTAssertEqual(first.recovery.deletionCheckpoint?.phase, .ledger)
        let next = try await restarted(first), model = try XCTUnwrap(next.make(resume: true))
        XCTAssertFalse(model.beginLedgerCleanup(userConfirmed: true)); XCTAssertTrue(next.requests.isEmpty)
        XCTAssertTrue(next.resume(model)); await eventually { model.canBeginLedgerCleanup }
        XCTAssertEqual(next.requests.count, 1); XCTAssertEqual(next.requests[0].httpBody, first.requests[0].httpBody)
        XCTAssertEqual(next.recovery.deletionCheckpoint?.phase, .ledger)
        XCTAssertFalse(model.beginLedgerCleanup(userConfirmed: false)); XCTAssertEqual(next.reauths, 1)
        next.now += 5_000; XCTAssertTrue(model.beginLedgerCleanup(userConfirmed: true))
        await eventually { model.status == .ledgerDataRemoved && !model.hasPhysicalFlight }
        XCTAssertEqual(next.requests.count, 2); XCTAssertEqual(next.requests[1].httpBody, first.requests[1].httpBody)
        XCTAssertEqual(next.actions.map(\.phase), [.cloudSlice, .mutationLedger])
        XCTAssertNotEqual(next.actions[0].actionID, next.actions[1].actionID)
        XCTAssertEqual(next.reauths, 2); assertAuthOnly(next); XCTAssertFalse(model.accountDeletionComplete)
    }

    func testPendingReconfirmedParentCannotAuthorizeLedgerAndExplicitRetryRetainsOriginalParent() async throws {
        let (first, _) = try await lostParent(), next = try await restarted(first)
        next.statuses[0] = "pending"
        let model = try XCTUnwrap(next.make(resume: true)); XCTAssertTrue(next.resume(model))
        await eventually { model.canRetry }
        XCTAssertFalse(model.beginLedgerCleanup(userConfirmed: true)); XCTAssertEqual(next.requests.count, 1)
        next.now += 5_000; XCTAssertTrue(model.retry(userConfirmed: true))
        await eventually { model.canBeginLedgerCleanup }
        XCTAssertEqual(next.requests[0].httpBody, next.requests[1].httpBody)
        XCTAssertEqual(next.reauths, 2); assertAuthOnly(next)
    }

    func testWrongAccountAndGuestCannotBorrowPersistedOriginalRequest() async throws {
        let (first, _) = try await lostParent()
        let identities: [String?] = ["reader-B", nil]
        for uid in identities {
            let next = try await restarted(first, uid: uid)
            if let model = next.make(resume: true) { XCTAssertFalse(next.resume(model)) }
            XCTAssertTrue(next.actions.isEmpty); XCTAssertTrue(next.requests.isEmpty); assertAuthOnly(next)
        }
    }

    func testProviderRoundTripCannotReviveOriginalResumeActionOrInitializeReaderSDK() async throws {
        let (first, _) = try await lostParent(), next = try await restarted(first)
        let provider = next.hold(.provider), model = try XCTUnwrap(next.make(resume: true))
        XCTAssertTrue(next.resume(model)); await eventually { provider.entered }
        let original = next.authContext; next.observe("reader-B"); next.observe("reader-A")
        XCTAssertNotEqual(original, next.authContext); XCTAssertTrue(model.hasPhysicalFlight)
        provider.release(); await eventually { !model.hasPhysicalFlight }
        XCTAssertEqual(next.reauths, 0); XCTAssertTrue(next.requests.isEmpty); XCTAssertNil(model.receipt)
        assertAuthOnly(next)
    }

    func testSameUIDSDKUserReplacementDuringProviderCannotSupplyNewHeldIdentity() async throws {
        let (first, _) = try await lostParent(), next = try await restarted(first)
        let provider = next.hold(.provider), model = try XCTUnwrap(next.make(resume: true))
        XCTAssertTrue(next.resume(model)); await eventually { provider.entered }
        let original = next.authContext; next.user = User("reader-A")
        provider.release(); await eventually { !model.hasPhysicalFlight }
        XCTAssertEqual(next.authContext, original); XCTAssertEqual(next.reauths, 0)
        XCTAssertTrue(next.requests.isEmpty); assertAuthOnly(next)
    }

    func testCancelledResumeSDKAwaitKeepsSharedLoginSlotUntilActualReturn() async throws {
        let (first, _) = try await lostParent(), next = try await restarted(first)
        let sdk = next.hold(.sdk), model = try XCTUnwrap(next.make(resume: true))
        XCTAssertTrue(next.resume(model)); await eventually { sdk.entered }
        model.cancel(); XCTAssertTrue(model.hasPhysicalFlight); XCTAssertTrue(next.operations.isBusy)
        XCTAssertThrowsError(try next.operations.capture(.google)) {
            guard case AuthOperationCoordinator.Failure.busy = $0 else { return XCTFail("Expected busy") }
        }
        XCTAssertNil(next.make(resume: true)); sdk.release()
        await eventually { !model.hasPhysicalFlight && !next.operations.isBusy }
        XCTAssertTrue(next.requests.isEmpty); assertAuthOnly(next)
    }

    func testLateCredentialsAfterOriginalSDKUserReplacementCannotSendResumeRequest() async throws {
        let (first, _) = try await lostParent(), next = try await restarted(first)
        let credentials = next.hold(.credentials), model = try XCTUnwrap(next.make(resume: true))
        XCTAssertTrue(next.resume(model)); await eventually { credentials.entered }
        next.user = User("reader-A"); credentials.release()
        await eventually { !model.hasPhysicalFlight }
        XCTAssertEqual(next.reauths, 1); XCTAssertTrue(next.requests.isEmpty); assertAuthOnly(next)
    }

    func testChangedProjectAppOrEndpointCannotUseStoredRequestBeforeProvider() async throws {
        let (first, _) = try await lostParent()
        let mismatches = [
            ("other-project", "1:123456789:ios:abcdef123456", "https://deletion.example.invalid/reader"),
            ("local-deletion", "1:123456789:ios:abcdef654321", "https://deletion.example.invalid/reader"),
            ("local-deletion", "1:123456789:ios:abcdef123456", "https://other.example.invalid/reader")
        ]
        for (project, app, endpoint) in mismatches {
            let next = try process(root: first.root, endpoint: endpoint, projectID: project, appID: app)
            await next.launch(); XCTAssertNil(next.make(resume: true))
            XCTAssertTrue(next.actions.isEmpty); XCTAssertTrue(next.requests.isEmpty); assertAuthOnly(next)
        }
    }

    func testCorruptCheckpointKeepsStartupAndResumeClosedWithoutAutomaticRepair() async throws {
        let (first, _) = try await lostParent()
        let marker = try Data(contentsOf: first.markerFile), corrupt = Data("{broken-checkpoint".utf8)
        try corrupt.write(to: first.checkpointFile, options: .atomic)
        let next = try await restarted(first)
        XCTAssertNil(next.make(resume: true)); XCTAssertTrue(next.actions.isEmpty); XCTAssertTrue(next.requests.isEmpty)
        XCTAssertEqual(try Data(contentsOf: first.checkpointFile), corrupt)
        XCTAssertEqual(try Data(contentsOf: first.markerFile), marker); assertAuthOnly(next)
    }

    func testMarkerWithoutDeletionCheckpointCannotInventResumeRequest() async throws {
        let first = try process(); await first.launch()
        _ = try await first.recovery.seal(binding: .init(ownerUID: "reader-A", epoch: 7))
        let next = try await restarted(first)
        XCTAssertNil(next.recovery.deletionCheckpoint); XCTAssertNil(next.make(resume: true))
        XCTAssertTrue(next.requests.isEmpty); assertAuthOnly(next)
    }

    func testActualCheckpointReadbackMustFinishBeforeFirstHTTPAndCancellationCannotReopen() async throws {
        let files = FileControl(); files.holdCheckpoint()
        let first = try process(files: files); await first.launch()
        let model = try XCTUnwrap(first.make(resume: false)); XCTAssertTrue(first.begin(model))
        await eventually { files.checkpointWrites == 1 }
        XCTAssertTrue(model.hasPhysicalFlight); XCTAssertTrue(first.requests.isEmpty)
        XCTAssertEqual(first.credentials, 0); XCTAssertFalse(first.recovery.admission.isAllowed)
        model.cancel(); XCTAssertTrue(model.hasPhysicalFlight); XCTAssertFalse(model.abortBeforeSubmission())
        files.release(); await eventually { !model.hasPhysicalFlight }
        XCTAssertTrue(first.requests.isEmpty); XCTAssertFalse(model.abortBeforeSubmission())
        let next = try await restarted(first)
        XCTAssertNotNil(next.recovery.deletionCheckpoint); XCTAssertNotNil(next.make(resume: true)); assertAuthOnly(next)
    }

    func testCheckpointWriteFailurePreventsHTTPAndCannotBecomeResumeAuthority() async throws {
        let files = FileControl(); files.failCheckpoint()
        let first = try process(files: files); await first.launch()
        let model = try XCTUnwrap(first.make(resume: false)); XCTAssertTrue(first.begin(model))
        await eventually { !model.hasPhysicalFlight }
        XCTAssertEqual(files.checkpointWrites, 1); XCTAssertTrue(first.requests.isEmpty)
        XCTAssertFalse(model.abortBeforeSubmission()); XCTAssertFalse(first.recovery.admission.isAllowed)
        let next = try await restarted(first)
        XCTAssertNil(next.recovery.deletionCheckpoint); XCTAssertNil(next.make(resume: true)); assertAuthOnly(next)
    }

    func testUntrustedCompleteClaimDoesNotAuthorizeLedgerOrPurgePersistedRequest() async throws {
        let (first, _) = try await lostParent(), next = try await restarted(first)
        let before = try Data(contentsOf: next.checkpointFile); next.invalidResponse = true
        let model = try XCTUnwrap(next.make(resume: true)); XCTAssertTrue(next.resume(model))
        await eventually { model.canRetry }
        XCTAssertNil(model.receipt); XCTAssertFalse(model.canBeginLedgerCleanup); XCTAssertFalse(model.accountDeletionComplete)
        XCTAssertEqual(try Data(contentsOf: next.checkpointFile), before)
        XCTAssertFalse(model.abortBeforeSubmission()); assertAuthOnly(next)
    }

    func testSameResumeCoordinatorRetriesFailedLedgerCheckpointAfterStorageRepair() async throws {
        let (first, _) = try await lostParent(), next = try await restarted(first)
        let model = try XCTUnwrap(next.make(resume: true)); XCTAssertTrue(next.resume(model))
        await eventually { model.canBeginLedgerCleanup }
        let original = try XCTUnwrap(next.recovery.deletionCheckpoint)
        XCTAssertEqual(original.phase, .parent)
        next.files.failCheckpoint(); next.now += 5_000
        XCTAssertTrue(model.beginLedgerCleanup(userConfirmed: true))
        await eventually { model.canRetry }
        XCTAssertEqual(model.status, .unavailable); XCTAssertEqual(next.requests.count, 1)
        XCTAssertEqual(next.reauths, 2); XCTAssertEqual(next.recovery.deletionCheckpoint, original)
        XCTAssertEqual(next.recovery.status, .unavailable); XCTAssertFalse(model.abortBeforeSubmission())
        next.files.repairCheckpoint(); next.now += 5_000
        XCTAssertTrue(model.retry(userConfirmed: true))
        await eventually { model.status == .ledgerDataRemoved && !model.hasPhysicalFlight }
        XCTAssertEqual(next.requests.count, 2); XCTAssertEqual(next.reauths, 3)
        XCTAssertEqual(next.actions.map(\.phase), [.cloudSlice, .mutationLedger, .mutationLedger])
        XCTAssertNotEqual(next.actions[1].actionID, next.actions[2].actionID)
        XCTAssertEqual(next.recovery.deletionCheckpoint?.phase, .ledger)
        XCTAssertEqual(next.recovery.deletionCheckpoint?.request, original.request)
        XCTAssertFalse(model.accountDeletionComplete); assertAuthOnly(next)
    }
}
