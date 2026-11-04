import FirebaseCore
import XCTest
@testable import Apropos

/// Actual Auth ingress -> HTTP wire decoder -> startup coordinator -> reader
/// publication. HTTP and provider waits are local; no positive Permit is forged.
@MainActor
final class AuthStartupTransportIntegrationTests: XCTestCase {
    private typealias Startup = ReaderStartupCoordinator
    private typealias Transport = ReaderStartupHTTPTransport
    private typealias Context = CanonicalSessionState.ContextTicket
    private enum Failure: Error { case malformedFixture }
    private enum Stage: String { case marker, credentials, membership, attestation, beforeAdmission, afterAdmission }

    @MainActor private final class Gate {
        let entered: XCTestExpectation
        private var continuation: CheckedContinuation<Void, Error>?
        init(_ entered: XCTestExpectation) { self.entered = entered }
        func wait() async throws {
            try await withCheckedThrowingContinuation { continuation in
                self.continuation = continuation; self.entered.fulfill()
            }
        }
        func release() {
            guard let continuation else { XCTFail("Expected a held physical operation"); return }
            self.continuation = nil; continuation.resume()
        }
        func close() { let held = continuation; continuation = nil; held?.resume(throwing: CancellationError()) }
    }
    @MainActor private final class Pending {
        let done: XCTestExpectation
        var task: Task<Void, Never>?
        var result: Result<Context, Error>?
        init(_ done: XCTestExpectation) { self.done = done }
    }
    private final class Flag: @unchecked Sendable {
        private let lock = NSLock()
        private var stored = false
        var value: Bool { lock.lock(); defer { lock.unlock() }; return stored }
        func set(_ value: Bool) { lock.lock(); stored = value; lock.unlock() }
    }

    @MainActor private final class Fixture {
        let sdk = ReaderSDKStartupState()
        let auth: AuthService
        let configuration: Transport.Configuration
        private let publication = CanonicalAccountPublication()
        var uid: String?
        var providerBound = true
        var time: Int64 = 10_000
        var requests: [URLRequest] = []
        var credentialContexts: [Context] = []
        var events: [String] = []
        var readerEffects: [String] = []
        var starts = 0, publicationAttempts = 0, profileRevocations = 0
        var attestationStatus = 200
        var publicationHook: (() -> Void)?
        var providerHook: (() -> Void)?
        var deadlines: [@MainActor () -> Void] = []
        var holds: [Stage: Gate] = [:]
        var allGates: [Gate] = []

        init() throws {
            auth = AuthService(startup: sdk)
            let startup = try Startup.Configuration(projectID: "local-startup", appID: "local-reader-app",
                installationID: UUID(), writerFenceRevision: String(repeating: "a", count: 64),
                migrationRevision: String(repeating: "b", count: 64))
            configuration = try Transport.Configuration(startup: startup,
                membershipURL: URL(string: "https://startup.example.invalid/membership")!,
                attestationURL: URL(string: "https://startup.example.invalid/attestation")!,
                deploymentEvidenceSHA256: String(repeating: "c", count: 64))
        }
        var context: Context { auth.bootstrapIdentity.contextTicket() }
        func observe(_ value: String?) {
            uid = value
            let session = value.map { ReaderAccountSession(uid: $0, email: "local@example.invalid", isEmailVerified: true) }
            _ = auth.observeIdentity(session, currentUserID: { [weak self] in self?.uid },
                revokeReader: { [weak self] current in self?.auth.state.suspend(stillPermitted: current) != nil },
                publishReader: { [weak self] current in
                    guard let self else { return nil }
                    self.publicationAttempts += 1; self.events.append("publish")
                    var result: Context?
                    let steps: [() -> Void] = ["reference", "profile", "favorites", "preferences", "FCM"].map { name in
                        { [weak self] in self?.readerEffects.append(name) }
                    }
                    let accepted = self.publication.performReaderTransition(expectedUserID: value,
                        currentUserID: { [weak self] in self?.uid }, revokeProfile: { [weak self] in
                            guard let self else { return false }
                            self.profileRevocations += 1; self.publicationHook?(); return true
                        }, revokePreferences: { true }, revocationsCurrent: { true }, dependentSteps: steps,
                        commitCanonical: { [weak self] in
                            result = self?.auth.state.adopt(session, stillPermitted: current); return result != nil
                        }, startLoads: { [weak self] in self?.readerEffects.append("loads") }, permission: current)
                    return accepted ? result : nil
                })
        }
        func hold(_ stage: Stage, _ expectation: XCTestExpectation) -> Gate {
            let gate = Gate(expectation); holds[stage] = gate; allGates.append(gate); return gate
        }
        private func pass(_ stage: Stage) async throws {
            events.append(stage.rawValue)
            if let gate = holds.removeValue(forKey: stage) { try await gate.wait() }
        }
        func start(configured: Bool = true, original: Context? = nil) async throws -> Context {
            let credentials: @MainActor (Context) async throws -> Transport.Credentials = { [self] context in
                self.credentialContexts.append(context)
                try await self.pass(.credentials)
                return .init(ownerUID: context.userID ?? "", projectID: self.configuration.startup.projectID,
                    appID: self.configuration.startup.appID, idToken: "local-id-token", appCheckToken: "local-app-check-token",
                    authValidUntilMs: 100_000, appCheckValidUntilMs: 90_000)
            }
            let execute: @MainActor (URLRequest) async throws -> (Data, HTTPURLResponse) = { [self] request in
                self.requests.append(request)
                guard let data = request.httpBody,
                      let echo = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let url = request.url else { throw Failure.malformedFixture }
                let isMember = url == self.configuration.membershipURL
                try await self.pass(isMember ? .membership : .attestation)
                let reply: [String: Any]
                if isMember {
                    guard let owner = echo["expectedUID"] as? String else { throw Failure.malformedFixture }
                    reply = ["schemaVersion": 1, "scope": "reader-membership-read-v1", "request": echo,
                        "membership": ["schemaVersion": 1, "ownerUID": owner, "epoch": 7, "state": "active"],
                        "validUntilMs": 30_000]
                } else {
                    reply = ["schemaVersion": 1, "scope": "reader-startup-attestation-v1", "request": echo,
                        "coverage": "all_persisted_writers_including_previous_accounts",
                        "deploymentEvidenceSHA256": self.configuration.deploymentEvidenceSHA256, "validUntilMs": 20_000]
                }
                guard let response = HTTPURLResponse(url: url, statusCode: isMember ? 200 : self.attestationStatus,
                    httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"]) else {
                    throw Failure.malformedFixture
                }
                return (try JSONSerialization.data(withJSONObject: reply), response)
            }
            let marker: @MainActor () async throws -> Startup.Marker? = { [self] in
                try await self.pass(.marker); return nil
            }
            let starter: @MainActor (Startup.Receipt, @escaping Startup.StartAdmission) async throws -> Void = { [self] _, admit in
                try await self.pass(.beforeAdmission)
                try admit(); self.starts += 1
                try await self.pass(.afterAdmission)
            }
            return try await auth.startReaderSession(context: original ?? context,
                configuration: configured ? configuration : nil, credentials: credentials, execute: execute,
                readMarker: marker, startSDK: starter, now: { [self] in self.time },
                schedule: { [self] callback in self.deadlines.append(callback); return {} },
                providerIsCurrent: { [self] in self.providerHook?(); return self.providerBound })
        }
        func close() { publicationHook = nil; providerHook = nil; allGates.forEach { $0.close() } }
    }

    override func setUp() { super.setUp(); XCTAssertNil(FirebaseApp.allApps) }
    override func tearDown() { XCTAssertNil(FirebaseApp.allApps); super.tearDown() }

    private func launch(_ fixture: Fixture, configured: Bool = true) -> Pending {
        let pending = Pending(expectation(description: "Actual Auth startup caller returned")), original = fixture.context
        pending.task = Task { @MainActor in
            do { pending.result = .success(try await fixture.start(configured: configured, original: original)) }
            catch { pending.result = .failure(error) }
            pending.done.fulfill()
        }
        return pending
    }
    private func failure(_ pending: Pending, _ expected: Startup.Failure? = nil) async {
        await fulfillment(of: [pending.done], timeout: 3)
        guard case .failure(let error) = pending.result else { return XCTFail("Startup must not release the reader") }
        if let expected { XCTAssertEqual(error as? Startup.Failure, expected) }
    }
    private func eventually(_ message: String, _ predicate: @escaping @MainActor () -> Bool) async {
        if predicate() { return }
        let flag = Flag()
        let check = NSPredicate { _, _ in Task { @MainActor in flag.set(predicate()) }; return flag.value }
        let expected = XCTNSPredicateExpectation(predicate: check, object: nil)
        await fulfillment(of: [expected], timeout: 3)
        XCTAssertTrue(predicate(), message)
    }
    private func assertClosed(_ fixture: Fixture, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertFalse(fixture.sdk.permitsReaderServices(identity: fixture.auth.bootstrapIdentity), file: file, line: line)
        XCTAssertEqual(fixture.auth.state.snapshot.context, .unresolved, file: file, line: line)
        XCTAssertTrue(fixture.readerEffects.isEmpty, file: file, line: line)
    }

    func testActualHTTPStartupKeepsReaderClosedUntilVerifiedStartThenReleasesExactlyOnce() async throws {
        let f = try Fixture(); defer { f.close() }; f.observe("A"); let original = f.context
        let gate = f.hold(.marker, expectation(description: "Local marker read held"))
        let pending = launch(f); await fulfillment(of: [gate.entered], timeout: 3)
        assertClosed(f); XCTAssertNil(f.auth.releaseReaderSession(context: original))
        XCTAssertTrue(f.requests.isEmpty); XCTAssertTrue(f.credentialContexts.isEmpty); XCTAssertEqual(f.starts, 0)
        gate.release(); await fulfillment(of: [pending.done], timeout: 3)
        guard case .success(let released) = pending.result else { return XCTFail("Actual wire startup should succeed") }
        XCTAssertTrue(f.auth.state.isCurrent(released)); XCTAssertEqual(f.auth.state.snapshot.context, .account("A"))
        XCTAssertEqual(f.requests.map(\.url), [f.configuration.membershipURL, f.configuration.attestationURL])
        XCTAssertEqual(f.credentialContexts, [original, original]); XCTAssertEqual(f.starts, 1)
        XCTAssertEqual(f.readerEffects, ["reference", "profile", "favorites", "preferences", "FCM", "loads"])
        XCTAssertEqual(f.events, ["marker", "credentials", "membership", "credentials", "attestation", "marker", "beforeAdmission", "afterAdmission", "publish"])
        XCTAssertNil(f.auth.releaseReaderSession(context: original)); XCTAssertEqual(f.publicationAttempts, 1)
        XCTAssertEqual(f.sdk.status, .started)
    }

    func testMissingConfigurationAndGuardedGuestNeverConsultCredentialsHTTPOrSDK() async throws {
        for guest in [false, true] {
            let f = try Fixture(); defer { f.close() }; f.observe(guest ? nil : "A")
            let pending = launch(f, configured: guest)
            await failure(pending, .unavailable); assertClosed(f)
            XCTAssertTrue(f.events.isEmpty); XCTAssertTrue(f.requests.isEmpty); XCTAssertTrue(f.credentialContexts.isEmpty)
            XCTAssertEqual(f.starts, 0); XCTAssertEqual(f.publicationAttempts, 0); XCTAssertEqual(f.sdk.status, .idle)
        }
    }

    func testHTTPAttestationFailureCannotReleaseAndOnlyExplicitFreshAttemptCanRetry() async throws {
        let f = try Fixture(); defer { f.close() }; f.observe("A"); f.attestationStatus = 503
        await failure(launch(f)); assertClosed(f)
        XCTAssertEqual(f.requests.count, 2); XCTAssertEqual(f.starts, 0); XCTAssertEqual(f.sdk.status, .idle)
        f.attestationStatus = 200
        let released = try await f.start()
        XCTAssertTrue(f.auth.state.isCurrent(released)); XCTAssertEqual(f.requests.count, 4)
        XCTAssertEqual(f.starts, 1); XCTAssertEqual(f.publicationAttempts, 1)
    }

    func testHeldCredentialsCannotSendForAnOldAccountGenerationAfterABA() async throws {
        let f = try Fixture(); defer { f.close() }; f.observe("A"); let original = f.context
        let gate = f.hold(.credentials, expectation(description: "Original credentials held"))
        let pending = launch(f); await fulfillment(of: [gate.entered], timeout: 3)
        f.observe("B"); f.observe("A"); await failure(pending, .stale)
        XCTAssertNotEqual(f.context, original); XCTAssertEqual(f.sdk.status, .preparing); assertClosed(f)
        gate.release(); await eventually("Original credentials physically returned") { f.sdk.status == .idle }
        XCTAssertTrue(f.requests.isEmpty); XCTAssertEqual(f.starts, 0); XCTAssertEqual(f.publicationAttempts, 0)
        XCTAssertNil(f.auth.releaseReaderSession(context: original)); assertClosed(f)
    }

    func testHeldAttestationCannotReleaseNewSameUIDSessionAfterABA() async throws {
        let f = try Fixture(); defer { f.close() }; f.observe("A")
        let gate = f.hold(.attestation, expectation(description: "Original HTTP attestation held"))
        let pending = launch(f); await fulfillment(of: [gate.entered], timeout: 3)
        XCTAssertEqual(f.requests.count, 2); XCTAssertEqual(f.starts, 0)
        f.observe("B"); f.observe("A"); await failure(pending, .stale)
        gate.release(); await eventually("Original HTTP physically returned") { f.sdk.status == .idle }
        assertClosed(f); XCTAssertEqual(f.starts, 0); XCTAssertEqual(f.publicationAttempts, 0)
    }

    func testActualUIDMismatchBeforeCanonicalCallbackCannotReleaseOrReviveOldHTTPResult() async throws {
        let f = try Fixture(); defer { f.close() }; f.observe("A"); let original = f.context
        let gate = f.hold(.membership, expectation(description: "Membership reply held"))
        let pending = launch(f); await fulfillment(of: [gate.entered], timeout: 3)
        f.uid = "B"; gate.release(); await failure(pending)
        f.uid = "A"
        XCTAssertEqual(f.context, original); XCTAssertEqual(f.requests.count, 1); XCTAssertEqual(f.starts, 0)
        XCTAssertNil(f.auth.releaseReaderSession(context: original)); assertClosed(f)
    }

    func testSameUIDProviderReplacementWhileStarterSuspendsNeverCrossesFinalAdmission() async throws {
        let f = try Fixture(); defer { f.close() }; f.observe("A")
        let gate = f.hold(.beforeAdmission, expectation(description: "Starter suspended before physical SDK reference"))
        let pending = launch(f); await fulfillment(of: [gate.entered], timeout: 3)
        f.providerBound = false; gate.release(); await failure(pending)
        XCTAssertEqual(f.uid, "A"); XCTAssertEqual(f.starts, 0); XCTAssertEqual(f.sdk.status, .uncertain)
        assertClosed(f); XCTAssertEqual(f.publicationAttempts, 0)
    }

    func testProviderHookChangingActualUIDCannotApproveThePriorOwnerEvenWhenItReturnsTrue() async throws {
        let f = try Fixture(); defer { f.close() }; f.observe("A")
        f.providerHook = { f.providerHook = nil; f.uid = "B" }
        await failure(launch(f), .stale)
        XCTAssertTrue(f.providerBound); XCTAssertEqual(f.context.userID, "A")
        XCTAssertTrue(f.credentialContexts.isEmpty); XCTAssertTrue(f.requests.isEmpty)
        XCTAssertEqual(f.starts, 0); XCTAssertEqual(f.sdk.status, .idle); assertClosed(f)
    }

    func testCancelledOrTimedOutCredentialWaitKeepsPhysicalReservationAndNeverSendsLateHTTP() async throws {
        for cancel in [false, true] {
            let f = try Fixture(); defer { f.close() }; f.observe("A")
            let gate = f.hold(.credentials, expectation(description: "Uncooperative credential callback held"))
            let pending = launch(f); await fulfillment(of: [gate.entered], timeout: 3)
            if cancel { pending.task?.cancel() } else { try XCTUnwrap(f.deadlines.first)() }
            await failure(pending, cancel ? .cancelled : .timedOut)
            XCTAssertEqual(f.sdk.status, .preparing); assertClosed(f)
            await failure(launch(f), .busy)
            XCTAssertEqual(f.credentialContexts.count, 1); XCTAssertTrue(f.requests.isEmpty)
            gate.release(); await eventually("Revoked credential wait physically released") { f.sdk.status == .idle }
            XCTAssertTrue(f.requests.isEmpty, "A late credential result must not start either authority request")
            XCTAssertEqual(f.starts, 0); XCTAssertEqual(f.publicationAttempts, 0); assertClosed(f)
        }
    }

    func testTimeoutOrCancellationAfterPhysicalSDKAdmissionNeverOpensReaderOnLateReturn() async throws {
        for cancel in [false, true] {
            let f = try Fixture(); defer { f.close() }; f.observe("A"); let original = f.context
            let gate = f.hold(.afterAdmission, expectation(description: "Physical starter return held"))
            let pending = launch(f); await fulfillment(of: [gate.entered], timeout: 3)
            XCTAssertEqual(f.starts, 1); XCTAssertEqual(f.sdk.status, .attempted)
            if cancel { pending.task?.cancel() } else { try XCTUnwrap(f.deadlines.first)() }
            await failure(pending, cancel ? .cancelled : .timedOut); assertClosed(f)
            XCTAssertNil(f.auth.releaseReaderSession(context: original))
            gate.release(); await eventually("Late physical start returns without a reader permit") { f.sdk.status == .started }
            XCTAssertNil(f.auth.releaseReaderSession(context: original)); assertClosed(f)
            XCTAssertEqual(f.publicationAttempts, 0); XCTAssertEqual(f.starts, 1)
        }
    }

    func testPublicationReentryCannotRunOldReaderEffectsEvenAfterVerifiedHTTPAndPhysicalStart() async throws {
        for change in ["provider", "actualUID", "generation"] {
            let f = try Fixture(); defer { f.close() }; f.observe("A")
            f.publicationHook = {
                f.publicationHook = nil
                if change == "generation" { f.observe("B"); f.observe("A") }
                else if change == "actualUID" { f.uid = "B" }
                else { f.providerBound = false }
            }
            await failure(launch(f))
            XCTAssertEqual(f.starts, 1); XCTAssertEqual(f.publicationAttempts, 1); XCTAssertEqual(f.profileRevocations, 1)
            assertClosed(f); XCTAssertEqual(f.sdk.status, .uncertain)
            XCTAssertNil(f.auth.releaseReaderSession(context: f.context))
        }
    }
}
