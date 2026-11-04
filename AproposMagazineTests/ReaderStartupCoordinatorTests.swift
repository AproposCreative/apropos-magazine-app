import Foundation
import XCTest
@testable import Apropos

/// This exercises the real startup coordinator with controlled physical awaits.
/// No Firebase, AuthService, SDK factory, network or application singleton is used.
@MainActor
final class ReaderStartupCoordinatorTests: XCTestCase {
    private typealias Coordinator = ReaderStartupCoordinator
    private typealias SDKState = ReaderSDKStartupState
    private typealias Contract = ReaderAuthoritativeReadContract
    private typealias Marker = ReaderTransitionRecoveryStore.Marker
    private enum Injected: Error { case marker, membership, verifier, starter }

    @MainActor private final class Gate<Value> {
        let entered: XCTestExpectation
        private var continuation: CheckedContinuation<Value, Error>?
        init(_ entered: XCTestExpectation) { self.entered = entered }
        func wait() async throws -> Value {
            try await withCheckedThrowingContinuation { continuation in
                self.continuation = continuation
                self.entered.fulfill()
            }
        }
        func resolve(_ result: Result<Value, Error>) {
            guard let continuation else { return XCTFail("Gate was not physically entered") }
            self.continuation = nil
            continuation.resume(with: result)
        }
    }
    @MainActor private final class Pending {
        let done: XCTestExpectation
        var task: Task<Void, Never>?
        var result: Result<Coordinator.Receipt, Error>?
        init(_ done: XCTestExpectation) { self.done = done }
    }
    private final class Flag: @unchecked Sendable {
        private let lock = NSLock()
        private var stored = false
        var value: Bool { lock.lock(); defer { lock.unlock() }; return stored }
        func set(_ value: Bool) { lock.lock(); stored = value; lock.unlock() }
    }
    @MainActor private final class Fixture {
        let canonical = CanonicalSessionState()
        let sdk: SDKState
        let configuration: Coordinator.Configuration
        var nowMs: Int64 = 10_000
        var nowReads = 0
        var events: [String] = []
        var marker: Marker?
        var markers: [Marker?] = []
        var markerReads = 0
        var markerGates: [Int: Gate<Marker?>] = [:]
        var markerError: Error?
        var memberGate: Gate<Contract.MembershipSnapshot>?
        var memberError: Error?
        var member: [String: Any]? = ["schemaVersion": 1, "ownerUID": "reader-A", "epoch": 7, "state": "active"]
        var memberExpiry: Int64 = 20_000
        var memberTransform: ((Contract.MembershipRequest) throws -> Contract.MembershipSnapshot)?
        var memberRequests: [Contract.MembershipRequest] = []
        var verifyGate: Gate<Coordinator.Permit>?
        var verifierError: Error?
        var permitTransform: ((Coordinator.Challenge) throws -> Coordinator.Permit)?
        var challenges: [Coordinator.Challenge] = []
        var beforeAdmissionGate: Gate<Void>?
        var skipAdmission = false
        var duplicateAdmission = false
        var admissions: [Coordinator.StartAdmission] = []
        var starterGate: Gate<Void>?
        var starterError: Error?
        var starterHook: (() async -> Void)?
        var starts: [Coordinator.Receipt] = []
        var scheduleHook: (() -> Void)?
        var cancelDeadlineHook: (() -> Void)?
        var nowHook: (() -> Void)?
        var deadlines: [@MainActor () -> Void] = []
        var cancelledDeadlines = 0
        lazy var coordinator = makeCoordinator()

        init(sdk: SDKState? = nil) throws {
            self.sdk = sdk ?? SDKState()
            configuration = try Coordinator.Configuration(projectID: "apropos-fixture", appID: "fixture-app",
                installationID: UUID(), writerFenceRevision: String(repeating: "a", count: 64),
                migrationRevision: String(repeating: "b", count: 64))
            select("reader-A")
        }
        var context: CanonicalSessionState.ContextTicket { canonical.contextTicket() }
        func select(_ uid: String?, force: Bool = false) {
            canonical.adopt(uid.map { .init(uid: $0, email: "fixture@example.invalid", isEmailVerified: true) },
                            forceNewGeneration: force)
        }
        func makeCoordinator(verifier: Bool = true,
                             readMarker: (@MainActor () async throws -> Marker?)? = nil) -> Coordinator {
            let markerReader: @MainActor () async throws -> Marker?
            if let readMarker {
                markerReader = readMarker
            } else {
                markerReader = { [unowned self] in
                    self.events.append("marker"); self.markerReads += 1
                    if let gate = self.markerGates[self.markerReads] { return try await gate.wait() }
                    if let error = self.markerError { throw error }
                    return self.markers.isEmpty ? self.marker : self.markers.removeFirst()
                }
            }
            let membershipReader: @MainActor (Contract.MembershipRequest) async throws -> Contract.MembershipSnapshot = { [unowned self] request in
                self.events.append("membership"); self.memberRequests.append(request)
                if let gate = self.memberGate { return try await gate.wait() }
                if let error = self.memberError { throw error }
                if let transform = self.memberTransform { return try transform(request) }
                return try self.snapshot(request)
            }
            let boundaryVerifier: Coordinator.Verifier?
            if verifier {
                boundaryVerifier = { [unowned self] challenge in
                    self.events.append("verify"); self.challenges.append(challenge)
                    if let gate = self.verifyGate { return try await gate.wait() }
                    if let error = self.verifierError { throw error }
                    if let transform = self.permitTransform { return try transform(challenge) }
                    return self.permit(challenge)
                }
            } else {
                boundaryVerifier = nil
            }
            let starter: @MainActor (Coordinator.Receipt, @escaping Coordinator.StartAdmission) async throws -> Void = { [unowned self] receipt, admit in
                self.admissions.append(admit)
                if let gate = self.beforeAdmissionGate { try await gate.wait() }
                if self.skipAdmission { return }
                try admit()
                self.events.append("start"); self.starts.append(receipt)
                if self.duplicateAdmission { try admit() }
                await self.starterHook?()
                if let gate = self.starterGate { try await gate.wait() }
                if let error = self.starterError { throw error }
            }
            let clock: @MainActor () -> Int64 = { [unowned self] in
                self.nowReads += 1; self.nowHook?(); return self.nowMs
            }
            let scheduler: Coordinator.Schedule = { [unowned self] action in
                self.deadlines.append(action); self.scheduleHook?()
                return { [unowned self] in
                    self.cancelledDeadlines += 1; self.cancelDeadlineHook?()
                }
            }
            return Coordinator(canonical: canonical, sdkState: sdk, configuration: configuration,
                readMarker: markerReader, readMembership: membershipReader, verify: boundaryVerifier,
                startSDK: starter, now: clock, schedule: scheduler)
        }
        func snapshot(_ request: Contract.MembershipRequest) throws -> Contract.MembershipSnapshot {
            let echoed = try JSONSerialization.jsonObject(with: Contract.encode(request))
            return try Contract.decodeMembershipResponse(data: JSONSerialization.data(withJSONObject: [
                "schemaVersion": 1, "scope": Contract.membershipScope, "request": echoed,
                "membership": member.map { $0 as Any } ?? NSNull(), "validUntilMs": memberExpiry
            ]), for: request)
        }
        func permit(_ challenge: Coordinator.Challenge,
                    coverage: Coordinator.Coverage = .allPersistedWritersIncludingPreviousAccounts,
                    expiry: Int64 = 20_000, fence: String? = nil, migration: String? = nil) -> Coordinator.Permit {
            .init(challenge: challenge, coverage: coverage,
                writerFenceRevision: fence ?? configuration.writerFenceRevision,
                migrationRevision: migration ?? configuration.migrationRevision, validUntilMs: expiry)
        }
    }

    private func launch(_ coordinator: Coordinator, context: CanonicalSessionState.ContextTicket) -> Pending {
        let pending = Pending(expectation(description: "Logical startup caller returns"))
        pending.task = Task { @MainActor in
            do { pending.result = .success(try await coordinator.start(context: context)) }
            catch { pending.result = .failure(error) }
            pending.done.fulfill()
        }
        return pending
    }
    private func failure(_ pending: Pending, equals expected: Coordinator.Failure? = nil,
                         file: StaticString = #filePath, line: UInt = #line) async {
        await fulfillment(of: [pending.done], timeout: 3)
        guard case .failure(let error) = pending.result else { return XCTFail("Expected startup failure", file: file, line: line) }
        if let expected { XCTAssertEqual(error as? Coordinator.Failure, expected, file: file, line: line) }
    }
    private func rejects(_ coordinator: Coordinator, context: CanonicalSessionState.ContextTicket,
                         file: StaticString = #filePath, line: UInt = #line) async {
        do { _ = try await coordinator.start(context: context); XCTFail("Startup must remain closed", file: file, line: line) }
        catch { }
    }
    private func idle(_ coordinator: Coordinator, file: StaticString = #filePath, line: UInt = #line) async {
        // Logical completion deliberately precedes physical completion. Poll only
        // the actual state, evaluated on MainActor, with XCTest's bounded waiter.
        // No timing sleeps or fixed number of actor yields stand in for completion.
        let flag = Flag()
        let predicate = NSPredicate { _, _ in
            Task { @MainActor in flag.set(!coordinator.isBusy) }
            return flag.value
        }
        await fulfillment(of: [XCTNSPredicateExpectation(predicate: predicate, object: nil)], timeout: 3)
        XCTAssertFalse(coordinator.isBusy, file: file, line: line)
    }
    private func marker(owner: String = "reader-A", epoch: Int64 = 7) throws -> Marker {
        .init(binding: try .init(ownerUID: owner, epoch: epoch), transitionID: UUID())
    }

    func testConstructionIsInertAndSharesNoImplicitSDKAuthority() throws {
        let f = try Fixture(); _ = f.coordinator
        XCTAssertEqual(f.sdk.status, .idle); XCTAssertFalse(f.coordinator.isBusy)
        XCTAssertTrue(f.events.isEmpty); XCTAssertTrue(f.deadlines.isEmpty); XCTAssertEqual(f.nowReads, 0)
        XCTAssertTrue(f.memberRequests.isEmpty); XCTAssertTrue(f.starts.isEmpty)
    }

    func testAlreadyCancelledCallerCannotReserveOrInvokeAnyStartupHook() async throws {
        let f = try Fixture(), pending = launch(f.coordinator, context: f.context)
        pending.task?.cancel()
        await failure(pending, equals: .cancelled)
        XCTAssertTrue(f.events.isEmpty); XCTAssertTrue(f.deadlines.isEmpty)
        XCTAssertEqual(f.sdk.status, .idle); XCTAssertFalse(f.coordinator.isBusy)
    }

    func testConfigurationRejectsMissingIDsAndNonCanonicalRevisionPins() throws {
        let valid = String(repeating: "a", count: 64)
        let invalid: [(String, String, String, String)] = [
            ("", "app", valid, valid), ("project", "", valid, valid),
            ("project", "app", "", valid), ("project", "app", valid, String(repeating: "A", count: 64)),
            ("project", "app", String(repeating: "a", count: 63), valid),
            ("project", "app", valid, String(repeating: "g", count: 64))
        ]
        for (project, app, fence, migration) in invalid {
            XCTAssertThrowsError(try Coordinator.Configuration(projectID: project, appID: app,
                installationID: UUID(), writerFenceRevision: fence, migrationRevision: migration))
        }
    }

    func testSuccessfulStartupOrdersAllBoundariesAndStartsSDKExactlyOnce() async throws {
        let f = try Fixture(), original = f.context
        let receipt = try await f.coordinator.start(context: original)
        XCTAssertEqual(f.events, ["marker", "membership", "verify", "marker", "start"])
        XCTAssertEqual(receipt.challenge.context, original)
        XCTAssertEqual(receipt.challenge.configuration, f.configuration)
        XCTAssertEqual(receipt.challenge.binding, try .init(ownerUID: "reader-A", epoch: 7))
        XCTAssertNil(receipt.challenge.marker); XCTAssertEqual(f.sdk.status, .started)
        XCTAssertFalse(f.coordinator.isBusy); XCTAssertEqual(f.starts.count, 1)
        await rejects(f.coordinator, context: original)
        await rejects(f.makeCoordinator(), context: original)
        XCTAssertEqual(f.starts.count, 1)
    }

    func testHeldMarkerBlocksMembershipVerifierAndCompetingCoordinator() async throws {
        let f = try Fixture(), gate = Gate<Marker?>(expectation(description: "Physical marker read"))
        f.markerGates[1] = gate
        let pending = launch(f.coordinator, context: f.context)
        await fulfillment(of: [gate.entered], timeout: 3)
        XCTAssertEqual(f.events, ["marker"]); XCTAssertEqual(f.nowReads, 0)
        XCTAssertTrue(f.coordinator.isBusy); XCTAssertEqual(f.sdk.status, .preparing)
        await rejects(f.makeCoordinator(), context: f.context)
        XCTAssertTrue(f.memberRequests.isEmpty); XCTAssertTrue(f.starts.isEmpty)
        gate.resolve(.success(nil))
        await fulfillment(of: [pending.done], timeout: 3)
        _ = try XCTUnwrap(pending.result).get(); XCTAssertEqual(f.starts.count, 1)
    }

    func testMarkerFailureDoesNotReadMembershipOrStartSDK() async throws {
        let f = try Fixture(); f.markerError = ReaderTransitionRecoveryStore.Failure.invalidMarker
        await failure(launch(f.coordinator, context: f.context))
        XCTAssertEqual(f.events, ["marker"]); XCTAssertEqual(f.sdk.status, .idle)
        XCTAssertFalse(f.coordinator.isBusy)
    }

    func testGuestUnresolvedForeignAndStaleContextsCannotBegin() async throws {
        let f = try Fixture(), stale = f.context
        f.select(nil)
        await rejects(f.coordinator, context: f.context)
        f.canonical.suspend()
        await rejects(f.coordinator, context: f.context)
        f.select("reader-A")
        await rejects(f.coordinator, context: stale)
        let foreign = CanonicalSessionState()
        foreign.adopt(.init(uid: "reader-A", email: "fixture@example.invalid", isEmailVerified: true))
        await rejects(f.coordinator, context: foreign.contextTicket())
        XCTAssertTrue(f.events.isEmpty); XCTAssertTrue(f.deadlines.isEmpty); XCTAssertEqual(f.sdk.status, .idle)
    }

    func testMissingAndFrozenMembershipDoNotCreateStartupAuthority() async throws {
        for frozen in [false, true] {
            let f = try Fixture()
            if frozen {
                f.member = ["schemaVersion": 1, "ownerUID": "reader-A", "epoch": 7, "state": "deletion_frozen",
                            "deletionRequestID": try ReaderAccountDeletionContract.Request(expectedUID: "reader-A", membershipEpoch: 7).requestID]
            } else { f.member = nil }
            await failure(launch(f.coordinator, context: f.context))
            XCTAssertEqual(f.events, ["marker", "membership"])
            XCTAssertTrue(f.challenges.isEmpty); XCTAssertEqual(f.sdk.status, .idle)
        }
    }

    func testMembershipSnapshotMustEchoThisExactReadRequest() async throws {
        let f = try Fixture()
        f.memberTransform = { request in
            try f.snapshot(.init(expectedUID: request.expectedUID, readID: UUID().uuidString.lowercased()))
        }
        await failure(launch(f.coordinator, context: f.context))
        XCTAssertTrue(f.challenges.isEmpty); XCTAssertTrue(f.starts.isEmpty)
    }

    func testExpiredMembershipAndMembershipTransportFailureStayClosed() async throws {
        for expired in [false, true] {
            let f = try Fixture()
            if expired { f.memberExpiry = f.nowMs } else { f.memberError = Injected.membership }
            await failure(launch(f.coordinator, context: f.context))
            XCTAssertTrue(f.challenges.isEmpty); XCTAssertTrue(f.starts.isEmpty)
        }
    }

    func testPersistedMarkerCannotBeAdoptedByDifferentOwnerOrNewEpoch() async throws {
        for original in [try marker(owner: "reader-B"), try marker(epoch: 6)] {
            let f = try Fixture(); f.marker = original
            await failure(launch(f.coordinator, context: f.context), equals: .markerMismatch)
            XCTAssertTrue(f.challenges.isEmpty); XCTAssertTrue(f.starts.isEmpty)
        }
    }

    func testActiveMembershipWithoutInstallationVerifierNeverStartsSDK() async throws {
        let f = try Fixture(), coordinator = f.makeCoordinator(verifier: false)
        await failure(launch(coordinator, context: f.context))
        XCTAssertEqual(f.events, ["marker", "membership"])
        XCTAssertEqual(f.sdk.status, .idle); XCTAssertTrue(f.starts.isEmpty)
    }

    func testValidScopedResourceReadStillCannotAuthorizeAllPersistedSDKWriters() async throws {
        let f = try Fixture()
        let request = try Contract.ResourceRequest(binding: .init(ownerUID: "reader-A", epoch: 7),
            target: .favorite(id: "story"), readID: UUID().uuidString.lowercased())
        let wire: [String: Any] = ["schemaVersion": 1, "scope": Contract.resourceScope,
            "request": try JSONSerialization.jsonObject(with: Contract.encode(request)), "membership": try XCTUnwrap(f.member),
            "boundary": ["readerSchemaVersion": 1, "writerFenceRevision": f.configuration.writerFenceRevision,
                         "migrationRevision": f.configuration.migrationRevision],
            "resource": ["revision": 0, "exists": false, "payload": NSNull()], "validUntilMs": 20_000]
        let resource = try Contract.decodeResourceResponse(data: JSONSerialization.data(withJSONObject: wire), for: request)
        f.permitTransform = { challenge in
            f.permit(challenge, coverage: .currentReaderOnly, expiry: resource.validUntilMs,
                fence: resource.boundary.writerFenceRevision, migration: resource.boundary.migrationRevision)
        }
        await failure(launch(f.coordinator, context: f.context), equals: .invalidPermit)
        XCTAssertTrue(f.starts.isEmpty); XCTAssertEqual(f.sdk.status, .idle)
    }

    func testPermitRequiresExactChallengeAndBothPinnedRevisions() async throws {
        for variation in 0..<4 {
            let f = try Fixture()
            f.permitTransform = { challenge in
                switch variation {
                case 0: return f.permit(challenge, fence: String(repeating: "c", count: 64))
                case 1: return f.permit(challenge, migration: String(repeating: "c", count: 64))
                case 2:
                    let different = Coordinator.Challenge(configuration: challenge.configuration, context: challenge.context,
                        binding: challenge.binding, marker: challenge.marker, readID: UUID().uuidString.lowercased())
                    return f.permit(different)
                default:
                    let different = Coordinator.Challenge(configuration: challenge.configuration, context: challenge.context,
                        binding: try .init(ownerUID: "reader-A", epoch: 8), marker: challenge.marker, readID: challenge.readID)
                    return f.permit(different)
                }
            }
            await failure(launch(f.coordinator, context: f.context), equals: .invalidPermit)
            XCTAssertTrue(f.starts.isEmpty); XCTAssertEqual(f.sdk.status, .idle)
        }
    }

    func testExpiredPermitAndVerifierFailureCannotReachSecondMarkerRead() async throws {
        for expired in [false, true] {
            let f = try Fixture()
            if expired { f.permitTransform = { f.permit($0, expiry: f.nowMs) } }
            else { f.verifierError = Injected.verifier }
            await failure(launch(f.coordinator, context: f.context))
            XCTAssertEqual(f.markerReads, 1); XCTAssertTrue(f.starts.isEmpty)
        }
    }

    func testSecondMarkerReadMustMatchInitialAbsenceOrExactOriginal() async throws {
        let original = try marker()
        let changes: [(Marker?, Marker?)] = [(nil, original), (original, nil), (original, try marker()),
                                             (original, try marker(epoch: 8))]
        for (before, after) in changes {
            let f = try Fixture(); f.markers = [before, after]
            await failure(launch(f.coordinator, context: f.context), equals: .markerMismatch)
            XCTAssertEqual(f.markerReads, 2); XCTAssertTrue(f.starts.isEmpty)
        }
    }

    func testHeldMembershipAccountRoundTripNeverAdoptsLateOriginalResponse() async throws {
        let f = try Fixture(), gate = Gate<Contract.MembershipSnapshot>(expectation(description: "Membership read held"))
        f.memberGate = gate
        let original = f.context, pending = launch(f.coordinator, context: original)
        await fulfillment(of: [gate.entered], timeout: 3)
        let request = try XCTUnwrap(f.memberRequests.first)
        f.select("reader-B"); f.select("reader-A")
        await failure(pending, equals: .stale)
        XCTAssertTrue(f.coordinator.isBusy); XCTAssertEqual(f.sdk.status, .preparing)
        await rejects(f.makeCoordinator(), context: f.context)
        gate.resolve(.success(try f.snapshot(request)))
        await idle(f.coordinator)
        XCTAssertTrue(f.starts.isEmpty); XCTAssertTrue(f.challenges.isEmpty); XCTAssertEqual(f.sdk.status, .idle)
    }

    func testSameUIDNewGenerationInvalidatesHeldVerifier() async throws {
        let f = try Fixture(), gate = Gate<Coordinator.Permit>(expectation(description: "Verifier held"))
        f.verifyGate = gate
        let pending = launch(f.coordinator, context: f.context)
        await fulfillment(of: [gate.entered], timeout: 3)
        let challenge = try XCTUnwrap(f.challenges.first)
        f.select("reader-A", force: true)
        await failure(pending, equals: .stale)
        XCTAssertTrue(f.coordinator.isBusy)
        gate.resolve(.success(f.permit(challenge)))
        await idle(f.coordinator)
        XCTAssertTrue(f.starts.isEmpty); XCTAssertEqual(f.markerReads, 1)
    }

    func testTimeoutWhileMarkerIsHeldReleasesCallerButNotSharedPhysicalSlot() async throws {
        let f = try Fixture(), gate = Gate<Marker?>(expectation(description: "Timed marker read held"))
        f.markerGates[1] = gate
        let pending = launch(f.coordinator, context: f.context)
        await fulfillment(of: [gate.entered], timeout: 3)
        try XCTUnwrap(f.deadlines.first)()
        await failure(pending, equals: .timedOut)
        XCTAssertTrue(f.coordinator.isBusy); XCTAssertEqual(f.sdk.status, .preparing)
        await rejects(f.makeCoordinator(), context: f.context)
        gate.resolve(.success(nil))
        await idle(f.coordinator)
        XCTAssertEqual(f.sdk.status, .idle); XCTAssertEqual(f.events, ["marker"])
        let receipt = try await f.coordinator.start(context: f.context)
        XCTAssertEqual(receipt.challenge.context, f.context); XCTAssertEqual(f.starts.count, 1)
    }

    func testCancellationWhileVerifierIsHeldCannotStartFromItsLatePermit() async throws {
        let f = try Fixture(), gate = Gate<Coordinator.Permit>(expectation(description: "Cancelled verifier held"))
        f.verifyGate = gate
        let pending = launch(f.coordinator, context: f.context)
        await fulfillment(of: [gate.entered], timeout: 3)
        let challenge = try XCTUnwrap(f.challenges.first)
        pending.task?.cancel()
        await failure(pending, equals: .cancelled)
        XCTAssertTrue(f.coordinator.isBusy); await rejects(f.makeCoordinator(), context: f.context)
        gate.resolve(.success(f.permit(challenge)))
        await idle(f.coordinator)
        XCTAssertTrue(f.starts.isEmpty); XCTAssertEqual(f.sdk.status, .idle)
    }

    func testTimeoutDuringSecondMarkerReadRejectsOtherwiseValidPermit() async throws {
        let f = try Fixture(), gate = Gate<Marker?>(expectation(description: "Final marker read held"))
        f.markerGates[2] = gate
        let pending = launch(f.coordinator, context: f.context)
        await fulfillment(of: [gate.entered], timeout: 3)
        try XCTUnwrap(f.deadlines.first)()
        await failure(pending, equals: .timedOut)
        XCTAssertTrue(f.coordinator.isBusy); XCTAssertEqual(f.challenges.count, 1)
        gate.resolve(.success(nil))
        await idle(f.coordinator); XCTAssertTrue(f.starts.isEmpty)
    }

    func testExpiryAdvancingDuringFinalMarkerAwaitPreventsSDKStart() async throws {
        let f = try Fixture(), gate = Gate<Marker?>(expectation(description: "Final marker before expiry"))
        f.markerGates[2] = gate
        let pending = launch(f.coordinator, context: f.context)
        await fulfillment(of: [gate.entered], timeout: 3)
        f.nowMs = 20_000; gate.resolve(.success(nil))
        await failure(pending, equals: .expired)
        XCTAssertTrue(f.starts.isEmpty); XCTAssertEqual(f.sdk.status, .idle)
    }

    func testScheduleHookTimeoutBeforePhysicalWorkHasNoEffects() async throws {
        let f = try Fixture()
        f.scheduleHook = { f.deadlines.last?() }
        await failure(launch(f.coordinator, context: f.context), equals: .timedOut)
        await idle(f.coordinator)
        XCTAssertTrue(f.events.isEmpty); XCTAssertEqual(f.sdk.status, .idle)
    }

    func testDeadlineCancellationReentryRevokesReceiptWithoutHidingActualSDKStart() async throws {
        let f = try Fixture()
        f.cancelDeadlineHook = { f.select("reader-B") }
        await failure(launch(f.coordinator, context: f.context))
        XCTAssertEqual(f.starts.count, 1); XCTAssertEqual(f.sdk.status, .started)
        XCTAssertEqual(f.markerReads, 2)
        await rejects(f.makeCoordinator(), context: f.context)
        XCTAssertEqual(f.starts.count, 1)
    }

    func testDeadlineCancellationHookCannotReturnAReceiptThatJustExpired() async throws {
        let f = try Fixture()
        f.cancelDeadlineHook = { f.nowMs = 20_000 }
        await failure(launch(f.coordinator, context: f.context), equals: .expired)
        XCTAssertEqual(f.starts.count, 1); XCTAssertEqual(f.sdk.status, .started)
        await rejects(f.makeCoordinator(), context: f.context)
        XCTAssertEqual(f.starts.count, 1)
    }

    func testFinalClockHookReentryCannotReviveOriginalAccount() async throws {
        let f = try Fixture(), gate = Gate<Marker?>(expectation(description: "Final marker before clock reentry"))
        f.markerGates[2] = gate
        let pending = launch(f.coordinator, context: f.context)
        await fulfillment(of: [gate.entered], timeout: 3)
        f.nowHook = {
            f.nowHook = nil
            f.select("reader-B"); f.select("reader-A")
        }
        gate.resolve(.success(nil))
        await failure(pending)
        XCTAssertTrue(f.starts.isEmpty); XCTAssertEqual(f.sdk.status, .idle)
    }

    func testPhysicalStarterThrowIsUncertainAndNeverRetried() async throws {
        let f = try Fixture(); f.starterError = Injected.starter
        await failure(launch(f.coordinator, context: f.context))
        XCTAssertEqual(f.sdk.status, .uncertain); XCTAssertEqual(f.starts.count, 1)
        f.starterError = nil
        await rejects(f.coordinator, context: f.context)
        await rejects(f.makeCoordinator(), context: f.context)
        XCTAssertEqual(f.starts.count, 1)
    }

    func testStarterReentryCannotStartSameSharedSDKTwice() async throws {
        let f = try Fixture(), competitor = f.makeCoordinator()
        var attemptedStatus: SDKState.Status?
        f.starterHook = {
            attemptedStatus = f.sdk.status
            do { _ = try await competitor.start(context: f.context); XCTFail("Reentrant starter admitted") }
            catch { }
        }
        _ = try await f.coordinator.start(context: f.context)
        XCTAssertEqual(attemptedStatus, .attempted); XCTAssertEqual(f.starts.count, 1)
        XCTAssertEqual(f.sdk.status, .started)
    }

    func testAccountChangeDuringPhysicalStarterKeepsSharedSlotAndRecordsActualSuccess() async throws {
        let f = try Fixture(), gate = Gate<Void>(expectation(description: "Physical SDK starter held"))
        f.starterGate = gate
        let pending = launch(f.coordinator, context: f.context)
        await fulfillment(of: [gate.entered], timeout: 3)
        XCTAssertEqual(f.sdk.status, .attempted)
        f.select("reader-B"); f.select("reader-A")
        await failure(pending, equals: .stale)
        XCTAssertTrue(f.coordinator.isBusy)
        await rejects(f.makeCoordinator(), context: f.context)
        gate.resolve(.success(())); await idle(f.coordinator)
        XCTAssertEqual(f.sdk.status, .started); XCTAssertEqual(f.starts.count, 1)
        await rejects(f.makeCoordinator(), context: f.context)
        XCTAssertEqual(f.starts.count, 1)
    }

    func testCancelledPhysicalStarterFailureStaysUncertainAfterCallback() async throws {
        let f = try Fixture(), gate = Gate<Void>(expectation(description: "Cancelled physical SDK starter"))
        f.starterGate = gate
        let pending = launch(f.coordinator, context: f.context)
        await fulfillment(of: [gate.entered], timeout: 3)
        pending.task?.cancel(); await failure(pending, equals: .cancelled)
        XCTAssertTrue(f.coordinator.isBusy); XCTAssertEqual(f.sdk.status, .attempted)
        gate.resolve(.failure(Injected.starter)); await idle(f.coordinator)
        XCTAssertEqual(f.sdk.status, .uncertain)
        await rejects(f.makeCoordinator(), context: f.context); XCTAssertEqual(f.starts.count, 1)
    }

    func testSuspendedAdapterMustRecheckAdmissionAfterCancellationTimeoutOrAccountRoundTrip() async throws {
        for variation in 0..<3 {
            let f = try Fixture(), gate = Gate<Void>(expectation(description: "Adapter suspended before SDK admission"))
            f.beforeAdmissionGate = gate
            let pending = launch(f.coordinator, context: f.context)
            await fulfillment(of: [gate.entered], timeout: 3)
            XCTAssertTrue(f.starts.isEmpty); XCTAssertEqual(f.sdk.status, .attempted)
            let expected: Coordinator.Failure
            switch variation {
            case 0: pending.task?.cancel(); expected = .cancelled
            case 1: try XCTUnwrap(f.deadlines.first)(); expected = .timedOut
            default: f.select("reader-B"); f.select("reader-A"); expected = .stale
            }
            await failure(pending, equals: expected)
            XCTAssertTrue(f.coordinator.isBusy)
            await rejects(f.makeCoordinator(), context: f.context)
            gate.resolve(.success(())); await idle(f.coordinator)
            XCTAssertTrue(f.starts.isEmpty, "A returned late adapter must not construct an SDK reference")
            XCTAssertEqual(f.sdk.status, .uncertain)
            XCTAssertThrowsError(try XCTUnwrap(f.admissions.first)())
            await rejects(f.makeCoordinator(), context: f.context)
        }
    }

    func testMissingOrRepeatedFinalAdmissionNeverProducesSuccessOrReopensSDK() async throws {
        for missing in [true, false] {
            let f = try Fixture(); f.skipAdmission = missing; f.duplicateAdmission = !missing
            await failure(launch(f.coordinator, context: f.context))
            XCTAssertEqual(f.starts.count, missing ? 0 : 1); XCTAssertEqual(f.sdk.status, .uncertain)
            XCTAssertThrowsError(try XCTUnwrap(f.admissions.first)())
            await rejects(f.makeCoordinator(), context: f.context)
            XCTAssertEqual(f.starts.count, missing ? 0 : 1)
        }
    }

    func testDeadlineRemainsActiveWhilePhysicalSDKStarterHasNotReturned() async throws {
        let f = try Fixture(), gate = Gate<Void>(expectation(description: "Started SDK has not returned"))
        f.starterGate = gate
        let pending = launch(f.coordinator, context: f.context)
        await fulfillment(of: [gate.entered], timeout: 3)
        XCTAssertEqual(f.starts.count, 1); XCTAssertEqual(f.cancelledDeadlines, 0)
        try XCTUnwrap(f.deadlines.first)()
        await failure(pending, equals: .timedOut)
        XCTAssertTrue(f.coordinator.isBusy); XCTAssertEqual(f.sdk.status, .attempted)
        await rejects(f.makeCoordinator(), context: f.context)
        gate.resolve(.success(())); await idle(f.coordinator)
        XCTAssertEqual(f.sdk.status, .started); XCTAssertEqual(f.starts.count, 1)
    }

    func testAlreadyInitializedSDKCannotClaimCleanStartupBoundary() async throws {
        let f = try Fixture(sdk: SDKState(alreadyInitialized: true))
        await rejects(f.coordinator, context: f.context)
        XCTAssertTrue(f.events.isEmpty); XCTAssertTrue(f.deadlines.isEmpty)
    }

    func testActualPersistedMarkerOnRestartRequiresFreshReadAndFreshPermit() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("reader-startup-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let original = try marker(), store = ReaderTransitionRecoveryStore(rootDirectory: root)
        let saved: Marker = try await withCheckedThrowingContinuation { continuation in
            store.seal(original) { continuation.resume(with: $0) }
        }
        XCTAssertEqual(saved, original)
        func diskReader(_ store: ReaderTransitionRecoveryStore) -> @MainActor () async throws -> Marker? {
            { try await withCheckedThrowingContinuation { continuation in
                store.read { continuation.resume(with: $0) }
            } }
        }
        let first = try Fixture(), a = first.makeCoordinator(readMarker: diskReader(store))
        let firstReceipt = try await a.start(context: first.context)
        XCTAssertEqual(firstReceipt.challenge.marker, original)
        let next = try Fixture()
        let restarted = next.makeCoordinator(readMarker: diskReader(ReaderTransitionRecoveryStore(rootDirectory: root)))
        next.permitTransform = { _ in first.permit(firstReceipt.challenge) }
        await failure(launch(restarted, context: next.context), equals: .invalidPermit)
        XCTAssertTrue(next.starts.isEmpty); XCTAssertEqual(next.memberRequests.count, 1)
        next.permitTransform = nil
        let newReceipt = try await restarted.start(context: next.context)
        XCTAssertEqual(newReceipt.challenge.marker, original)
        XCTAssertNotEqual(newReceipt.challenge.readID, firstReceipt.challenge.readID)
        XCTAssertEqual(next.starts.count, 1); XCTAssertEqual(next.memberRequests.count, 2)
    }
}
