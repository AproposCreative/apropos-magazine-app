import FirebaseCore
import XCTest
@testable import Apropos

/// The existing provider factories and prompts run through a real cold startup
/// from local checkpoint files. All provider, held-user SDK and HTTP effects are
/// injected; no Firebase client, reader service or physical provider is started.
@MainActor
final class ReaderDeletionProviderResumeTests: XCTestCase {
    private typealias Model = ReaderAccountDeletionCoordinator
    private typealias Contract = ReaderAccountDeletionContract
    private typealias Bridge = ReaderAccountReauthentication<String>
    private enum Provider: CaseIterable { case email, apple, google }
    private enum Failure: Error { case malformedRequest, wrongPassword }
    @MainActor private final class User {
        let uid: String
        var email = "original.sdk@example.invalid"
        var appleSubject = "original-apple-subject", googleSubject = "original-google-subject"
        init(_ uid: String) { self.uid = uid }
    }
    @MainActor private final class Gate {
        var entered = false
        private var continuation: CheckedContinuation<Void, Never>?
        func wait() async { await withCheckedContinuation { continuation = $0; entered = true } }
        func release() { let old = continuation; continuation = nil; old?.resume() }
    }
    @MainActor private enum Input {
        case email(ReaderEmailReauthenticationPrompt.Presentation)
        case apple(ReaderAppleReauthenticationPrompt.Presentation, AppleSignInChallenge)
        case google(ReaderGoogleReauthenticationPrompt.Presentation, Task<Void, Never>, Int)
        var action: Model.ActionTicket {
            switch self { case .email(let p): return p.action; case .apple(let p, _): return p.action; case .google(let p, _, _): return p.action }
        }
    }

    @MainActor private final class Fixture {
        let root: URL, configuration: ReaderDeletionHTTPTransport.Configuration
        let recovery: ReaderTransitionRecovery, startup: ReaderSDKStartupState, auth: AuthService
        let wrongIdentity = CanonicalSessionState()
        var user: User? = User("reader-A")
        var now: Int64 = 1_800_000_000_123
        var sdkReauths = 0, credentialReads = 0, readerSteps = 0, readerPublications = 0, feedStarts = 0
        var capturedUsers: [User] = [], requests: [URLRequest] = [], models: [Model] = []
        var proofs: [Model.ReauthenticationResult] = [], credentialPairs: [(String, String)] = []
        var sdkError: Error?, sdkGate: Gate?, allGates: [Gate] = []
        var tasks: [Task<Void, Never>] = [], appleFlows: [AppleAccountFlowModel] = []
        var googleCallbacks: [@Sendable (GoogleSignInService.ReauthenticationIdentity?, Error?) -> Void] = []
        lazy var operations = AuthOperationCoordinator(canonical: auth.state,
            actualUserID: { [unowned self] in user?.uid }, reauthenticationIdentity: auth.bootstrapIdentity)
        lazy var emailPrompt = ReaderEmailReauthenticationPrompt(canonical: auth.bootstrapIdentity)
        lazy var applePrompt = ReaderAppleReauthenticationPrompt(canonical: auth.bootstrapIdentity)
        lazy var googleService = GoogleSignInService(reauthenticationProvider: { [unowned self] permitted, callback in
            guard permitted() else { throw CancellationError() }; googleCallbacks.append(callback)
        })
        lazy var googlePrompt = ReaderGoogleReauthenticationPrompt(canonical: auth.bootstrapIdentity, service: googleService)
        lazy var wrongEmail = ReaderEmailReauthenticationPrompt(canonical: wrongIdentity)
        lazy var wrongApple = ReaderAppleReauthenticationPrompt(canonical: wrongIdentity)
        lazy var wrongGoogle = ReaderGoogleReauthenticationPrompt(canonical: wrongIdentity, service: googleService)
        lazy var vm = ArticleViewModel(startup: startup, identity: auth.bootstrapIdentity,
            actualUserID: { [unowned self] in user?.uid }, readEffects: .init())
        lazy var delegate = AppDelegate(startup: startup, identity: auth.bootstrapIdentity,
            actualUserID: { [unowned self] in user?.uid })
        lazy var bridge = Bridge(canonical: auth.bootstrapIdentity, operations: operations, captureUser: { [unowned self] in
            guard let original = user else { return nil }; capturedUsers.append(original)
            return .init(uid: original.uid, isCurrent: { [unowned self] in user === original },
                reauthenticate: { [unowned self] _, permitted in
                    guard permitted() else { throw CancellationError() }
                    sdkReauths += 1
                    if let held = sdkGate { sdkGate = nil; await held.wait() }
                    guard permitted() else { throw CancellationError() }
                    if let sdkError { throw sdkError }
                    return .init(uid: original.uid, authTimeMs: (now / 1_000) * 1_000)
                }, deletionCredentials: { [unowned self] proof, _ in
                    credentialReads += 1; proofs.append(proof)
                    return .init(ownerUID: original.uid, projectID: configuration.projectID, appID: configuration.appID,
                        idToken: "local.id." + proof.action.actionID.uuidString,
                        appCheckToken: "local.app." + proof.action.actionID.uuidString, authTimeMs: proof.authTimeMs,
                        authValidUntilMs: now + 60_000, appCheckValidUntilMs: now + 60_000)
                }, email: original.email, supportsPassword: true, appleSubject: original.appleSubject, googleSubject: original.googleSubject)
        }, nowMilliseconds: { [unowned self] in now })

        init() throws {
            root = FileManager.default.temporaryDirectory.appendingPathComponent("provider-resume-" + UUID().uuidString)
            configuration = try .init(projectID: "local-deletion", appID: "1:123456789:ios:abcdef123456",
                endpointURL: try XCTUnwrap(URL(string: "https://deletion.example.invalid/reader")))
            recovery = ReaderTransitionRecovery(store: .init(rootDirectory: root))
            startup = ReaderSDKStartupState(legacyRecovery: recovery); auth = AuthService(startup: startup)
        }
        var context: CanonicalSessionState.ContextTicket { auth.bootstrapIdentity.contextTicket() }
        var parent: Contract.Request { get throws { try .init(expectedUID: "reader-A", membershipEpoch: 7) } }
        var checkpointURL: URL { root.appendingPathComponent("reader-deletion-v1.json") }
        var markerURL: URL { root.appendingPathComponent("reader-transition-v1.json") }
        func seedAndLaunch() async throws {
            // A previous process wrote these exact records. The actual cold
            // composition below receives no in-memory proof from that instance.
            let previous = ReaderTransitionRecovery(store: .init(rootDirectory: root))
            try await previous.bootstrap()
            _ = try await previous.seal(binding: .init(ownerUID: "reader-A", epoch: 7))
            _ = try await previous.recordDeletion(request: parent, phase: .parent,
                configurationDigest: ReaderTransitionRecoveryStore.deletionConfigurationDigest(
                    projectID: configuration.projectID, appID: configuration.appID, endpoint: configuration.endpointURL))
            wrongIdentity.adopt(.init(uid: "reader-A", email: "local@example.invalid", isEmailVerified: true))
            vm.start(readerSteps: [{ [unowned self] _ in feedStarts += 1 }])
            let launch = delegate.runAccountStartup(authOnly: {}, readerSteps: [{ [unowned self] in readerSteps += 1 }],
                observeAuth: { [unowned self] in observe("reader-A") },
                releaseReader: { [unowned self] in _ = auth.resumeReaderAfterLocalRecovery() })
            if let launch { tasks.append(launch); await launch.value }
        }
        func observe(_ uid: String?) {
            if user?.uid != uid { user = uid.map { User($0) } }
            let session = uid.map { ReaderAccountSession(uid: $0, email: "canonical@example.invalid", isEmailVerified: true) }
            _ = auth.observeIdentity(session, currentUserID: { [unowned self] in user?.uid },
                revokeReader: { [unowned self] permitted in auth.state.suspend(stillPermitted: permitted) != nil },
                publishReader: { [unowned self] permitted in
                    guard let accepted = auth.state.adopt(session, stillPermitted: permitted) else { return nil }
                    readerPublications += 1; return accepted
                })
        }
        func make(_ provider: Provider, wrongPrompt: Bool = false) -> Model? {
            let create: @MainActor (String, String) -> String = { [unowned self] first, second in
                credentialPairs.append((first, second)); return "injected-provider-credential"
            }
            let execute: @MainActor (URLRequest) async throws -> (Data, HTTPURLResponse) = { [unowned self] request in
                requests.append(request); return try response(request)
            }
            let clock: @MainActor () -> Int64 = { [unowned self] in now }
            let model: Model?
            switch provider {
            case .email:
                model = auth.makeEmailReaderAccountDeletion(configuration: configuration, reauthentication: bridge,
                    prompt: wrongPrompt ? wrongEmail : emailPrompt, makeCredential: create, execute: execute, now: clock,
                    scheduleTimeout: { _, _ in {} }, resumingAfterRestart: true)
            case .apple:
                model = auth.makeAppleReaderAccountDeletion(configuration: configuration, reauthentication: bridge,
                    prompt: wrongPrompt ? wrongApple : applePrompt, makeCredential: create, execute: execute, now: clock,
                    scheduleTimeout: { _, _ in {} }, resumingAfterRestart: true)
            case .google:
                model = auth.makeGoogleReaderAccountDeletion(configuration: configuration, reauthentication: bridge,
                    prompt: wrongPrompt ? wrongGoogle : googlePrompt, makeCredential: create, execute: execute, now: clock,
                    scheduleTimeout: { _, _ in {} }, resumingAfterRestart: true)
            }
            if let model { models.append(model) }; return model
        }
        func resume(_ model: Model, confirmed: Bool = true) -> Bool { model.beginResumption(context: context, userConfirmed: confirmed) }
        func holdSDK() -> Gate { let gate = Gate(); sdkGate = gate; allGates.append(gate); return gate }
        func hasPrompt(_ provider: Provider) -> Bool {
            switch provider { case .email: return emailPrompt.presentation != nil; case .apple: return applePrompt.presentation != nil; case .google: return googlePrompt.presentation != nil }
        }
        func dismiss(_ input: Input) {
            switch input { case .email(let p): emailPrompt.cancel(action: p.action)
            case .apple(let p, _): applePrompt.cancel(action: p.action)
            case .google(let p, _, _): googlePrompt.cancel(action: p.action) }
        }
        func providerCancelled(_ input: Input) {
            switch input { case .email: break
            case .apple(let p, let challenge): p.flow.providerCancelled(ticketID: challenge.id)
            case .google(_, _, let index): googleCallbacks[index](nil, CancellationError()) }
        }
        func response(_ request: URLRequest) throws -> (Data, HTTPURLResponse) {
            guard let data = request.httpBody, let body = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let uid = body["expectedUID"] as? String, let epoch = body["membershipEpoch"] as? Int64,
                  let url = request.url else { throw Failure.malformedRequest }
            let original = try Contract.Request(expectedUID: uid, membershipEpoch: epoch)
            let ledger = body["scope"] as? String == Contract.ledgerScope
            let requestID: String
            if ledger {
                requestID = try Contract.LedgerRequest(expectedUID: uid, membershipEpoch: epoch,
                    parentRequestID: try XCTUnwrap(body["parentRequestID"] as? String)).requestID
            } else { requestID = original.requestID }
            var reply: [String: Any] = ["requestID": requestID, "scope": ledger ? Contract.ledgerScope : Contract.scope,
                "status": ledger ? "ledgerDataRemoved" : "scopedCloudDataRemoved", "accountDeletionComplete": false,
                "unresolved": ledger ? Contract.ledgerUnresolved : Contract.unresolved]
            if ledger {
                reply["parentRequestID"] = original.requestID; reply["removedReceiptDocuments"] = 2; reply["removedRevisionDocuments"] = 1
            } else { reply["removedFavoriteDocuments"] = 3 }
            return (try JSONSerialization.data(withJSONObject: reply), try XCTUnwrap(HTTPURLResponse(url: url,
                statusCode: 200, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"])))
        }
        func close() async {
            emailPrompt.cancel(); applePrompt.cancel(); googlePrompt.cancel()
            models.forEach { $0.cancel() }; allGates.forEach { $0.release() }
            for flow in appleFlows { if let id = flow.activeTicketID { flow.providerCancelled(ticketID: id) } }
            googleCallbacks.forEach { $0(nil, CancellationError()) }
            for task in tasks { task.cancel(); await task.value }
            for _ in 0..<2_000 {
                if models.allSatisfy({ !$0.hasPhysicalFlight }) && !recovery.isBusy { break }
                try? await Task.sleep(nanoseconds: 1_000_000)
            }
            try? FileManager.default.removeItem(at: root)
        }
    }

    override func setUp() { super.setUp(); XCTAssertNil(FirebaseApp.allApps) }
    override func tearDown() { XCTAssertNil(FirebaseApp.allApps); super.tearDown() }
    private func fixture() async throws -> Fixture {
        let value = try Fixture(); addTeardownBlock { @MainActor in await value.close() }
        try await value.seedAndLaunch(); assertReaderClosed(value); return value
    }
    private func eventually(_ predicate: () -> Bool, file: StaticString = #filePath, line: UInt = #line) async {
        for _ in 0..<2_000 { if predicate() { return }; try? await Task.sleep(nanoseconds: 1_000_000) }
        XCTFail("Actual provider composition did not reach its expected stage", file: file, line: line)
    }
    private func assertReaderClosed(_ f: Fixture, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(f.auth.state.snapshot.context, .unresolved, file: file, line: line)
        XCTAssertEqual(f.readerSteps, 0, file: file, line: line); XCTAssertEqual(f.readerPublications, 0, file: file, line: line)
        XCTAssertEqual(f.feedStarts, 0, file: file, line: line); XCTAssertFalse(f.recovery.admission.isAllowed, file: file, line: line)
        XCTAssertFalse(f.startup.permitsReaderServices(identity: f.auth.bootstrapIdentity), file: file, line: line)
        XCTAssertNil(FavoritesRuntime.existingJournalForTransition(context: f.auth.state.contextTicket()), file: file, line: line)
    }
    private func open(_ provider: Provider, in f: Fixture) async throws -> Input {
        await eventually { f.hasPrompt(provider) }
        switch provider {
        case .email: return .email(try XCTUnwrap(f.emailPrompt.presentation))
        case .apple:
            let p = try XCTUnwrap(f.applePrompt.presentation), challenge = try XCTUnwrap(p.flow.begin())
            f.appleFlows.append(p.flow); return .apple(p, challenge)
        case .google:
            let p = try XCTUnwrap(f.googlePrompt.presentation), index = f.googleCallbacks.count
            let task = Task { await f.googlePrompt.start(action: p.action) }; f.tasks.append(task)
            await eventually { f.googleCallbacks.count == index + 1 }
            return .google(p, task, index)
        }
    }
    private func respond(_ input: Input, in f: Fixture, password: String = "LocalFresh!", subject: String? = nil) throws -> Task<Void, Never> {
        let task: Task<Void, Never>
        switch input {
        case .email(let p):
            p.form.form.password = password
            let submission = try XCTUnwrap(p.form.captureSubmission())
            task = Task { await p.form.submit(submission) }
        case .apple(let p, let challenge):
            task = Task { await p.flow.complete(ticketID: challenge.id, response: .init(identityToken: Data("local-id-token".utf8),
                state: challenge.state, fullName: nil, userID: subject ?? "original-apple-subject")) }
        case .google(_, let pending, let index):
            f.googleCallbacks[index](.init(idToken: "local-id-token", accessToken: "local-access-token",
                userID: subject ?? "original-google-subject"), nil)
            task = pending
        }
        f.tasks.append(task); return task
    }
    private func completeParentAndLedger(_ provider: Provider) async throws {
        let f = try await fixture(), model = try XCTUnwrap(f.make(provider))
        let marker = try Data(contentsOf: f.markerURL), original = try XCTUnwrap(f.recovery.deletionCheckpoint)
        XCTAssertFalse(f.resume(model, confirmed: false)); XCTAssertFalse(model.beginLedgerCleanup(userConfirmed: true))
        XCTAssertFalse(f.hasPrompt(provider)); XCTAssertTrue(f.requests.isEmpty); XCTAssertEqual(f.sdkReauths, 0)
        XCTAssertTrue(f.resume(model)); let first = try await open(provider, in: f)
        let firstTask = try respond(first, in: f); await firstTask.value
        await eventually { model.canBeginLedgerCleanup }
        XCTAssertEqual(first.action.context, f.context); XCTAssertEqual(first.action.request, original.request)
        XCTAssertEqual(model.receipt?.requestID, original.request.requestID); XCTAssertNil(model.ledgerReceipt)
        XCTAssertFalse(model.beginLedgerCleanup(userConfirmed: false)); XCTAssertEqual(f.requests.count, 1)
        f.now += 5_000; XCTAssertTrue(model.beginLedgerCleanup(userConfirmed: true))
        let second = try await open(provider, in: f)
        XCTAssertNotEqual(first.action.actionID, second.action.actionID)
        XCTAssertEqual(second.action.phase, .mutationLedger); XCTAssertEqual(second.action.request, original.request)
        f.dismiss(first); XCTAssertTrue(model.hasPhysicalFlight); XCTAssertTrue(f.hasPrompt(provider))
        if case .apple(_, let a) = first, case .apple(_, let b) = second {
            XCTAssertNotEqual(a.rawNonce, b.rawNonce); XCTAssertNotEqual(a.state, b.state)
        }
        let secondTask = try respond(second, in: f); await secondTask.value
        await eventually { model.status == .ledgerDataRemoved && !model.hasPhysicalFlight }
        XCTAssertEqual(f.requests.count, 2); XCTAssertEqual(f.sdkReauths, 2); XCTAssertEqual(f.credentialReads, 2)
        XCTAssertEqual(f.proofs.map(\.action.phase), [.cloudSlice, .mutationLedger])
        XCTAssertEqual(f.recovery.deletionCheckpoint?.phase, .ledger)
        XCTAssertEqual(f.recovery.deletionCheckpoint?.request, original.request)
        XCTAssertEqual(try Data(contentsOf: f.markerURL), marker)
        XCTAssertFalse(model.accountDeletionComplete); assertReaderClosed(f)
        switch second { case .email(let p): XCTAssertNil(p.form.authenticatedSession); XCTAssertTrue(p.form.form.password.isEmpty)
        case .apple(let p, _): XCTAssertNil(p.flow.authenticatedSession)
        case .google: XCTAssertFalse(f.googleService.isSignedIn); XCTAssertNil(f.googleService.user) }
    }

    func testEmailColdResumeUsesFreshParentThenSeparatelyConfirmedLedger() async throws { try await completeParentAndLedger(.email) }
    func testAppleColdResumeUsesFreshChallengeForParentAndSeparatelyConfirmedLedger() async throws { try await completeParentAndLedger(.apple) }
    func testGoogleColdResumeUsesFreshProviderForParentAndSeparatelyConfirmedLedger() async throws { try await completeParentAndLedger(.google) }

    func testEmailWrongPasswordClearsDraftAndSameCoordinatorRetryCreatesFreshAction() async throws {
        let f = try await fixture(), model = try XCTUnwrap(f.make(.email)); f.sdkError = Failure.wrongPassword
        XCTAssertTrue(f.resume(model)); let first = try await open(.email, in: f)
        let failed = try respond(first, in: f, password: "WrongLocal!"); await failed.value
        await eventually { model.canRetry }
        guard case .email(let previous) = first else { return XCTFail("Expected email form") }
        XCTAssertNotNil(previous.form.errorMessage); XCTAssertTrue(previous.form.form.password.isEmpty)
        XCTAssertNil(previous.form.authenticatedSession); XCTAssertTrue(f.requests.isEmpty)
        f.sdkError = nil; f.now += 5_000; f.emailPrompt.retry(action: first.action)
        await eventually { f.emailPrompt.presentation?.id != nil && f.emailPrompt.presentation?.id != first.action.actionID }
        let second = try await open(.email, in: f)
        guard case .email(let fresh) = second else { return XCTFail("Expected email form") }
        XCTAssertTrue(fresh.form.form.password.isEmpty); XCTAssertNotEqual(first.action, second.action)
        let retry = try respond(second, in: f, password: "FreshLocal!"); await retry.value
        await eventually { model.canBeginLedgerCleanup }
        XCTAssertEqual(f.sdkReauths, 2); XCTAssertEqual(f.credentialPairs.map { $0.1 }, ["WrongLocal!", "FreshLocal!"])
        XCTAssertEqual(f.requests.count, 1); assertReaderClosed(f)
    }

    func testEmailPromptUsesOriginalHeldSDKEmailAndCannotPublishReaderSession() async throws {
        let f = try await fixture(), originalUser = try XCTUnwrap(f.user), model = try XCTUnwrap(f.make(.email))
        XCTAssertTrue(f.resume(model)); let input = try await open(.email, in: f)
        guard case .email(let p) = input else { return XCTFail("Expected email form") }
        originalUser.email = "changed-metadata@example.invalid"; p.form.form.email = "edited@example.invalid"
        let gate = f.holdSDK(), submit = try respond(input, in: f)
        await eventually { gate.entered }
        XCTAssertEqual(p.email, "original.sdk@example.invalid")
        XCTAssertEqual(f.credentialPairs.first?.0, "original.sdk@example.invalid")
        XCTAssertTrue(f.capturedUsers.first === originalUser); XCTAssertTrue(p.form.isWorking)
        XCTAssertTrue(p.form.form.password.isEmpty); XCTAssertTrue(f.requests.isEmpty); assertReaderClosed(f)
        gate.release(); await submit.value; await eventually { model.canBeginLedgerCleanup }
        XCTAssertNil(p.form.authenticatedSession); assertReaderClosed(f)
    }

    func testEachProviderRejectsPromptBoundToDifferentCanonicalModelEvenForSameUID() async throws {
        for provider in Provider.allCases {
            let f = try await fixture(), model = try XCTUnwrap(f.make(provider, wrongPrompt: true))
            XCTAssertEqual(f.wrongIdentity.snapshot.session?.uid, f.auth.bootstrapIdentity.snapshot.session?.uid)
            XCTAssertNotEqual(f.wrongIdentity.contextTicket(), f.context)
            XCTAssertTrue(f.resume(model)); await eventually { !model.hasPhysicalFlight }
            XCTAssertNil(f.wrongEmail.presentation); XCTAssertNil(f.wrongApple.presentation); XCTAssertNil(f.wrongGoogle.presentation)
            XCTAssertEqual(f.sdkReauths, 0); XCTAssertTrue(f.credentialPairs.isEmpty); XCTAssertTrue(f.requests.isEmpty)
            XCTAssertTrue(f.googleCallbacks.isEmpty); assertReaderClosed(f)
        }
    }

    func testEmailDraftCancellationDoesNotRequestCredentialAndKeepsRestartSeal() async throws {
        let f = try await fixture(), model = try XCTUnwrap(f.make(.email))
        XCTAssertTrue(f.resume(model)); let input = try await open(.email, in: f)
        guard case .email(let p) = input else { return XCTFail("Expected email form") }
        p.form.form.password = "UnsentLocal!"; f.dismiss(input)
        await eventually { !model.hasPhysicalFlight && !f.operations.isBusy }
        XCTAssertTrue(p.form.form.password.isEmpty); XCTAssertNil(p.form.captureSubmission())
        XCTAssertTrue(f.credentialPairs.isEmpty); XCTAssertEqual(f.sdkReauths, 0); XCTAssertTrue(f.requests.isEmpty)
        XCTAssertFalse(model.abortBeforeSubmission()); assertReaderClosed(f)
    }

    func testAppleAndGoogleProviderCancellationRetainsSharedSlotUntilActualProviderReturn() async throws {
        for provider in [Provider.apple, .google] {
            let f = try await fixture(), model = try XCTUnwrap(f.make(provider))
            XCTAssertTrue(f.resume(model)); let input = try await open(provider, in: f)
            f.dismiss(input)
            XCTAssertTrue(model.hasPhysicalFlight); XCTAssertTrue(f.operations.isBusy); XCTAssertNil(f.make(provider))
            XCTAssertThrowsError(try f.operations.capture(.emailSignIn))
            f.providerCancelled(input); await eventually { !model.hasPhysicalFlight && !f.operations.isBusy }
            XCTAssertEqual(f.sdkReauths, 0); XCTAssertTrue(f.requests.isEmpty); assertReaderClosed(f)
        }
    }

    func testEachProviderCancellationDuringSDKRetainsPhysicalSlotAndRejectsLateSuccess() async throws {
        for provider in Provider.allCases {
            let f = try await fixture(), model = try XCTUnwrap(f.make(provider))
            XCTAssertTrue(f.resume(model)); let input = try await open(provider, in: f), gate = f.holdSDK()
            let submit = try respond(input, in: f); await eventually { gate.entered }
            f.dismiss(input)
            XCTAssertTrue(model.hasPhysicalFlight); XCTAssertTrue(f.operations.isBusy); XCTAssertNil(f.make(provider))
            XCTAssertThrowsError(try f.operations.capture(.google)); XCTAssertTrue(f.requests.isEmpty)
            gate.release(); await submit.value; await eventually { !model.hasPhysicalFlight && !f.operations.isBusy }
            XCTAssertEqual(f.credentialReads, 0); XCTAssertNil(model.receipt); assertReaderClosed(f)
        }
    }

    func testEachProviderRejectsAccountRoundTripWhileOriginalPresentationIsWaiting() async throws {
        for provider in Provider.allCases {
            let f = try await fixture(), model = try XCTUnwrap(f.make(provider))
            XCTAssertTrue(f.resume(model)); let input = try await open(provider, in: f), original = f.context
            if case .email(let p) = input { p.form.form.password = "OldDraft!" }
            f.observe("reader-B"); f.observe("reader-A"); XCTAssertNotEqual(original, f.context)
            switch input {
            case .email(let p):
                XCTAssertTrue(p.form.form.password.isEmpty); XCTAssertNil(p.form.captureSubmission())
            case .apple, .google:
                XCTAssertTrue(model.hasPhysicalFlight)
                let late = try respond(input, in: f); await late.value
            }
            await eventually { !model.hasPhysicalFlight }
            XCTAssertEqual(f.sdkReauths, 0); XCTAssertTrue(f.credentialPairs.isEmpty); XCTAssertTrue(f.requests.isEmpty)
            assertReaderClosed(f)
        }
    }

    func testEachProviderRejectsReplacementSDKObjectWithSameUIDBeforeCredentialDelivery() async throws {
        for provider in Provider.allCases {
            let f = try await fixture(), model = try XCTUnwrap(f.make(provider))
            XCTAssertTrue(f.resume(model)); let input = try await open(provider, in: f), original = f.context
            f.user = User("reader-A")
            switch input {
            case .email(let p): p.form.form.password = "OldInstance!"; XCTAssertNil(p.form.captureSubmission())
            case .apple, .google: let late = try respond(input, in: f); await late.value
            }
            await eventually { !model.hasPhysicalFlight }
            XCTAssertEqual(original, f.context); XCTAssertEqual(f.sdkReauths, 0)
            XCTAssertTrue(f.requests.isEmpty); XCTAssertTrue(f.credentialPairs.isEmpty); assertReaderClosed(f)
        }
    }

    func testAppleAndGoogleRejectDifferentProviderSubjectWithoutUsingCloudRequest() async throws {
        for provider in [Provider.apple, .google] {
            let f = try await fixture(), model = try XCTUnwrap(f.make(provider))
            XCTAssertTrue(f.resume(model)); let input = try await open(provider, in: f)
            let rejected = try respond(input, in: f, subject: "different-provider-subject"); await rejected.value
            await eventually { model.canRetry }
            XCTAssertEqual(f.sdkReauths, 0); XCTAssertTrue(f.credentialPairs.isEmpty); XCTAssertTrue(f.requests.isEmpty)
            XCTAssertFalse(model.accountDeletionComplete); assertReaderClosed(f)
        }
    }
}
