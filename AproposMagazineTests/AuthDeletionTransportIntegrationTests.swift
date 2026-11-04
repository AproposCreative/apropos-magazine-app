import Combine
import FirebaseCore
import XCTest
@testable import Apropos

/// Actual AuthService composition -> reauthentication helper -> coordinator ->
/// HTTP adapter. All provider/user/token/HTTP effects are local injected values.
@MainActor
final class AuthDeletionTransportIntegrationTests: XCTestCase {
    private typealias Model = ReaderAccountDeletionCoordinator
    private typealias Contract = ReaderAccountDeletionContract
    private typealias Transport = ReaderDeletionHTTPTransport
    private typealias Bridge = ReaderAccountReauthentication<String>
    private enum Stage: Hashable { case provider, reauthentication, credentials, http }
    private enum FixtureFailure: Error { case malformedRequest }

    private final class User {
        let uid: String
        var email: String? = "held.user@example.invalid"
        var supportsPassword = true
        var appleSubject: String? = "apple-subject-A"
        var googleSubject: String? = "google-subject-A"
        init(_ uid: String) { self.uid = uid }
    }
    @MainActor private final class Gate {
        let entered: XCTestExpectation
        private var continuation: CheckedContinuation<Void, Never>?
        init(_ entered: XCTestExpectation) { self.entered = entered }
        func wait() async { await withCheckedContinuation { continuation = $0; entered.fulfill() } }
        func release() { let held = continuation; continuation = nil; held?.resume() }
    }
    @MainActor private final class Fixture {
        let auth = AuthService()
        let configuration: Transport.Configuration
        // Real source-journal reads use an isolated, initially absent temp root.
        // Snapshotting an empty journal creates no files or directories.
        let journal = FavoritesFileJournal(rootDirectory: FileManager.default.temporaryDirectory
            .appendingPathComponent("auth-deletion-barrier-" + UUID().uuidString, isDirectory: true))
        let recoveryRoot = FileManager.default.temporaryDirectory.appendingPathComponent("auth-deletion-recovery-" + UUID().uuidString)
        var failsRecoverySeal = false
        lazy var recovery = ReaderTransitionRecovery(store: .init(rootDirectory: recoveryRoot,
            replace: { [fails = failsRecoverySeal] data, url in
                if fails { throw CocoaError(.fileWriteUnknown) }
                try data.write(to: url, options: .atomic)
            }))
        var drainCalls = 0
        lazy var writers = ReaderWriterDrainRuntime(canonical: auth.state,
            actualUID: { [unowned self] in user?.uid }, makeDrain: { [unowned self] in
                drainCalls += 1
                return .init(wait: { completion in completion(nil) })
            })
        var resumeStore: ReaderResumeStore?
        var writeBarrier: Model.WriteBarrier { .init(writers: writers, journal: journal, recovery: recovery, resumeStore: resumeStore) }
        var user: User? = User("reader-A")
        var now: Int64 = 1_800_000_000_123
        var epoch: Int64? = 7
        var captures = 0, identityReads = 0, sdkReauths = 0, credentialCalls = 0
        var actions: [Model.ActionTicket] = []
        var credentialProofs: [Model.ReauthenticationResult] = []
        var capturedUsers: [User] = []
        var requests: [URLRequest] = []
        var credentialEmails: [String] = []
        var credentialPasswords: [String] = []
        var sdkError: Error?
        var makeCredentialHook: (() -> Void)?
        lazy var prompt = ReaderEmailReauthenticationPrompt(canonical: auth.state)
        lazy var applePrompt = ReaderAppleReauthenticationPrompt(canonical: auth.state)
        var appleFlows: [AppleAccountFlowModel] = []
        var appleCredentials: [(String, String)] = []
        var googleCallbacks: [@Sendable (GoogleSignInService.ReauthenticationIdentity?, Error?) -> Void] = []
        var googleTasks: [Task<Void, Never>] = []
        var googleCredentials: [(String, String)] = []
        lazy var googleService = GoogleSignInService(reauthenticationProvider: { [unowned self] admitted, callback in
            guard admitted() else { throw CancellationError() }
            googleCallbacks.append(callback)
        })
        lazy var googlePrompt = ReaderGoogleReauthenticationPrompt(canonical: auth.state, service: googleService)
        var holds: [Stage: Gate] = [:], allGates: [Gate] = []
        var deadlines: [@MainActor () -> Void] = []
        var models: [Model] = []
        var replyStatuses: [Int: String] = [:]
        var tokenAuthTime: Int64?
        var tokenLifetime: Int64 = 60_000
        var identityHook: (() -> Void)?, epochHook: (() -> Void)?, credentialHook: (() -> Void)?

        lazy var operations = AuthOperationCoordinator(canonical: auth.state, actualUserID: { [unowned self] in user?.uid })
        lazy var bridge = Bridge(canonical: auth.state, operations: operations, captureUser: { [unowned self] in
            captures += 1
            guard let original = user else { return nil }
            capturedUsers.append(original)
            return Bridge.HeldUser(uid: original.uid, isCurrent: { [unowned self] in
                identityReads += 1
                let result = user === original
                identityHook?()
                return result
            }, reauthenticate: { [unowned self] _, admitted in
                guard admitted() else { throw CancellationError() }
                sdkReauths += 1
                await pass(.reauthentication)
                guard admitted() else { throw CancellationError() }
                if let sdkError { throw sdkError }
                return .init(uid: original.uid, authTimeMs: (now / 1_000) * 1_000)
            }, deletionCredentials: { [unowned self] proof, _ in
                // Deliberately return after logical cancellation/replacement.
                // The actual composition/transport must reject this old result.
                credentialCalls += 1; credentialProofs.append(proof)
                await pass(.credentials)
                credentialHook?()
                return .init(ownerUID: original.uid, projectID: "local-deletion", appID: "1:123456789:ios:abcdef123456",
                    idToken: "local.id." + proof.action.actionID.uuidString,
                    appCheckToken: "local.app." + proof.action.actionID.uuidString,
                    authTimeMs: tokenAuthTime ?? proof.authTimeMs,
                    authValidUntilMs: now + tokenLifetime, appCheckValidUntilMs: now + tokenLifetime)
            }, email: original.email, supportsPassword: original.supportsPassword, appleSubject: original.appleSubject, googleSubject: original.googleSubject)
        }, nowMilliseconds: { [unowned self] in now })

        init(failSeal: Bool = false) async throws {
            failsRecoverySeal = failSeal
            configuration = try .init(projectID: "local-deletion", appID: "1:123456789:ios:abcdef123456",
                endpointURL: URL(string: "https://deletion.example.invalid/reader")!)
            select("reader-A")
            try await recovery.bootstrap()
        }
        var context: CanonicalSessionState.ContextTicket { auth.state.contextTicket() }
        func select(_ uid: String?) {
            if user?.uid != uid { user = uid.map(User.init) }
            auth.state.adopt(uid.map { .init(uid: $0, email: "local@example.invalid", isEmailVerified: true) })
        }
        func roundTrip() { select("reader-B"); select("reader-A") }
        func hold(_ stage: Stage, _ entered: XCTestExpectation) -> Gate {
            let gate = Gate(entered); holds[stage] = gate; allGates.append(gate); return gate
        }
        func pass(_ stage: Stage) async { if let gate = holds.removeValue(forKey: stage) { await gate.wait() } }
        func make(configured: Bool = true, hasBarrier: Bool = true) -> Model? {
            let model = auth.makeReaderAccountDeletion(configuration: configured ? configuration : nil,
                currentMembershipEpoch: { [unowned self] _ in epochHook?(); return epoch },
                reauthentication: bridge, obtainCredential: { [unowned self] action in
                    actions.append(action); await pass(.provider)
                    return "credential." + action.actionID.uuidString
                }, execute: { [unowned self] request in
                    let index = requests.count; requests.append(request)
                    await pass(.http)
                    return try response(for: request, index: index)
                }, now: { [unowned self] in now }, scheduleTimeout: { [unowned self] _, fire in
                    deadlines.append(fire); return {}
                }, writeBarrier: hasBarrier ? writeBarrier : nil)
            if let model { models.append(model) }
            return model
        }
        func makeEmail(configured: Bool = true) -> Model? {
            let model = auth.makeEmailReaderAccountDeletion(configuration: configured ? configuration : nil,
                currentMembershipEpoch: { [unowned self] _ in epochHook?(); return epoch },
                reauthentication: bridge, prompt: prompt,
                makeCredential: { [unowned self] email, password in
                    credentialEmails.append(email); credentialPasswords.append(password)
                    makeCredentialHook?()
                    return "local-password-credential"
                }, execute: { [unowned self] request in
                    let index = requests.count; requests.append(request)
                    await pass(.http)
                    return try response(for: request, index: index)
                }, now: { [unowned self] in now }, scheduleTimeout: { [unowned self] _, fire in
                    deadlines.append(fire); return {}
                }, writeBarrier: writeBarrier)
            if let model { models.append(model) }
            return model
        }
        func makeApple(configured: Bool = true) -> Model? {
            let model = auth.makeAppleReaderAccountDeletion(configuration: configured ? configuration : nil,
                currentMembershipEpoch: { [unowned self] _ in epochHook?(); return epoch },
                reauthentication: bridge, prompt: applePrompt,
                makeCredential: { [unowned self] token, nonce in
                    appleCredentials.append((token, nonce)); makeCredentialHook?()
                    return "local-apple-credential"
                }, execute: { [unowned self] request in
                    let index = requests.count; requests.append(request)
                    await pass(.http); return try response(for: request, index: index)
                }, now: { [unowned self] in now }, scheduleTimeout: { [unowned self] _, fire in
                    deadlines.append(fire); return {}
                }, writeBarrier: writeBarrier)
            if let model { models.append(model) }
            return model
        }
        func makeGoogle(configured: Bool = true) -> Model? {
            let model = auth.makeGoogleReaderAccountDeletion(configuration: configured ? configuration : nil,
                currentMembershipEpoch: { [unowned self] _ in epochHook?(); return epoch },
                reauthentication: bridge, prompt: googlePrompt,
                makeCredential: { [unowned self] token, access in
                    googleCredentials.append((token, access)); makeCredentialHook?()
                    return "local-google-credential"
                }, execute: { [unowned self] request in
                    let index = requests.count; requests.append(request)
                    await pass(.http); return try response(for: request, index: index)
                }, now: { [unowned self] in now }, scheduleTimeout: { [unowned self] _, fire in
                    deadlines.append(fire); return {}
                }, writeBarrier: writeBarrier)
            if let model { models.append(model) }
            return model
        }
        func begin(_ model: Model) -> Bool { model.begin(context: context, membershipEpoch: epoch ?? 7, userConfirmed: true) }
        func response(for request: URLRequest, index: Int) throws -> (Data, HTTPURLResponse) {
            guard let data = request.httpBody, let body = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let uid = body["expectedUID"] as? String, let epoch = body["membershipEpoch"] as? Int64,
                  let url = request.url else { throw FixtureFailure.malformedRequest }
            let ledger = body["scope"] as? String == Contract.ledgerScope
            let status = replyStatuses[index] ?? (ledger ? "ledgerDataRemoved" : "scopedCloudDataRemoved")
            let parent = try Contract.Request(expectedUID: uid, membershipEpoch: epoch)
            let id: String
            if ledger {
                guard let parentID = body["parentRequestID"] as? String else { throw FixtureFailure.malformedRequest }
                id = try Contract.LedgerRequest(expectedUID: uid, membershipEpoch: epoch, parentRequestID: parentID).requestID
            } else { id = parent.requestID }
            var reply: [String: Any] = ["requestID": id, "scope": ledger ? Contract.ledgerScope : Contract.scope,
                "status": status, "accountDeletionComplete": false, "unresolved": ledger ? Contract.ledgerUnresolved : Contract.unresolved]
            if status == "ledgerDataRemoved" {
                reply["parentRequestID"] = parent.requestID; reply["removedReceiptDocuments"] = 4; reply["removedRevisionDocuments"] = 2
            } else if status == "scopedCloudDataRemoved" { reply["removedFavoriteDocuments"] = 3 }
            else if status == "paused" { reply["code"] = "reader_boundary_unverified" }
            guard let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]) else { throw FixtureFailure.malformedRequest }
            return (try JSONSerialization.data(withJSONObject: reply), response)
        }
        func close() {
            try? FileManager.default.removeItem(at: recoveryRoot)
            identityHook = nil; epochHook = nil; credentialHook = nil; makeCredentialHook = nil
            prompt.cancel(); applePrompt.cancel(); googlePrompt.cancel()
            for callback in googleCallbacks { callback(nil, CancellationError()) }
            googleTasks.forEach { $0.cancel() }
            for flow in appleFlows { if let id = flow.activeTicketID { flow.providerCancelled(ticketID: id) } }
            models.forEach { $0.cancel() }; allGates.forEach { $0.release() }
        }
    }

    override func setUp() { super.setUp(); XCTAssertNil(FirebaseApp.allApps) }
    override func tearDown() { XCTAssertNil(FirebaseApp.allApps); super.tearDown() }
    private func eventually(_ predicate: () -> Bool, file: StaticString = #filePath, line: UInt = #line) async {
        for _ in 0..<2_000 {
            if predicate() { return }
            // The actual journal snapshot now crosses a real utility I/O queue.
            try? await Task.sleep(nanoseconds: 1_000_000)
        }
        XCTFail("Expected injected asynchronous state was not reached", file: file, line: line)
    }
    private func parentComplete(_ f: Fixture, _ model: Model) async {
        XCTAssertTrue(f.begin(model)); await eventually { model.status == .scopedCloudDataRemoved && !model.hasPhysicalFlight }
    }
    private func body(_ request: URLRequest) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: Any])
    }

    private enum LocalDrainEnding { case success, cancellation, deadline, accountRoundTrip, sealFailure }

    private func exerciseResumeDrain(holdReadback: Bool, ending: LocalDrainEnding) async throws {
        let f = try await Fixture(failSeal: ending == .sealFailure); defer { f.close() }
        let entered = expectation(description: "Original accepted local storage is physically held")
        let memory = DeletionResumeMemory(entered: entered)
        defer { memory.release() }
        let store = ReaderResumeStore(storage: memory.storage)
        f.resumeStore = store
        let item = try XCTUnwrap(ReaderResumeIdentity(articleID: "article", sourceRevision: "v1", html: "<p>Original</p>"))
        let ownerA = "account_" + String(repeating: "a", count: 64)
        let ownerB = "account_" + String(repeating: "b", count: 64)
        let anchor = ReaderResumeAnchor(index: 4, fingerprint: "1234abcd")
        try await store.save(owner: "guest", source: item, anchor: anchor)
        try await store.save(owner: ownerB, source: item, anchor: anchor)
        memory.holdNextWrite(readback: holdReadback)
        let receipt = try store.accept(owner: ownerA, source: item, anchor: anchor)
        await fulfillment(of: [entered], timeout: 3)
        let model = try XCTUnwrap(f.make())
        XCTAssertTrue(f.begin(model))
        await eventually { !f.recovery.admission.isAllowed }
        // Deliberately let the old physical operation remain held after seal.
        for _ in 0..<30 { await Task.yield() }
        XCTAssertTrue(model.hasPhysicalFlight)
        XCTAssertEqual(f.credentialCalls, 0); XCTAssertTrue(f.requests.isEmpty)
        XCTAssertFalse(model.canRetry); XCTAssertFalse(model.retry(userConfirmed: true))
        switch ending {
        case .success: break
        case .sealFailure: await eventually { !f.recovery.isBusy }
        case .cancellation: model.cancel()
        case .deadline: try XCTUnwrap(f.deadlines.first)()
        case .accountRoundTrip: f.roundTrip()
        }
        XCTAssertTrue(model.hasPhysicalFlight)
        XCTAssertFalse(model.canRetry); XCTAssertEqual(f.credentialCalls, 0)
        XCTAssertTrue(f.requests.isEmpty)
        memory.release()
        try await receipt.value()
        await eventually { !model.hasPhysicalFlight }
        switch ending {
        case .success:
            XCTAssertEqual(model.status, .scopedCloudDataRemoved)
            XCTAssertEqual(f.credentialCalls, 1); XCTAssertEqual(f.requests.count, 1)
        case .cancellation, .deadline, .accountRoundTrip, .sealFailure:
            XCTAssertNil(model.receipt); XCTAssertEqual(f.credentialCalls, 0)
            XCTAssertTrue(f.requests.isEmpty)
        }
        // This barrier is not purge: every accepted original owner remains.
        let a = try await store.load(owner: ownerA, source: item)
        let b = try await store.load(owner: ownerB, source: item)
        let guest = try await store.load(owner: "guest", source: item)
        XCTAssertEqual(a, anchor); XCTAssertEqual(b, anchor); XCTAssertEqual(guest, anchor)
        XCTAssertFalse(f.recovery.admission.isAllowed)
    }

    func testActualDeletionWaitsForAcceptedResumeWriteBeforeCredentialsAndHTTP() async throws {
        try await exerciseResumeDrain(holdReadback: false, ending: .success)
    }
    func testActualDeletionWaitsForResumeReadbackBeforeCredentialsAndHTTP() async throws {
        try await exerciseResumeDrain(holdReadback: true, ending: .success)
    }
    func testCancellationKeepsOriginalResumeReadbackFlightWithoutSending() async throws {
        try await exerciseResumeDrain(holdReadback: true, ending: .cancellation)
    }
    func testDeadlineKeepsOriginalResumeWriteFlightWithoutSending() async throws {
        try await exerciseResumeDrain(holdReadback: false, ending: .deadline)
    }
    func testAccountRoundTripKeepsOriginalResumeReadbackFlightWithoutSending() async throws {
        try await exerciseResumeDrain(holdReadback: true, ending: .accountRoundTrip)
    }

    func testRecoverySealFailureStillWaitsForAcceptedResumeReadbackWithoutHTTP() async throws {
        try await exerciseResumeDrain(holdReadback: true, ending: .sealFailure)
    }

    func testMissingConfigurationDoesNotCaptureUserOrStartAnyCredentialOrHTTPWork() async throws {
        let f = try await Fixture(); defer { f.close() }
        XCTAssertNil(f.make(configured: false))
        for _ in 0..<10 { await Task.yield() }
        XCTAssertEqual(f.captures, 0); XCTAssertEqual(f.identityReads, 0); XCTAssertEqual(f.sdkReauths, 0)
        XCTAssertEqual(f.credentialCalls, 0); XCTAssertTrue(f.actions.isEmpty); XCTAssertTrue(f.requests.isEmpty)
        XCTAssertTrue(f.deadlines.isEmpty); XCTAssertFalse(f.operations.isBusy)
    }

    func testMissingWriterBarrierDoesNotCaptureUserOrStartAnyCredentialOrHTTPWork() async throws {
        let f = try await Fixture(); defer { f.close() }
        XCTAssertNil(f.make(hasBarrier: false))
        for _ in 0..<10 { await Task.yield() }
        XCTAssertEqual(f.captures, 0); XCTAssertEqual(f.identityReads, 0); XCTAssertEqual(f.sdkReauths, 0)
        XCTAssertEqual(f.credentialCalls, 0); XCTAssertTrue(f.actions.isEmpty); XCTAssertTrue(f.requests.isEmpty)
        XCTAssertEqual(f.drainCalls, 0); XCTAssertTrue(f.deadlines.isEmpty); XCTAssertFalse(f.operations.isBusy)
    }

    func testActualCompositionSendsTwoExplicitPhasesWithSeparateHeldUserReauthenticationAndTokens() async throws {
        let f = try await Fixture(); defer { f.close() }; let model = try XCTUnwrap(f.make())
        await parentComplete(f, model); let acceptedParent = model.receipt
        XCTAssertEqual(f.actions.count, 1); XCTAssertEqual(f.requests.count, 1)
        XCTAssertFalse(model.beginLedgerCleanup(userConfirmed: false)); XCTAssertEqual(f.actions.count, 1)
        f.now += 5_000; XCTAssertTrue(model.beginLedgerCleanup(userConfirmed: true))
        await eventually { model.status == .ledgerDataRemoved && !model.hasPhysicalFlight }
        XCTAssertEqual(f.sdkReauths, 2); XCTAssertEqual(f.credentialCalls, 2); XCTAssertEqual(f.actions.count, 2)
        XCTAssertEqual(f.actions.map(\.phase), [.cloudSlice, .mutationLedger])
        XCTAssertNotEqual(f.actions[0].actionID, f.actions[1].actionID)
        XCTAssertEqual(f.credentialProofs.map(\.action), f.actions)
        XCTAssertTrue(f.capturedUsers[0] === f.capturedUsers[1])
        let first = try body(f.requests[0]), second = try body(f.requests[1])
        XCTAssertEqual(Set(first.keys), ["expectedUID", "membershipEpoch"])
        XCTAssertEqual(first["expectedUID"] as? String, "reader-A"); XCTAssertEqual(first["membershipEpoch"] as? Int, 7)
        XCTAssertEqual(second["scope"] as? String, Contract.ledgerScope)
        XCTAssertEqual(second["parentRequestID"] as? String, acceptedParent?.requestID)
        XCTAssertEqual(model.receipt, acceptedParent); XCTAssertEqual(model.ledgerReceipt?.removedReceiptDocuments, 4)
        XCTAssertFalse(model.accountDeletionComplete)
        for (index, request) in f.requests.enumerated() {
            XCTAssertEqual(request.httpMethod, "POST"); XCTAssertEqual(request.url, f.configuration.endpointURL)
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer local.id." + f.actions[index].actionID.uuidString)
            XCTAssertEqual(request.value(forHTTPHeaderField: "X-Firebase-AppCheck"), "local.app." + f.actions[index].actionID.uuidString)
        }
    }

    func testPendingRetryKeepsExactBodyButUsesNewActionFreshProofAndAppCheckToken() async throws {
        let f = try await Fixture(); defer { f.close() }; f.replyStatuses[0] = "pending"
        let model = try XCTUnwrap(f.make()); XCTAssertTrue(f.begin(model))
        await eventually { model.status == .pending && !model.hasPhysicalFlight }
        XCTAssertFalse(model.canBeginLedgerCleanup); XCTAssertFalse(model.retry(userConfirmed: false))
        f.now += 5_000; XCTAssertTrue(model.retry(userConfirmed: true))
        await eventually { model.status == .scopedCloudDataRemoved && !model.hasPhysicalFlight }
        XCTAssertEqual(f.requests.count, 2); XCTAssertEqual(f.requests[0].httpBody, f.requests[1].httpBody)
        XCTAssertNotEqual(f.requests[0].value(forHTTPHeaderField: "Authorization"), f.requests[1].value(forHTTPHeaderField: "Authorization"))
        XCTAssertNotEqual(f.requests[0].value(forHTTPHeaderField: "X-Firebase-AppCheck"), f.requests[1].value(forHTTPHeaderField: "X-Firebase-AppCheck"))
        XCTAssertGreaterThan(f.credentialProofs[1].authTimeMs, f.credentialProofs[0].authTimeMs)
        XCTAssertEqual(f.actions[0].request, f.actions[1].request); XCTAssertEqual(f.sdkReauths, 2)
    }

    func testSameUIDReplacementDuringCredentialWaitCannotBorrowOriginalReauthentication() async throws {
        let f = try await Fixture(); defer { f.close() }; let model = try XCTUnwrap(f.make())
        let gate = f.hold(.credentials, expectation(description: "Original held user credentials"))
        XCTAssertTrue(f.begin(model)); await fulfillment(of: [gate.entered], timeout: 3)
        let context = f.context; f.user = User("reader-A"); XCTAssertEqual(f.context, context)
        gate.release(); await eventually { !model.hasPhysicalFlight }
        XCTAssertNil(model.receipt); XCTAssertTrue(f.requests.isEmpty); XCTAssertEqual(f.sdkReauths, 1)
    }

    func testAccountRoundTripDuringCredentialWaitCannotSendOldAction() async throws {
        let f = try await Fixture(); defer { f.close() }; let model = try XCTUnwrap(f.make())
        let gate = f.hold(.credentials, expectation(description: "Old A credentials"))
        XCTAssertTrue(f.begin(model)); await fulfillment(of: [gate.entered], timeout: 3)
        let original = f.context; f.roundTrip(); XCTAssertNotEqual(f.context, original)
        gate.release(); await eventually { !model.hasPhysicalFlight }
        XCTAssertNil(model.receipt); XCTAssertTrue(f.requests.isEmpty); XCTAssertFalse(model.accountDeletionComplete)
    }

    func testSameUIDReplacementDuringHTTPWaitCannotAcceptOldReceipt() async throws {
        let f = try await Fixture(); defer { f.close() }; let model = try XCTUnwrap(f.make())
        let gate = f.hold(.http, expectation(description: "Original HTTP request"))
        XCTAssertTrue(f.begin(model)); await fulfillment(of: [gate.entered], timeout: 3)
        f.user = User("reader-A"); XCTAssertTrue(model.hasPhysicalFlight)
        gate.release(); await eventually { !model.hasPhysicalFlight }
        XCTAssertEqual(f.requests.count, 1); XCTAssertNil(model.receipt); XCTAssertFalse(model.canBeginLedgerCleanup)
    }

    func testAccountRoundTripDuringHTTPWaitDoesNotPublishOldReceiptIntoNewA() async throws {
        let f = try await Fixture(); defer { f.close() }; let model = try XCTUnwrap(f.make())
        let gate = f.hold(.http, expectation(description: "A HTTP reply held"))
        XCTAssertTrue(f.begin(model)); await fulfillment(of: [gate.entered], timeout: 3)
        f.roundTrip(); XCTAssertTrue(model.hasPhysicalFlight); XCTAssertFalse(f.begin(model))
        gate.release(); await eventually { !model.hasPhysicalFlight }
        XCTAssertNil(model.receipt); XCTAssertNil(model.ledgerReceipt); XCTAssertEqual(f.requests.count, 1)
    }

    func testTimeoutKeepsPhysicalHTTPFlightAndExactRetryUntilOldCallbackReturns() async throws {
        let f = try await Fixture(); defer { f.close() }; let model = try XCTUnwrap(f.make())
        let gate = f.hold(.http, expectation(description: "Physical HTTP completion"))
        XCTAssertTrue(f.begin(model)); await fulfillment(of: [gate.entered], timeout: 3)
        let requestID = model.requestID; f.deadlines[0]()
        XCTAssertEqual(model.status, .timedOut); XCTAssertTrue(model.hasPhysicalFlight)
        XCTAssertFalse(model.canRetry); XCTAssertFalse(model.retry(userConfirmed: true)); XCTAssertNil(f.make())
        gate.release(); await eventually { !model.hasPhysicalFlight }
        XCTAssertEqual(model.status, .timedOut); XCTAssertNil(model.receipt); XCTAssertTrue(model.canRetry)
        f.now += 5_000; XCTAssertTrue(model.retry(userConfirmed: true))
        await eventually { model.status == .scopedCloudDataRemoved && !model.hasPhysicalFlight }
        XCTAssertEqual(model.requestID, requestID); XCTAssertEqual(f.requests[0].httpBody, f.requests[1].httpBody)
        XCTAssertEqual(f.sdkReauths, 2)
    }

    func testCancellationHoldsPhysicalHTTPSlotAndRejectsLateReceiptBeforeNewExplicitAction() async throws {
        let f = try await Fixture(); defer { f.close() }; let model = try XCTUnwrap(f.make())
        let gate = f.hold(.http, expectation(description: "Cancelled physical HTTP"))
        XCTAssertTrue(f.begin(model)); await fulfillment(of: [gate.entered], timeout: 3)
        model.cancel(); XCTAssertEqual(model.status, .cancelled); XCTAssertTrue(model.hasPhysicalFlight)
        XCTAssertFalse(f.begin(model)); XCTAssertFalse(model.retry(userConfirmed: true)); XCTAssertNil(f.make())
        gate.release(); await eventually { !model.hasPhysicalFlight }
        XCTAssertNil(model.receipt); XCTAssertFalse(model.canRetry)
        f.now += 5_000; XCTAssertTrue(f.begin(model)); await eventually { model.status == .scopedCloudDataRemoved }
        XCTAssertEqual(f.requests.count, 2); XCTAssertNotEqual(f.actions[0].actionID, f.actions[1].actionID)
    }

    func testWrongTokenAuthTimeCannotSendDespiteValidLocalReauthenticationProof() async throws {
        let f = try await Fixture(); defer { f.close() }; f.tokenAuthTime = (f.now / 1_000) * 1_000 - 1_000
        let model = try XCTUnwrap(f.make()); XCTAssertTrue(f.begin(model))
        await eventually { !model.hasPhysicalFlight && f.credentialCalls == 1 }
        XCTAssertEqual(f.sdkReauths, 1); XCTAssertTrue(f.requests.isEmpty); XCTAssertNil(model.receipt)
    }

    func testCredentialExpiryCannotStartHTTPOrBeSilentlyRefreshedIntoNewAuthority() async throws {
        let f = try await Fixture(); defer { f.close() }; f.tokenLifetime = 0
        let model = try XCTUnwrap(f.make()); XCTAssertTrue(f.begin(model))
        await eventually { !model.hasPhysicalFlight && f.credentialCalls == 1 }
        XCTAssertTrue(f.requests.isEmpty); XCTAssertEqual(f.captures, 1); XCTAssertEqual(f.sdkReauths, 1)
        XCTAssertNil(model.receipt)
    }

    func testReentrantHeldUserGetterCannotReturnStaleTrueAndStartHTTP() async throws {
        let f = try await Fixture(); defer { f.close() }; let model = try XCTUnwrap(f.make())
        let gate = f.hold(.credentials, expectation(description: "Credentials before reentrant identity read"))
        XCTAssertTrue(f.begin(model)); await fulfillment(of: [gate.entered], timeout: 3)
        f.identityHook = { f.identityHook = nil; f.roundTrip() }
        gate.release(); await eventually { !model.hasPhysicalFlight }
        XCTAssertTrue(f.requests.isEmpty); XCTAssertNil(model.receipt)
    }

    func testReentrantEpochGetterCannotBorrowNewGenerationForAnOldAction() async throws {
        let f = try await Fixture(); defer { f.close() }; let model = try XCTUnwrap(f.make())
        f.epochHook = { f.epochHook = nil; f.roundTrip() }
        XCTAssertFalse(f.begin(model))
        for _ in 0..<10 { await Task.yield() }
        XCTAssertTrue(f.actions.isEmpty); XCTAssertTrue(f.requests.isEmpty); XCTAssertEqual(f.captures, 0)
    }

    func testFactoryReplacementRemainsRefusedAfterPossibleSubmissionWhileOriginalRetryStillWorks() async throws {
        let f = try await Fixture(); defer { f.close() }; f.replyStatuses[0] = "pending"
        let old = try XCTUnwrap(f.make()), gate = f.hold(.http, expectation(description: "Original owner HTTP"))
        XCTAssertTrue(f.begin(old)); await fulfillment(of: [gate.entered], timeout: 3)
        XCTAssertNil(f.make()); gate.release()
        await eventually { old.status == .pending && !old.hasPhysicalFlight }
        XCTAssertTrue(old.hasWriteBarrier)
        XCTAssertNil(f.make(), "A returned HTTP callback does not reopen the original writer boundary")
        let originalRequest = try XCTUnwrap(f.requests.first)
        let originalAction = try XCTUnwrap(f.actions.first)
        f.now += 5_000
        XCTAssertTrue(old.retry(userConfirmed: true))
        await eventually { old.status == .scopedCloudDataRemoved && !old.hasPhysicalFlight }
        XCTAssertEqual(f.requests.count, 2); XCTAssertEqual(f.requests.last?.httpBody, originalRequest.httpBody)
        XCTAssertEqual(f.actions.count, 2); XCTAssertNotEqual(f.actions.last?.actionID, originalAction.actionID)
        XCTAssertEqual(f.drainCalls, 2, "Each explicit attempt obtains a fresh physical drain")
        XCTAssertNil(f.make()); XCTAssertFalse(old.abortBeforeSubmission()); XCTAssertFalse(old.accountDeletionComplete)
    }

    func testReentrantFactoryReplacementDuringOldCancellationKeepsNewestOwner() async throws {
        let f = try await Fixture(); defer { f.close() }; let old = try XCTUnwrap(f.make())
        var armed = true
        var nested: Model?
        let observer = old.objectWillChange.sink {
            if armed { armed = false; nested = f.make() }
        }
        let superseded = f.make()
        XCTAssertFalse(armed); XCTAssertNil(superseded)
        let newest = try XCTUnwrap(nested)
        XCTAssertFalse(newest === old)
        XCTAssertEqual(f.captures, 0); XCTAssertTrue(f.actions.isEmpty); XCTAssertTrue(f.requests.isEmpty)
        await parentComplete(f, newest)
        XCTAssertEqual(f.actions.count, 1); XCTAssertEqual(f.requests.count, 1)
        XCTAssertEqual(newest.receipt?.status, .scopedCloudDataRemoved); XCTAssertNil(old.receipt)
        withExtendedLifetime(observer) {}
    }

    func testRetainedOldCoordinatorCannotBeginProviderAfterFactoryReplacement() async throws {
        let f = try await Fixture(); defer { f.close() }; let old = try XCTUnwrap(f.make())
        let replacement = try XCTUnwrap(f.make())
        // This is a fresh begin, not retry of the cancelled intent. It reaches
        // the actual composition's owner check before any provider effect.
        _ = f.begin(old)
        await eventually { !old.hasPhysicalFlight }
        XCTAssertEqual(f.captures, 0); XCTAssertTrue(f.actions.isEmpty)
        XCTAssertEqual(f.sdkReauths, 0); XCTAssertEqual(f.credentialCalls, 0); XCTAssertTrue(f.requests.isEmpty)
        XCTAssertNil(old.receipt)
        await parentComplete(f, replacement)
        XCTAssertEqual(f.actions.count, 1); XCTAssertEqual(f.requests.count, 1)
        XCTAssertNil(old.receipt); XCTAssertFalse(old.accountDeletionComplete)
    }

    private func emailPresentation(_ f: Fixture) async throws -> ReaderEmailReauthenticationPrompt.Presentation {
        await eventually { f.prompt.presentation != nil }
        return try XCTUnwrap(f.prompt.presentation)
    }
    private func submitPassword(_ presentation: ReaderEmailReauthenticationPrompt.Presentation,
                                _ password: String = "Local123!") throws -> Task<Void, Never> {
        presentation.form.form.password = password
        let submission = try XCTUnwrap(presentation.form.captureSubmission())
        return Task { await presentation.form.submit(submission) }
    }

    func testEmailMissingEndpointNeverPresentsOrCapturesProvider() async throws {
        let f = try await Fixture(); defer { f.close() }
        XCTAssertNil(f.makeEmail(configured: false)); XCTAssertNil(f.prompt.presentation)
        XCTAssertEqual(f.captures, 0); XCTAssertTrue(f.credentialEmails.isEmpty); XCTAssertTrue(f.requests.isEmpty)
    }

    func testEmailUsesCapturedSDKEmailAndWaitsForActualSDKBeforeClosing() async throws {
        let f = try await Fixture(); defer { f.close() }; let model = try XCTUnwrap(f.makeEmail())
        XCTAssertTrue(f.begin(model)); let presentation = try await emailPresentation(f)
        XCTAssertEqual(presentation.email, "held.user@example.invalid")
        f.user?.email = "later@example.invalid"
        presentation.form.form.email = "edited@example.invalid"
        let gate = f.hold(.reauthentication, expectation(description: "SDK held"))
        let submit = try submitPassword(presentation)
        await fulfillment(of: [gate.entered], timeout: 3)
        XCTAssertEqual(f.credentialEmails, ["held.user@example.invalid"])
        XCTAssertTrue(presentation.form.form.password.isEmpty); XCTAssertTrue(presentation.form.isWorking)
        XCTAssertEqual(f.prompt.presentation?.id, presentation.id); XCTAssertTrue(f.requests.isEmpty)
        gate.release(); await submit.value
        await eventually { model.status == .scopedCloudDataRemoved && !model.hasPhysicalFlight }
        XCTAssertNil(f.prompt.presentation); XCTAssertNil(presentation.form.authenticatedSession)
        XCTAssertEqual(f.auth.state.snapshot.session?.uid, "reader-A"); XCTAssertEqual(f.requests.count, 1)
    }

    func testEmailWrongPasswordClearsDraftThenExplicitRetryCreatesNewAction() async throws {
        let f = try await Fixture(); defer { f.close() }; f.sdkError = NSError(domain: "LocalAuth", code: 17009)
        let model = try XCTUnwrap(f.makeEmail()); XCTAssertTrue(f.begin(model))
        let first = try await emailPresentation(f); let submit = try submitPassword(first, "WrongLocal!"); await submit.value
        await eventually { !model.hasPhysicalFlight }
        XCTAssertNotNil(first.form.errorMessage); XCTAssertTrue(first.form.form.password.isEmpty)
        XCTAssertNil(first.form.authenticatedSession); XCTAssertTrue(f.requests.isEmpty)
        XCTAssertEqual(f.prompt.presentation?.id, first.id)
        f.sdkError = nil; f.now += 1_000; f.prompt.retry()
        await eventually { f.prompt.presentation?.id != nil && f.prompt.presentation?.id != first.id }
        let second = try XCTUnwrap(f.prompt.presentation); XCTAssertNotEqual(first.action.actionID, second.action.actionID)
        XCTAssertTrue(second.form.form.password.isEmpty)
        let retry = try submitPassword(second, "FreshLocal!"); await retry.value
        await eventually { model.status == .scopedCloudDataRemoved && !model.hasPhysicalFlight }
        XCTAssertEqual(f.sdkReauths, 2); XCTAssertEqual(f.credentialPasswords, ["WrongLocal!", "FreshLocal!"])
        XCTAssertEqual(f.requests.count, 1); XCTAssertNil(f.prompt.presentation)
    }

    func testEmailCancelBeforeSubmitClearsDraftAndReleasesProviderWithoutSDK() async throws {
        let f = try await Fixture(); defer { f.close() }; let model = try XCTUnwrap(f.makeEmail())
        XCTAssertTrue(f.begin(model)); let presentation = try await emailPresentation(f)
        presentation.form.form.password = "UnsentLocal!"; f.prompt.cancel(action: presentation.action)
        await eventually { !model.hasPhysicalFlight && !f.operations.isBusy }
        XCTAssertTrue(presentation.form.form.password.isEmpty); XCTAssertNil(f.prompt.presentation)
        XCTAssertNil(presentation.form.captureSubmission()); XCTAssertEqual(f.sdkReauths, 0)
        XCTAssertTrue(f.credentialEmails.isEmpty); XCTAssertTrue(f.requests.isEmpty)
    }

    func testEmailCancelDuringSDKRetainsPhysicalSlotAndRejectsLateSuccess() async throws {
        let f = try await Fixture(); defer { f.close() }; let model = try XCTUnwrap(f.makeEmail())
        XCTAssertTrue(f.begin(model)); let presentation = try await emailPresentation(f)
        let gate = f.hold(.reauthentication, expectation(description: "Held password verification"))
        let submit = try submitPassword(presentation); await fulfillment(of: [gate.entered], timeout: 3)
        f.prompt.cancel(action: presentation.action); await submit.value
        XCTAssertTrue(model.hasPhysicalFlight); XCTAssertNil(f.makeEmail())
        XCTAssertNil(f.prompt.presentation); XCTAssertTrue(presentation.form.form.password.isEmpty)
        gate.release(); await eventually { !model.hasPhysicalFlight }
        XCTAssertTrue(f.requests.isEmpty); XCTAssertEqual(f.credentialCalls, 0); XCTAssertNil(model.receipt)
    }

    func testEmailAccountRoundTripBeforeSubmissionRetiresOriginalPrompt() async throws {
        let f = try await Fixture(); defer { f.close() }; let model = try XCTUnwrap(f.makeEmail())
        XCTAssertTrue(f.begin(model)); let presentation = try await emailPresentation(f)
        presentation.form.form.password = "OldLocal!"; f.roundTrip()
        await eventually { !model.hasPhysicalFlight }
        XCTAssertNil(f.prompt.presentation); XCTAssertTrue(presentation.form.form.password.isEmpty)
        XCTAssertNil(presentation.form.captureSubmission()); XCTAssertEqual(f.sdkReauths, 0); XCTAssertTrue(f.requests.isEmpty)
    }

    func testEmailSameUIDNewSDKInstanceCannotSubmitOriginalPrompt() async throws {
        let f = try await Fixture(); defer { f.close() }; let model = try XCTUnwrap(f.makeEmail())
        XCTAssertTrue(f.begin(model)); let presentation = try await emailPresentation(f)
        f.user = User("reader-A"); presentation.form.form.password = "OldInstance!"
        XCTAssertNil(presentation.form.captureSubmission())
        await eventually { !model.hasPhysicalFlight }
        XCTAssertNil(f.prompt.presentation); XCTAssertTrue(presentation.form.form.password.isEmpty)
        XCTAssertTrue(f.credentialEmails.isEmpty); XCTAssertEqual(f.sdkReauths, 0)
    }

    func testEmailAccountRoundTripDuringSDKCannotPublishOldError() async throws {
        let f = try await Fixture(); defer { f.close() }; f.sdkError = NSError(domain: "LocalAuth", code: 17009)
        let model = try XCTUnwrap(f.makeEmail()); XCTAssertTrue(f.begin(model)); let presentation = try await emailPresentation(f)
        let gate = f.hold(.reauthentication, expectation(description: "Old SDK verification"))
        let submit = try submitPassword(presentation); await fulfillment(of: [gate.entered], timeout: 3)
        f.roundTrip(); await submit.value; XCTAssertTrue(model.hasPhysicalFlight)
        gate.release(); await eventually { !model.hasPhysicalFlight }
        XCTAssertNil(f.prompt.presentation); XCTAssertNil(presentation.form.errorMessage)
        XCTAssertTrue(presentation.form.form.password.isEmpty); XCTAssertTrue(f.requests.isEmpty)
    }

    func testEmailCoordinatorDeadlineBeforeInputClosesPromptWithoutCredentialCreation() async throws {
        let f = try await Fixture(); defer { f.close() }; let model = try XCTUnwrap(f.makeEmail())
        XCTAssertTrue(f.begin(model)); let presentation = try await emailPresentation(f)
        presentation.form.form.password = "NeverSent!"; try XCTUnwrap(f.deadlines.last)()
        await eventually { !model.hasPhysicalFlight }
        XCTAssertNil(f.prompt.presentation); XCTAssertTrue(presentation.form.form.password.isEmpty)
        XCTAssertTrue(f.credentialEmails.isEmpty); XCTAssertEqual(f.sdkReauths, 0)
    }

    func testEmailCredentialConstructorReentryCannotStartSDKOrHTTPRequest() async throws {
        let f = try await Fixture(); defer { f.close() }; let model = try XCTUnwrap(f.makeEmail())
        XCTAssertTrue(f.begin(model)); let presentation = try await emailPresentation(f)
        f.makeCredentialHook = { f.makeCredentialHook = nil; f.roundTrip() }
        let submit = try submitPassword(presentation); await submit.value
        await eventually { !model.hasPhysicalFlight }
        XCTAssertEqual(f.credentialEmails.count, 1); XCTAssertEqual(f.sdkReauths, 0)
        XCTAssertNil(f.prompt.presentation); XCTAssertTrue(f.requests.isEmpty)
    }

    func testEmailUnsupportedProviderOrMissingSDKEmailDoesNotShowPasswordForm() async throws {
        for unsupported in [true, false] {
            let f = try await Fixture(); defer { f.close() }
            if unsupported { f.user?.supportsPassword = false } else { f.user?.email = nil }
            let model = try XCTUnwrap(f.makeEmail()); XCTAssertTrue(f.begin(model))
            await eventually { !model.hasPhysicalFlight }
            XCTAssertNil(f.prompt.presentation); XCTAssertTrue(f.credentialEmails.isEmpty)
            XCTAssertEqual(f.sdkReauths, 0); XCTAssertTrue(f.requests.isEmpty)
        }
    }

    func testEmailLedgerRequiresNewPromptAndOldDismissCannotCancelIt() async throws {
        let f = try await Fixture(); defer { f.close() }; let model = try XCTUnwrap(f.makeEmail())
        XCTAssertTrue(f.begin(model)); let first = try await emailPresentation(f)
        let initial = try submitPassword(first); await initial.value
        await eventually { model.status == .scopedCloudDataRemoved && !model.hasPhysicalFlight }
        f.now += 1_000; XCTAssertTrue(model.beginLedgerCleanup(userConfirmed: true))
        let second = try await emailPresentation(f); XCTAssertNotEqual(second.id, first.id)
        f.prompt.cancel(action: first.action)
        XCTAssertEqual(f.prompt.presentation?.id, second.id); XCTAssertTrue(model.hasPhysicalFlight)
        let child = try submitPassword(second, "NewLedger!"); await child.value
        await eventually { model.status == .ledgerDataRemoved && !model.hasPhysicalFlight }
        XCTAssertEqual(f.sdkReauths, 2); XCTAssertEqual(f.requests.count, 2); XCTAssertFalse(model.accountDeletionComplete)
    }

    private func applePresentation(_ f: Fixture) async throws -> ReaderAppleReauthenticationPrompt.Presentation {
        await eventually { f.applePrompt.presentation != nil }
        let presentation = try XCTUnwrap(f.applePrompt.presentation)
        f.appleFlows.append(presentation.flow)
        return presentation
    }
    private func appleReply(_ challenge: AppleSignInChallenge, subject: String = "apple-subject-A") -> AppleIdentityResponse {
        .init(identityToken: Data("local-signed-token".utf8), state: challenge.state, fullName: nil, userID: subject)
    }
    func testAppleMissingEndpointOrProviderIsInertWithoutPromptOrTransport() async throws {
        let f = try await Fixture(); defer { f.close() }
        XCTAssertNil(f.makeApple(configured: false)); XCTAssertEqual(f.captures, 0)
        f.user?.appleSubject = nil
        let model = try XCTUnwrap(f.makeApple()); XCTAssertTrue(f.begin(model))
        await eventually { !model.hasPhysicalFlight }
        XCTAssertNil(f.applePrompt.presentation); XCTAssertTrue(f.appleCredentials.isEmpty)
        XCTAssertEqual(f.sdkReauths, 0); XCTAssertTrue(f.requests.isEmpty)
    }
    func testAppleOriginalSubjectAndNonceReachHeldSDKWithoutLoginOrNewSession() async throws {
        let f = try await Fixture(); defer { f.close() }; let model = try XCTUnwrap(f.makeApple())
        let original = f.auth.state.contextTicket(), user = try XCTUnwrap(f.user)
        XCTAssertTrue(f.begin(model)); let p = try await applePresentation(f), challenge = try XCTUnwrap(p.flow.begin())
        // Provider metadata is immutable once the original SDK instance is captured.
        user.appleSubject = "replaced-metadata"
        let gate = f.hold(.reauthentication, expectation(description: "Original Apple SDK reauth"))
        let reply = Task { await p.flow.complete(ticketID: challenge.id, response: appleReply(challenge)) }
        await fulfillment(of: [gate.entered], timeout: 3)
        XCTAssertTrue(p.flow.isWorking); XCTAssertTrue(model.hasPhysicalFlight); XCTAssertTrue(f.requests.isEmpty)
        XCTAssertEqual(f.appleCredentials.first?.0, "local-signed-token"); XCTAssertEqual(f.appleCredentials.first?.1, challenge.rawNonce)
        XCTAssertNil(p.flow.authenticatedSession); XCTAssertEqual(f.capturedUsers.count, 1); XCTAssertTrue(f.capturedUsers.first === user)
        gate.release(); await reply.value
        await eventually { model.status == .scopedCloudDataRemoved && !model.hasPhysicalFlight }
        XCTAssertEqual(f.sdkReauths, 1); XCTAssertEqual(f.requests.count, 1)
        XCTAssertNil(p.flow.authenticatedSession); XCTAssertNil(p.flow.errorMessage); XCTAssertTrue(f.auth.state.isCurrent(original))
        XCTAssertNil(f.applePrompt.presentation); XCTAssertFalse(model.accountDeletionComplete)
    }
    func testAppleWrongProviderSubjectNeverConstructsFirebaseCredential() async throws {
        let f = try await Fixture(); defer { f.close() }; let model = try XCTUnwrap(f.makeApple())
        XCTAssertTrue(f.begin(model)); let p = try await applePresentation(f), challenge = try XCTUnwrap(p.flow.begin())
        await p.flow.complete(ticketID: challenge.id, response: appleReply(challenge, subject: "apple-subject-B"))
        await eventually { !model.hasPhysicalFlight }
        XCTAssertTrue(f.appleCredentials.isEmpty); XCTAssertEqual(f.sdkReauths, 0); XCTAssertTrue(f.requests.isEmpty)
        XCTAssertNil(p.flow.authenticatedSession)
    }
    func testAppleInvalidStateDrainsReturnedProviderWithoutCredentialOrHTTP() async throws {
        let f = try await Fixture(); defer { f.close() }; let model = try XCTUnwrap(f.makeApple())
        XCTAssertTrue(f.begin(model)); let p = try await applePresentation(f), challenge = try XCTUnwrap(p.flow.begin())
        await p.flow.complete(ticketID: challenge.id, response: .init(identityToken: Data("token".utf8), state: "foreign", fullName: nil, userID: "apple-subject-A"))
        await eventually { !model.hasPhysicalFlight }
        XCTAssertTrue(f.appleCredentials.isEmpty); XCTAssertEqual(f.sdkReauths, 0); XCTAssertTrue(f.requests.isEmpty)
    }
    func testAppleCancelBeforeButtonNeverStartsProviderAndReleasesOnlyUnstartedWait() async throws {
        let f = try await Fixture(); defer { f.close() }; let model = try XCTUnwrap(f.makeApple())
        XCTAssertTrue(f.begin(model)); let p = try await applePresentation(f)
        f.applePrompt.cancel(action: p.action); await eventually { !model.hasPhysicalFlight }
        XCTAssertNil(p.flow.begin()); XCTAssertEqual(f.sdkReauths, 0); XCTAssertTrue(f.appleCredentials.isEmpty)
    }
    func testAppleCancelWithProviderOpenKeepsPhysicalSlotUntilActualCallback() async throws {
        let f = try await Fixture(); defer { f.close() }; let model = try XCTUnwrap(f.makeApple())
        XCTAssertTrue(f.begin(model)); let p = try await applePresentation(f), challenge = try XCTUnwrap(p.flow.begin())
        f.applePrompt.cancel(action: p.action)
        for _ in 0..<10 { await Task.yield() }
        XCTAssertTrue(model.hasPhysicalFlight); XCTAssertTrue(p.flow.isWorking); XCTAssertNil(f.makeApple())
        p.flow.providerCancelled(ticketID: challenge.id); await eventually { !model.hasPhysicalFlight }
        XCTAssertFalse(p.flow.isWorking); XCTAssertTrue(f.appleCredentials.isEmpty); XCTAssertTrue(f.requests.isEmpty)
    }
    func testAppleCancellationDuringSDKKeepsPhysicalFlightUntilHeldUserReturns() async throws {
        let f = try await Fixture(); defer { f.close() }; let model = try XCTUnwrap(f.makeApple())
        XCTAssertTrue(f.begin(model)); let p = try await applePresentation(f), challenge = try XCTUnwrap(p.flow.begin())
        let gate = f.hold(.reauthentication, expectation(description: "Physical Apple reauth held"))
        let reply = Task { await p.flow.complete(ticketID: challenge.id, response: appleReply(challenge)) }
        await fulfillment(of: [gate.entered], timeout: 3); f.applePrompt.cancel(action: p.action)
        for _ in 0..<10 { await Task.yield() }
        XCTAssertTrue(model.hasPhysicalFlight); XCTAssertTrue(p.flow.isWorking); XCTAssertNil(f.makeApple())
        gate.release(); await reply.value; await eventually { !model.hasPhysicalFlight }
        XCTAssertNil(p.flow.authenticatedSession); XCTAssertTrue(f.requests.isEmpty); XCTAssertNil(p.flow.errorMessage)
    }
    func testAppleAccountRoundTripWhileProviderOpenRejectsLateMatchingSubject() async throws {
        let f = try await Fixture(); defer { f.close() }; let model = try XCTUnwrap(f.makeApple())
        XCTAssertTrue(f.begin(model)); let p = try await applePresentation(f), challenge = try XCTUnwrap(p.flow.begin())
        f.roundTrip(); XCTAssertTrue(model.hasPhysicalFlight)
        await p.flow.complete(ticketID: challenge.id, response: appleReply(challenge)); await eventually { !model.hasPhysicalFlight }
        XCTAssertTrue(f.appleCredentials.isEmpty); XCTAssertEqual(f.sdkReauths, 0); XCTAssertTrue(f.requests.isEmpty)
        XCTAssertNil(p.flow.authenticatedSession); XCTAssertNil(p.flow.errorMessage)
    }
    func testAppleSameUIDReplacementInstanceCannotBorrowOriginalProviderResult() async throws {
        let f = try await Fixture(); defer { f.close() }; let model = try XCTUnwrap(f.makeApple())
        XCTAssertTrue(f.begin(model)); let p = try await applePresentation(f), challenge = try XCTUnwrap(p.flow.begin())
        f.user = User("reader-A")
        await p.flow.complete(ticketID: challenge.id, response: appleReply(challenge)); await eventually { !model.hasPhysicalFlight }
        XCTAssertTrue(f.appleCredentials.isEmpty); XCTAssertEqual(f.sdkReauths, 0); XCTAssertTrue(f.requests.isEmpty)
    }
    func testAppleSDKRejectsWrongAccountDespiteLocalMatchingSubject() async throws {
        let f = try await Fixture(); defer { f.close() }; f.sdkError = NSError(domain: "LocalAuth", code: 17024)
        let model = try XCTUnwrap(f.makeApple()); let original = f.context
        XCTAssertTrue(f.begin(model)); let p = try await applePresentation(f), challenge = try XCTUnwrap(p.flow.begin())
        await p.flow.complete(ticketID: challenge.id, response: appleReply(challenge)); await eventually { !model.hasPhysicalFlight }
        XCTAssertEqual(f.sdkReauths, 1); XCTAssertTrue(f.requests.isEmpty); XCTAssertNil(p.flow.authenticatedSession)
        XCTAssertTrue(f.auth.state.isCurrent(original)); XCTAssertFalse(model.accountDeletionComplete)
        // The existing deletion coordinator owns provider-failure feedback and retry.
        XCTAssertEqual(model.status, .unavailable); XCTAssertTrue(model.canRetry)
        XCTAssertNotNil(model.message); XCTAssertNil(f.applePrompt.presentation)
        f.sdkError = nil; f.now += 1_000; XCTAssertTrue(model.retry(userConfirmed: true))
        let next = try await applePresentation(f), nextChallenge = try XCTUnwrap(next.flow.begin())
        XCTAssertNotEqual(next.action.actionID, p.action.actionID)
        XCTAssertNotEqual(nextChallenge.rawNonce, challenge.rawNonce)
        await next.flow.complete(ticketID: nextChallenge.id, response: appleReply(nextChallenge))
        await eventually { model.status == .scopedCloudDataRemoved && !model.hasPhysicalFlight }
        XCTAssertEqual(f.sdkReauths, 2); XCTAssertEqual(f.requests.count, 1)
    }
    func testAppleTimeoutCannotFreeOpenProviderOrAcceptLateSuccess() async throws {
        let f = try await Fixture(); defer { f.close() }; let model = try XCTUnwrap(f.makeApple())
        XCTAssertTrue(f.begin(model)); let p = try await applePresentation(f), challenge = try XCTUnwrap(p.flow.begin())
        try XCTUnwrap(f.deadlines.last)(); for _ in 0..<10 { await Task.yield() }
        XCTAssertTrue(model.hasPhysicalFlight); XCTAssertNil(f.makeApple())
        await p.flow.complete(ticketID: challenge.id, response: appleReply(challenge)); await eventually { !model.hasPhysicalFlight }
        XCTAssertTrue(f.requests.isEmpty); XCTAssertTrue(f.appleCredentials.isEmpty); XCTAssertEqual(f.sdkReauths, 0)
    }
    func testAppleCredentialConstructionReentryCannotContinueUnderNewAccountGeneration() async throws {
        let f = try await Fixture(); defer { f.close() }; let model = try XCTUnwrap(f.makeApple())
        XCTAssertTrue(f.begin(model)); let p = try await applePresentation(f), challenge = try XCTUnwrap(p.flow.begin())
        f.makeCredentialHook = { f.makeCredentialHook = nil; f.roundTrip() }
        await p.flow.complete(ticketID: challenge.id, response: appleReply(challenge)); await eventually { !model.hasPhysicalFlight }
        XCTAssertEqual(f.appleCredentials.count, 1); XCTAssertEqual(f.sdkReauths, 0); XCTAssertTrue(f.requests.isEmpty)
        XCTAssertNil(p.flow.authenticatedSession)
    }
    func testAppleLedgerRequiresNewChallengeAndOldPromptCancelCannotCancelNextAction() async throws {
        let f = try await Fixture(); defer { f.close() }; let model = try XCTUnwrap(f.makeApple())
        XCTAssertTrue(f.begin(model)); let first = try await applePresentation(f), a = try XCTUnwrap(first.flow.begin())
        await first.flow.complete(ticketID: a.id, response: appleReply(a))
        await eventually { model.status == .scopedCloudDataRemoved && !model.hasPhysicalFlight }
        f.now += 1_000; XCTAssertTrue(model.beginLedgerCleanup(userConfirmed: true))
        let second = try await applePresentation(f), b = try XCTUnwrap(second.flow.begin())
        XCTAssertNotEqual(a.rawNonce, b.rawNonce); XCTAssertNotEqual(a.state, b.state)
        f.applePrompt.cancel(action: first.action); XCTAssertTrue(model.hasPhysicalFlight)
        await first.flow.complete(ticketID: a.id, response: appleReply(a))
        XCTAssertTrue(second.flow.isWorking)
        await second.flow.complete(ticketID: b.id, response: appleReply(b))
        await eventually { model.status == .ledgerDataRemoved && !model.hasPhysicalFlight }
        XCTAssertEqual(f.sdkReauths, 2); XCTAssertEqual(f.requests.count, 2); XCTAssertFalse(model.accountDeletionComplete)
    }


    private func googlePresentation(_ f: Fixture) async throws -> ReaderGoogleReauthenticationPrompt.Presentation {
        await eventually { f.googlePrompt.presentation != nil }
        return try XCTUnwrap(f.googlePrompt.presentation)
    }
    @discardableResult private func startGoogle(_ f: Fixture, _ p: ReaderGoogleReauthenticationPrompt.Presentation) async -> Task<Void, Never> {
        let count = f.googleCallbacks.count
        let task = Task { await f.googlePrompt.start(action: p.action) }
        f.googleTasks.append(task)
        await eventually { f.googleCallbacks.count == count + 1 }
        return task
    }
    private func googleReply(_ f: Fixture, at index: Int? = nil, subject: String = "google-subject-A") {
        f.googleCallbacks[index ?? f.googleCallbacks.count - 1](.init(idToken: "local-google-id", accessToken: "local-google-access", userID: subject), nil)
    }
    func testGoogleMissingConfigurationOrProviderNeverOpensPrompt() async throws {
        let f = try await Fixture(); defer { f.close() }
        XCTAssertNil(f.makeGoogle(configured: false)); XCTAssertEqual(f.captures, 0)
        f.user?.googleSubject = nil
        let model = try XCTUnwrap(f.makeGoogle()); XCTAssertTrue(f.begin(model))
        await eventually { !model.hasPhysicalFlight }
        XCTAssertNil(f.googlePrompt.presentation); XCTAssertTrue(f.googleCallbacks.isEmpty)
        XCTAssertTrue(f.googleCredentials.isEmpty); XCTAssertEqual(f.sdkReauths, 0); XCTAssertTrue(f.requests.isEmpty)
    }
    func testGoogleOriginalSubjectAndTokensReachSameHeldSDKWithoutNewAppSession() async throws {
        let f = try await Fixture(); defer { f.close() }; let model = try XCTUnwrap(f.makeGoogle())
        let original = f.context, user = try XCTUnwrap(f.user)
        XCTAssertTrue(f.begin(model)); let p = try await googlePresentation(f)
        XCTAssertTrue(f.googleCallbacks.isEmpty)
        user.googleSubject = "later-metadata"
        let gate = f.hold(.reauthentication, expectation(description: "Original Google SDK held"))
        let task = await startGoogle(f, p); googleReply(f)
        await fulfillment(of: [gate.entered], timeout: 3)
        XCTAssertEqual(f.googleCredentials.first?.0, "local-google-id"); XCTAssertEqual(f.googleCredentials.first?.1, "local-google-access")
        XCTAssertTrue(f.capturedUsers.first === user); XCTAssertEqual(f.capturedUsers.count, 1)
        XCTAssertTrue(model.hasPhysicalFlight); XCTAssertTrue(f.requests.isEmpty)
        XCTAssertTrue(f.auth.state.isCurrent(original)); XCTAssertFalse(f.googleService.isSignedIn); XCTAssertNil(f.googleService.user)
        gate.release(); await task.value
        await eventually { model.status == .scopedCloudDataRemoved && !model.hasPhysicalFlight }
        XCTAssertNil(f.googlePrompt.presentation); XCTAssertEqual(f.sdkReauths, 1); XCTAssertEqual(f.requests.count, 1)
        XCTAssertTrue(f.auth.state.isCurrent(original)); XCTAssertFalse(model.accountDeletionComplete)
    }
    func testGoogleWrongSubjectNeverBuildsFirebaseCredential() async throws {
        let f = try await Fixture(); defer { f.close() }; let model = try XCTUnwrap(f.makeGoogle())
        XCTAssertTrue(f.begin(model)); let p = try await googlePresentation(f), task = await startGoogle(f, p)
        googleReply(f, subject: "google-subject-B"); await task.value
        await eventually { !model.hasPhysicalFlight }
        XCTAssertTrue(f.googleCredentials.isEmpty); XCTAssertEqual(f.sdkReauths, 0); XCTAssertTrue(f.requests.isEmpty)
        XCTAssertEqual(model.status, .unavailable); XCTAssertTrue(model.canRetry)
    }
    func testGoogleCancelBeforeTapDoesNotStartProvider() async throws {
        let f = try await Fixture(); defer { f.close() }; let model = try XCTUnwrap(f.makeGoogle())
        XCTAssertTrue(f.begin(model)); let p = try await googlePresentation(f)
        f.googlePrompt.cancel(action: p.action); await eventually { !model.hasPhysicalFlight }
        await f.googlePrompt.start(action: p.action)
        XCTAssertTrue(f.googleCallbacks.isEmpty); XCTAssertEqual(f.sdkReauths, 0)
    }
    func testGoogleCancelOpenProviderKeepsSharedAuthSlotUntilCallback() async throws {
        let f = try await Fixture(); defer { f.close() }; let model = try XCTUnwrap(f.makeGoogle())
        XCTAssertTrue(f.begin(model)); let p = try await googlePresentation(f), task = await startGoogle(f, p)
        f.googlePrompt.cancel(action: p.action)
        for _ in 0..<10 { await Task.yield() }
        XCTAssertTrue(model.hasPhysicalFlight); XCTAssertTrue(f.operations.isBusy); XCTAssertNil(f.makeGoogle())
        XCTAssertThrowsError(try f.operations.capture(.google))
        googleReply(f); await task.value; await eventually { !model.hasPhysicalFlight }
        XCTAssertFalse(f.operations.isBusy); XCTAssertTrue(f.googleCredentials.isEmpty); XCTAssertTrue(f.requests.isEmpty)
    }
    func testGoogleCancelDuringHeldSDKRetainsFlightAndRejectsItsLateSuccess() async throws {
        let f = try await Fixture(); defer { f.close() }; let model = try XCTUnwrap(f.makeGoogle())
        XCTAssertTrue(f.begin(model)); let p = try await googlePresentation(f)
        let gate = f.hold(.reauthentication, expectation(description: "Google SDK held for cancel"))
        let task = await startGoogle(f, p); googleReply(f)
        await fulfillment(of: [gate.entered], timeout: 3); f.googlePrompt.cancel(action: p.action)
        for _ in 0..<10 { await Task.yield() }
        XCTAssertTrue(model.hasPhysicalFlight); XCTAssertNil(f.makeGoogle()); XCTAssertTrue(f.operations.isBusy)
        gate.release(); await task.value; await eventually { !model.hasPhysicalFlight }
        XCTAssertTrue(f.requests.isEmpty); XCTAssertEqual(f.credentialCalls, 0)
    }
    func testGoogleAccountRoundTripRejectsLateMatchingSubject() async throws {
        let f = try await Fixture(); defer { f.close() }; let model = try XCTUnwrap(f.makeGoogle())
        XCTAssertTrue(f.begin(model)); let p = try await googlePresentation(f), task = await startGoogle(f, p)
        f.roundTrip(); XCTAssertTrue(model.hasPhysicalFlight)
        googleReply(f); await task.value; await eventually { !model.hasPhysicalFlight }
        XCTAssertEqual(f.sdkReauths, 0); XCTAssertTrue(f.googleCredentials.isEmpty); XCTAssertTrue(f.requests.isEmpty)
    }
    func testGoogleSameUIDReplacementCannotUseOriginalProviderResult() async throws {
        let f = try await Fixture(); defer { f.close() }; let model = try XCTUnwrap(f.makeGoogle())
        XCTAssertTrue(f.begin(model)); let p = try await googlePresentation(f), task = await startGoogle(f, p)
        f.user = User("reader-A")
        googleReply(f); await task.value; await eventually { !model.hasPhysicalFlight }
        XCTAssertEqual(f.sdkReauths, 0); XCTAssertTrue(f.googleCredentials.isEmpty); XCTAssertTrue(f.requests.isEmpty)
    }
    func testGoogleSDKAccountRejectionNeedsFreshExplicitActionAndProviderRetry() async throws {
        let f = try await Fixture(); defer { f.close() }; f.sdkError = NSError(domain: "LocalAuth", code: 17024)
        let model = try XCTUnwrap(f.makeGoogle()); let original = f.context
        XCTAssertTrue(f.begin(model)); let p = try await googlePresentation(f), task = await startGoogle(f, p)
        googleReply(f); await task.value; await eventually { !model.hasPhysicalFlight }
        XCTAssertEqual(model.status, .unavailable); XCTAssertTrue(model.canRetry); XCTAssertNotNil(model.message)
        XCTAssertNil(f.googlePrompt.presentation); XCTAssertTrue(f.requests.isEmpty); XCTAssertTrue(f.auth.state.isCurrent(original))
        f.sdkError = nil; f.now += 1_000; XCTAssertTrue(model.retry(userConfirmed: true))
        let next = try await googlePresentation(f), retry = await startGoogle(f, next)
        XCTAssertNotEqual(p.action.actionID, next.action.actionID)
        googleReply(f); await retry.value; await eventually { model.status == .scopedCloudDataRemoved && !model.hasPhysicalFlight }
        XCTAssertEqual(f.googleCallbacks.count, 2); XCTAssertEqual(f.sdkReauths, 2); XCTAssertEqual(f.requests.count, 1)
    }
    func testGoogleDeadlineCannotReleasePhysicalProviderOrAcceptLateCredential() async throws {
        let f = try await Fixture(); defer { f.close() }; let model = try XCTUnwrap(f.makeGoogle())
        XCTAssertTrue(f.begin(model)); let p = try await googlePresentation(f), task = await startGoogle(f, p)
        try XCTUnwrap(f.deadlines.last)(); for _ in 0..<10 { await Task.yield() }
        XCTAssertTrue(model.hasPhysicalFlight); XCTAssertNil(f.makeGoogle())
        googleReply(f); await task.value; await eventually { !model.hasPhysicalFlight }
        XCTAssertTrue(f.googleCredentials.isEmpty); XCTAssertEqual(f.sdkReauths, 0); XCTAssertTrue(f.requests.isEmpty)
    }
    func testGoogleCredentialConstructionReentryCannotExchangeInNewGeneration() async throws {
        let f = try await Fixture(); defer { f.close() }; let model = try XCTUnwrap(f.makeGoogle())
        XCTAssertTrue(f.begin(model)); let p = try await googlePresentation(f), task = await startGoogle(f, p)
        f.makeCredentialHook = { f.makeCredentialHook = nil; f.roundTrip() }
        googleReply(f); await task.value; await eventually { !model.hasPhysicalFlight }
        XCTAssertEqual(f.googleCredentials.count, 1); XCTAssertEqual(f.sdkReauths, 0); XCTAssertTrue(f.requests.isEmpty)
    }
    func testGoogleLedgerRequiresNewProviderAndOldPromptCannotCancelIt() async throws {
        let f = try await Fixture(); defer { f.close() }; let model = try XCTUnwrap(f.makeGoogle())
        XCTAssertTrue(f.begin(model)); let p = try await googlePresentation(f), first = await startGoogle(f, p)
        googleReply(f); await first.value; await eventually { model.status == .scopedCloudDataRemoved && !model.hasPhysicalFlight }
        f.now += 1_000; XCTAssertTrue(model.beginLedgerCleanup(userConfirmed: true))
        let next = try await googlePresentation(f), second = await startGoogle(f, next)
        XCTAssertNotEqual(p.action.actionID, next.action.actionID)
        f.googlePrompt.cancel(action: p.action); googleReply(f, at: 0)
        for _ in 0..<10 { await Task.yield() }
        XCTAssertTrue(model.hasPhysicalFlight); XCTAssertEqual(f.sdkReauths, 1)
        googleReply(f, at: 1); await second.value
        await eventually { model.status == .ledgerDataRemoved && !model.hasPhysicalFlight }
        XCTAssertEqual(f.sdkReauths, 2); XCTAssertEqual(f.requests.count, 2); XCTAssertFalse(model.accountDeletionComplete)
    }
}

/// A real serial-store adapter with one controllable physical write/readback.
/// It never contacts UserDefaults, KVS or any service.
private final class DeletionResumeMemory: @unchecked Sendable {
    private let lock = NSLock()
    private let gate = DispatchSemaphore(value: 0)
    private let entered: XCTestExpectation
    private var data: Data?
    private var holdWrite = false, holdReadback = false, readbackPending = false
    private enum Failure: Error { case waitExpired }
    init(entered: XCTestExpectation) { self.entered = entered }
    func holdNextWrite(readback: Bool) {
        lock.withLock { holdWrite = !readback; holdReadback = readback }
    }
    func release() { gate.signal() }
    private func wait() throws {
        entered.fulfill()
        guard gate.wait(timeout: .now() + 10) == .success else { throw Failure.waitExpired }
    }
    var storage: ReaderResumeStore.Storage {
        .init(read: { [self] in
            let held = lock.withLock { let held = readbackPending; readbackPending = false; return held }
            if held { try wait() }
            return lock.withLock { data }
        }, write: { [self] next in
            let held = lock.withLock { let held = holdWrite; holdWrite = false; return held }
            if held { try wait() }
            lock.withLock {
                data = next
                if holdReadback { readbackPending = true; holdReadback = false }
            }
        })
    }
}
