import Combine
import Foundation
import XCTest
@testable import Apropos

@MainActor
final class PushAcknowledgedBindingTests: XCTestCase {
    func testActualHTTPModelAndVaultRetainPendingThenActiveServerCounters() async throws {
        let f = BindingFixture()
        let model = f.model()
        await model.update(f.intent())
        XCTAssertEqual(model.state, .pending)
        let pendingRecord = try await f.vault.readExisting()
        let pending = try XCTUnwrap(pendingRecord)
        XCTAssertEqual(pending.acknowledgedBinding?.ownerEpoch, 7)
        XCTAssertEqual(pending.acknowledgedBinding?.revision, 31)
        XCTAssertEqual(pending.revision, 1)
        XCTAssertEqual(pending.acknowledgedBinding, model.acknowledgedBinding)
        let handled = await model.receiveChallenge(f.challengePayload())
        XCTAssertTrue(handled)
        XCTAssertEqual(model.state, .active)
        let activeRecord = try await f.vault.readExisting()
        let active = try XCTUnwrap(activeRecord)
        XCTAssertEqual(active.acknowledgedBinding?.status, .active)
        XCTAssertEqual(active.acknowledgedBinding?.revision, 31)
        XCTAssertEqual(f.headers, ["1", "1"])
        XCTAssertEqual(f.store.writes, 3) // preparation, pending ACK, active ACK
    }

    func testLegacyModePreservesOldReceiptWithoutInventingAuthority() async throws {
        let f = BindingFixture(); f.includeBinding = false
        let model = f.model(configured: false)
        await model.update(f.intent())
        XCTAssertEqual(model.state, .pending)
        XCTAssertNil(model.acknowledgedBinding)
        let stored = try await f.vault.readExisting()
        XCTAssertNil(stored?.acknowledgedBinding)
        XCTAssertEqual(f.headers.count, 1); XCTAssertNil(f.headers[0])
    }

    func testMissingBindingOnNegotiatedTransportFailsClosedWithoutChangingIdentity() async throws {
        let f = BindingFixture(); f.includeBinding = false
        let model = f.model()
        await model.update(f.intent())
        XCTAssertEqual(model.state, .blocked(.invalidResponse))
        XCTAssertNil(model.acknowledgedBinding)
        let stored = try await f.vault.readExisting()
        XCTAssertEqual(stored?.revision, 1); XCTAssertNil(stored?.acknowledgedBinding)
        XCTAssertEqual(f.store.writes, 1)
    }

    func testHTTPRejectsWrongAndMalformedBindingsWithoutVaultACK() async throws {
        let mutations: [(inout [String: Any]) -> Void] = [
            { $0["ownerUID"] = "reader_B" }, { $0["appId"] = "another-app" },
            { $0["installationId"] = "22222222-2222-4222-8222-222222222222" },
            { $0["clientRevision"] = 2 }, { $0["ownerEpoch"] = true },
            { $0["revision"] = 1.5 }, { $0["schemaVersion"] = 2 },
            { $0["status"] = "active" }, { $0["token"] = "must-never-be-retained" },
            { $0.removeValue(forKey: "ownerUID") }
        ]
        for mutation in mutations {
            let f = BindingFixture(); f.mutate = mutation; let model = f.model()
            await model.update(f.intent())
            XCTAssertEqual(model.state, .blocked(.invalidResponse))
            let stored = try await f.vault.readExisting()
            XCTAssertNil(stored?.acknowledgedBinding); XCTAssertEqual(f.store.writes, 1)
        }
    }

    func testExplicitGuestBindingCannotBorrowSignedInOwner() async throws {
        let f = BindingFixture(); let guest = PushAccountContext.guest(epoch: UUID()); let model = f.model()
        await model.update(f.intent(context: guest))
        let storedRecord = try await f.vault.readExisting()
        let stored = try XCTUnwrap(storedRecord)
        XCTAssertNil(stored.acknowledgedBinding?.ownerUID)
        XCTAssertEqual(stored.acknowledgedBinding?.ownerEpoch, 7)
        XCTAssertEqual(model.state, .pending)
    }

    func testTokenRevisionClearsPriorACKAndStoresOnlyNewOriginalBinding() async throws {
        let f = BindingFixture(); let model = f.model()
        await model.update(f.intent())
        f.includeBinding = false
        await model.update(f.intent(token: String(repeating: "n", count: 60)))
        let storedRecord = try await f.vault.readExisting()
        let stored = try XCTUnwrap(storedRecord)
        XCTAssertEqual(stored.revision, 2)
        XCTAssertNil(stored.acknowledgedBinding)
        XCTAssertNil(model.acknowledgedBinding)
    }

    func testLatePendingResponseCannotDowngradeConfirmedBinding() async throws {
        let f = BindingFixture(); f.holdRegister = true; let model = f.model()
        let update = Task { await model.update(f.intent()) }
        await wait { f.heldResponse != nil }
        let handled = await model.receiveChallenge(f.challengePayload())
        XCTAssertTrue(handled)
        XCTAssertEqual(model.state, .active)
        f.finishHeld(); await update.value
        let stored = try await f.vault.readExisting()
        XCTAssertEqual(stored?.acknowledgedBinding?.status, .active)
        XCTAssertEqual(model.acknowledgedBinding?.status, .active)
        XCTAssertEqual(f.store.writes, 2)
    }

    func testLatePendingStorageFailureCannotBlockCompletedConfirmation() async throws {
        let f = BindingFixture(); var held: CheckedContinuation<Void, Never>?
        var physicalReturned = false
        let model = f.model(retain: { binding, original, lease in
            if binding.status == .pending {
                await withCheckedContinuation { held = $0 }
                defer { physicalReturned = true }
                return try await f.vault.acknowledge(binding, original: original, lease: lease)
            }
            return try await f.vault.acknowledge(binding, original: original, lease: lease)
        })
        let update = Task { await model.update(f.intent()) }
        await wait { held != nil }
        let handled = await model.receiveChallenge(f.challengePayload())
        XCTAssertTrue(handled); XCTAssertEqual(model.state, .active)
        held?.resume(); held = nil; await update.value; await wait { physicalReturned }
        XCTAssertEqual(model.state, .active)
        XCTAssertEqual(model.acknowledgedBinding?.status, .active)
        let stored = try await f.vault.readExisting()
        XCTAssertEqual(stored?.acknowledgedBinding?.status, .active)
    }

    func testOldHTTPResponseAfterAccountABAHasNoPublicationOrACKWrite() async throws {
        let f = BindingFixture(); f.holdRegister = true; let model = f.model()
        let old = Task { await model.update(f.intent()) }
        await wait { f.heldResponse != nil }; f.holdRegister = false
        await model.update(f.intent(context: .authenticated(uid: "reader_B", epoch: UUID())))
        await model.update(f.intent(context: .authenticated(uid: "reader_A", epoch: UUID())))
        let current = try await f.vault.readExisting(), writes = f.store.writes
        f.finishHeld(); await old.value
        let after = try await f.vault.readExisting()
        XCTAssertEqual(after, current); XCTAssertEqual(f.store.writes, writes)
        XCTAssertEqual(model.acknowledgedBinding?.clientRevision, 3)
        XCTAssertEqual(model.acknowledgedBinding?.ownerUID, "reader_A")
    }

    func testRevocationDuringRetainPreventsOldWriteAndPreservesNewOwner() async throws {
        let f = BindingFixture()
        var held: CheckedContinuation<Void, Never>?
        var first = true
        let model = f.model(retain: { binding, original, lease in
            if first { first = false; await withCheckedContinuation { held = $0 } }
            return try await f.vault.acknowledge(binding, original: original, lease: lease)
        })
        let old = Task { await model.update(f.intent()) }
        await wait { held != nil }
        await model.update(f.intent(context: .authenticated(uid: "reader_B", epoch: UUID())))
        let before = try await f.vault.readExisting(), writes = f.store.writes
        held?.resume(); held = nil; await old.value
        await Task.yield()
        let after = try await f.vault.readExisting()
        XCTAssertEqual(after, before); XCTAssertEqual(f.store.writes, writes)
        XCTAssertEqual(model.acknowledgedBinding?.ownerUID, "reader_B")
    }

    func testTimeoutRevokesPendingRetainWithoutClaimingUndoOrCurrentACK() async throws {
        let f = BindingFixture(); var held: CheckedContinuation<Void, Never>?
        var physicalReturned = false
        let model = f.model(retain: { binding, original, lease in
            await withCheckedContinuation { held = $0 }
            defer { physicalReturned = true }
            return try await f.vault.acknowledge(binding, original: original, lease: lease)
        })
        let update = Task { await model.update(f.intent()) }
        await wait { held != nil }
        f.timeouts.last?(); await update.value
        XCTAssertFalse(physicalReturned)
        XCTAssertEqual(model.state, .blocked(.storage)); XCTAssertNil(model.acknowledgedBinding)
        held?.resume(); held = nil
        await wait { physicalReturned }
        let stored = try await f.vault.readExisting()
        XCTAssertNil(stored?.acknowledgedBinding); XCTAssertEqual(f.store.writes, 1)
    }

    func testTimeoutRevokesLeaseBeforeDeadlineCancellationHookCanReenter() async throws {
        let f = BindingFixture(); var held: CheckedContinuation<Void, Never>?
        var captured: PushRegistrationBindingLease?
        var finished = false; var hookCalls = 0
        let model = f.model(retain: { binding, original, lease in
            captured = lease
            await withCheckedContinuation { held = $0 }
            defer { finished = true }
            return try await f.vault.acknowledge(binding, original: original, lease: lease)
        })
        let update = Task { await model.update(f.intent()) }
        await wait { held != nil }
        f.cancelHook = {
            hookCalls += 1
            XCTAssertFalse(captured?.isValid ?? true)
            held?.resume(); held = nil
        }
        f.timeouts.last?(); await update.value; await wait { finished }
        XCTAssertEqual(hookCalls, 1)
        XCTAssertEqual(model.state, .blocked(.storage))
        let stored = try await f.vault.readExisting()
        XCTAssertNil(stored?.acknowledgedBinding)
    }

    func testStorageReadbackFailureCannotPublishCurrentBinding() async throws {
        let f = BindingFixture()
        let model = f.model(retain: { _, original, _ in original })
        await model.update(f.intent())
        XCTAssertEqual(model.state, .blocked(.storage)); XCTAssertNil(model.acknowledgedBinding)
        let stored = try await f.vault.readExisting()
        XCTAssertNil(stored?.acknowledgedBinding)
    }

    func testDisposeDuringRetainRevokesLeaseBeforeOldWorkCanWrite() async throws {
        let f = BindingFixture(); var held: CheckedContinuation<Void, Never>?
        var finished = false
        let model = f.model(retain: { binding, original, lease in
            await withCheckedContinuation { held = $0 }
            defer { finished = true }
            return try await f.vault.acknowledge(binding, original: original, lease: lease)
        })
        let update = Task { await model.update(f.intent()) }
        await wait { held != nil }; model.dispose(); await update.value
        held?.resume(); held = nil; await wait { finished }
        let stored = try await f.vault.readExisting()
        XCTAssertEqual(model.state, .idle); XCTAssertNil(stored?.acknowledgedBinding)
    }

    func testStoredAcknowledgementSurvivesLogicalVaultReconstructionWithoutGeneration() async throws {
        let f = BindingFixture(); let model = f.model()
        await model.update(f.intent())
        let original = try await f.vault.readExisting(), bytes = f.store.bytes, writes = f.store.writes
        let restarted = PushInstallationVault(store: f.store, makeIdentity: { throw PushInstallationVaultError.identityGenerationFailed })
        let recovered = try await restarted.readExisting()
        XCTAssertEqual(recovered, original); XCTAssertEqual(f.store.bytes, bytes); XCTAssertEqual(f.store.writes, writes)
        // Historical ACK only; constructing a new model does not confer current authority.
        let next = f.model(); XCTAssertNil(next.acknowledgedBinding)
    }

    private func wait(_ ready: () -> Bool, file: StaticString = #filePath, line: UInt = #line) async {
        for _ in 0..<1000 { if ready() { return }; await Task.yield() }
        XCTFail("Local continuation did not arrive", file: file, line: line)
    }
}

private final class BindingStore: @unchecked Sendable, PushInstallationRecordStore {
    private let lock = NSLock()
    private var value: Data?
    private var count = 0
    var bytes: Data? { lock.lock(); defer { lock.unlock() }; return value }
    var writes: Int { lock.lock(); defer { lock.unlock() }; return count }
    func transaction(_ update: (Data?) throws -> Data) throws -> Data {
        lock.lock(); defer { lock.unlock() }
        let next = try update(value)
        if next != value { value = next; count += 1 }
        return next
    }
}

@MainActor
private final class BindingFixture {
    let store = BindingStore()
    let iid = "11111111-1111-4111-8111-111111111111"
    let app = "1:123456789:ios:abcdef123456"
    let context = PushAccountContext.authenticated(uid: "reader_A", epoch: UUID())
    let challenge = String(repeating: "a", count: 64)
    lazy var vault = PushInstallationVault(store: store, makeIdentity: {
        ("11111111-1111-4111-8111-111111111111", String(repeating: "K", count: 64))
    })
    var includeBinding = true
    var holdRegister = false
    var heldResponse: CheckedContinuation<(Data, HTTPURLResponse), Never>?
    var heldValue: (Data, HTTPURLResponse)?
    var headers: [String?] = []
    var timeouts: [() -> Void] = []
    var cancelHook: (() -> Void)?
    var mutate: ((inout [String: Any]) -> Void)?

    func intent(context: PushAccountContext? = nil, token: String? = nil) -> PushRegistrationIntent {
        .init(context: context ?? self.context, permission: true,
              preferences: .init(articles: .all, categoryIds: [], podcasts: false), token: token ?? String(repeating: "T", count: 60))
    }
    func challengePayload() -> [String: String] {
        ["type": "verify_push_installation", "installation_id": iid, "client_revision": "1",
         "challenge_id": challenge, "nonce": String(repeating: "N", count: 64)]
    }
    func finishHeld() {
        let continuation = heldResponse; heldResponse = nil
        continuation?.resume(returning: heldValue!); heldValue = nil
    }
    func model(configured: Bool = true, retain: PushRegistrationModel.RetainBinding? = nil) -> PushRegistrationModel {
        let holder = BindingModelHolder()
        let transport = try! PushRegistrationHTTPTransport(
            registerURL: URL(string: "https://push.example.test/register")!,
            confirmURL: URL(string: "https://push.example.test/confirm")!, expectedAppID: configured ? app : nil,
            credentials: { context in .init(appCheckToken: "local-app", idToken: context.ownerUID == nil ? nil : "local-user", ownerUID: context.ownerUID) },
            isCurrent: { holder.model?.isCurrent($0) == true }, perform: { [self] request in
                headers.append(request.value(forHTTPHeaderField: "X-Apropos-Push-Binding"))
                let body = try JSONSerialization.jsonObject(with: request.httpBody!) as! [String: Any]
                let isRegister = request.url!.path == "/register"
                let revision = body["clientRevision"] as? Int64 ?? holder.model!.clientRevision!
                let status = isRegister ? "pending" : "active"
                var response: [String: Any] = ["status": status, "installationId": iid, "clientRevision": revision]
                if isRegister { response["challengeId"] = challenge } else { response["revision"] = 31 }
                if includeBinding {
                    // Credentials are represented by a local header only. Capture the exact
                    // model ticket via send below rather than infer owner from current auth.
                    var binding: [String: Any] = ["schemaVersion": 1, "installationId": iid, "appId": app,
                        "ownerUID": sendingOwner.map { $0 as Any } ?? NSNull(), "ownerEpoch": 7, "revision": 31,
                        "clientRevision": revision, "status": status]
                    mutate?(&binding); response["binding"] = binding
                }
                let data = try JSONSerialization.data(withJSONObject: response)
                let http = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"])!
                if isRegister && holdRegister && heldResponse == nil {
                    heldValue = (data, http)
                    return await withCheckedContinuation { heldResponse = $0 }
                }
                return (data, http)
            })
        let send: PushRegistrationModel.Send = { [self] call, ticket in
            sendingOwner = ticket.context.ownerUID
            return try await transport.send(call, ticket: ticket)
        }
        let schedule: PushRegistrationDeadline.Schedule = { [self] action in
            timeouts.append(action); return { [weak self] in self?.cancelHook?() }
        }
        let model: PushRegistrationModel
        if configured, let retain {
            model = PushRegistrationModel(prepare: { [self] hash, date, force in try await vault.prepare(intentHash: hash, at: date, forceNewRevision: force) },
                send: send, expectedAppID: app, retainBinding: retain, now: { Date(timeIntervalSince1970: 1000) }, schedule: schedule)
        } else if configured {
            model = PushRegistrationModel(vault: vault, expectedAppID: app, send: send, now: { Date(timeIntervalSince1970: 1000) }, schedule: schedule)
        } else {
            model = PushRegistrationModel(prepare: { [self] hash, date, force in try await vault.prepare(intentHash: hash, at: date, forceNewRevision: force) },
                send: send, now: { Date(timeIntervalSince1970: 1000) }, schedule: schedule)
        }
        holder.model = model
        return model
    }
    private var sendingOwner: String?
}

@MainActor
private final class BindingModelHolder { weak var model: PushRegistrationModel? }
