import Combine
import FirebaseCore
import XCTest
@testable import Apropos

/// Actual Auth/bootstrap/recovery with local introduction storage. The normal
/// reader publication is injected; no Firebase or provider service is started.
@MainActor
final class ReaderIntroductionRecoveryIntegrationTests: XCTestCase {
    @MainActor private final class Memory {
        var data: Data?
        var reads = 0, writes = 0
        var failWrite = false
        var onRead: (@MainActor () -> Void)?
        var onWrite: (@MainActor () -> Void)?
        var storage: ReaderIntroductionStorage {
            .init(read: { [self] in reads += 1; onRead?(); return data }, write: { [self] in
                writes += 1; onWrite?()
                if failWrite { throw CocoaError(.fileWriteUnknown) }
                data = $0
            })
        }
        func seed(owner: String?, topics: [String]) {
            let canonical = CanonicalSessionState()
            _ = canonical.adopt(owner.map { ReaderAccountSession(uid: $0, email: "seed@example.invalid", isEmailVerified: true) })
            let model = ReaderIntroductionModel(storage: storage)
            XCTAssertTrue(model.bindContext(canonical.contextTicket(), isCurrent: canonical.isCurrent))
            XCTAssertTrue(model.start())
            XCTAssertTrue(model.setSelectedTopicIDs(topics))
        }
    }
    @MainActor private final class Fixture {
        let directory: URL
        let recovery: ReaderTransitionRecovery
        let startup: ReaderSDKStartupState
        let auth: AuthService
        let memory = Memory(), guestMemory = Memory()
        var actualUID: String?
        var prepared = 0, publications = 0
        lazy var intro = ReaderIntroductionModel(storage: memory.storage, recovery: recovery)
        lazy var operations = AuthOperationCoordinator(canonical: auth.state, actualUserID: { [unowned self] in actualUID })
        lazy var delegate = AppDelegate(startup: startup, identity: auth.bootstrapIdentity,
            actualUserID: { [unowned self] in actualUID })
        init(directory: URL? = nil, unavailable: Bool = false) {
            self.directory = directory ?? FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            recovery = ReaderTransitionRecovery(store: .init(rootDirectory: unavailable ? nil : self.directory))
            startup = ReaderSDKStartupState(legacyRecovery: recovery)
            auth = AuthService(startup: startup)
        }
        @discardableResult func observe(_ uid: String?) -> ReaderAccountSession? {
            actualUID = uid
            let user = uid.map { ReaderAccountSession(uid: $0, email: "reader@example.invalid", isEmailVerified: true) }
            _ = auth.observeIdentity(user, currentUserID: { [unowned self] in actualUID },
                revokeReader: { [unowned self] in auth.state.suspend(stillPermitted: $0) != nil },
                publishReader: { [unowned self] allowed in
                    let accepted = auth.state.adopt(user, stillPermitted: allowed)
                    if accepted != nil { publications += 1 }
                    return accepted
                })
            return user
        }
        func launch(_ uid: String? = "reader-A") async throws {
            _ = intro // Inert construction before marker bootstrap.
            let task = delegate.runAccountStartup(authOnly: {}, readerSteps: [{ [unowned self] in prepared += 1 }],
                observeAuth: { [unowned self] in _ = observe(uid) },
                releaseReader: { [unowned self] in _ = auth.resumeReaderAfterLocalRecovery() })
            let started = try XCTUnwrap(task)
            await started.value
        }
        func bindAndStart() {
            XCTAssertTrue(intro.bindContext(auth.state.contextTicket(), isCurrent: auth.state.isCurrent))
            XCTAssertTrue(intro.start())
        }
        func seal() async throws { _ = try await recovery.seal(binding: .init(ownerUID: "reader-A", epoch: 1)) }
        /// Local last-hook test seam only; actual seal paths above/below use the
        /// disk-backed recovery. This does not create a durable deletion proof.
        func closeAtHook(notify: Bool = true) {
            recovery.admission.setAllowed(false)
            if notify { recovery.changes.send() }
        }
        func cleanup() { try? FileManager.default.removeItem(at: directory) }
        func providerResult(isNew: Bool) async throws -> (ReaderIntroductionModel.AccountEntryTicket, ReaderLoginResult) {
            let operation = try operations.capture(.emailSignIn)
            let entry = try XCTUnwrap(intro.beginAccountEntry(actionID: operation.actionID))
            let user = try await operations.exchange(operation) { [unowned self] in
                let user = try XCTUnwrap(observe("reader-A"))
                XCTAssertTrue(intro.bindContext(auth.state.contextTicket(), isCurrent: auth.state.isCurrent))
                XCTAssertTrue(operations.acceptResult(operation, context: auth.state.contextTicket(), isNewUser: isNew))
                return user
            }
            return (entry, try XCTUnwrap(operations.acceptedLoginResult(operation, session: user)))
        }
    }

    override func setUp() { super.setUp(); XCTAssertNil(FirebaseApp.allApps) }
    override func tearDown() { XCTAssertNil(FirebaseApp.allApps); super.tearDown() }

    func testActualSealKeepsCanonicalAccountButRejectsOriginalIntroductionWrites() async throws {
        XCTAssertNil(FirebaseApp.allApps)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let recovery = ReaderTransitionRecovery(store: .init(rootDirectory: directory))
        let startup = ReaderSDKStartupState(legacyRecovery: recovery)
        let auth = AuthService(startup: startup)
        let originalUser = ReaderAccountSession(uid: "reader-A", email: "reader-a@example.invalid", isEmailVerified: true)
        let delegate = AppDelegate(startup: startup, identity: auth.bootstrapIdentity,
            actualUserID: { originalUser.uid })
        var prepared = 0
        let task = delegate.runAccountStartup(authOnly: {}, readerSteps: [{ prepared += 1 }], observeAuth: {
            _ = auth.observeIdentity(originalUser, currentUserID: { originalUser.uid },
                revokeReader: { auth.state.suspend(stillPermitted: $0) != nil },
                publishReader: { auth.state.adopt(originalUser, stillPermitted: $0) })
        }, releaseReader: { _ = auth.resumeReaderAfterLocalRecovery() })
        let launched = try XCTUnwrap(task)
        await launched.value
        XCTAssertEqual(prepared, 1)
        let original = auth.state.contextTicket()
        XCTAssertEqual(original.userID, "reader-A")
        XCTAssertTrue(startup.permitsReaderServices(identity: auth.bootstrapIdentity))

        var data: Data?, writes = 0
        // The unchanged assertions reproduced two writes with canonical A
        // still current, before this model received the shared recovery.
        let intro = ReaderIntroductionModel(storage: .init(read: { data }, write: {
            writes += 1; data = $0
        }), recovery: recovery)
        XCTAssertTrue(intro.bindContext(original, isCurrent: auth.state.isCurrent))
        XCTAssertTrue(intro.start())
        XCTAssertTrue(intro.setSelectedTopicIDs(["music"]))
        let baseline = writes
        _ = try await recovery.seal(binding: .init(ownerUID: "reader-A", epoch: 1))

        // Closing readiness deliberately does not synthesize an Auth logout.
        // A new auth observation would be a different path, absent here.
        XCTAssertFalse(startup.permitsReaderServices(identity: auth.bootstrapIdentity))
        XCTAssertTrue(auth.state.isCurrent(original))
        XCTAssertEqual(auth.state.snapshot.session, originalUser)
        let toggled = intro.toggleTopic("film")
        let replayed = intro.replay()
        let retried = intro.retry()
        XCTAssertEqual(writes - baseline, 0, "The original introduction must not write after actual recovery closure")
        XCTAssertFalse(toggled)
        XCTAssertFalse(replayed)
        XCTAssertFalse(retried)
        XCTAssertFalse(intro.isPresented)
        XCTAssertNil(FirebaseApp.allApps)
    }

    func testColdClosedModelDoesNotReadButFreshBootstrapAdmitsNormalGuest() async throws {
        let f = Fixture(); defer { f.cleanup() }
        XCTAssertFalse(f.intro.permitsIntroduction)
        XCTAssertFalse(f.intro.start())
        XCTAssertFalse(f.intro.replay())
        XCTAssertEqual(f.memory.reads, 0)
        XCTAssertEqual(f.memory.writes, 0)
        try await f.launch(nil)
        XCTAssertEqual(f.auth.state.snapshot.context, .guest)
        f.bindAndStart()
        XCTAssertTrue(f.intro.permitsIntroduction)
        XCTAssertTrue(f.intro.setSelectedTopicIDs(["music"]))
        XCTAssertEqual(f.memory.writes, 1)
        XCTAssertTrue(f.intro.isPresented)
    }

    func testActualColdSealedStartupRetainsDraftWithoutPublishingReaderOrReadingIntroduction() async throws {
        let original = Fixture(); defer { original.cleanup() }
        try await original.recovery.bootstrap(); try await original.seal()
        let f = Fixture(directory: original.directory)
        f.memory.seed(owner: "reader-B", topics: ["film"])
        let before = f.memory.data, reads = f.memory.reads, writes = f.memory.writes
        try await f.launch()
        XCTAssertEqual(f.auth.bootstrapIdentity.snapshot.userID, "reader-A")
        XCTAssertEqual(f.auth.state.snapshot.context, .unresolved)
        XCTAssertEqual(f.prepared, 0)
        XCTAssertEqual(f.publications, 0)
        XCTAssertFalse(f.intro.start())
        XCTAssertFalse(f.intro.bindContext(f.auth.bootstrapIdentity.contextTicket(), isCurrent: f.auth.bootstrapIdentity.isCurrent))
        XCTAssertEqual(f.memory.data, before)
        XCTAssertEqual(f.memory.reads, reads)
        XCTAssertEqual(f.memory.writes, writes)
        XCTAssertFalse(f.intro.isPresented)
    }

    func testUnavailableMarkerLeavesActualAuthOnlyIdentityWithoutIntroductionIO() async throws {
        let f = Fixture(unavailable: true); defer { f.cleanup() }
        try await f.launch()
        XCTAssertEqual(f.recovery.status, .unavailable)
        XCTAssertEqual(f.auth.bootstrapIdentity.snapshot.userID, "reader-A")
        XCTAssertEqual(f.auth.state.snapshot.context, .unresolved)
        XCTAssertFalse(f.intro.start()); XCTAssertFalse(f.intro.retry())
        XCTAssertEqual(f.memory.reads, 0); XCTAssertEqual(f.memory.writes, 0)
        XCTAssertEqual(f.prepared, 0)
    }

    func testActualAcceptedProviderReceiptCannotAdvanceIntroductionAfterSeal() async throws {
        let f = Fixture(); defer { f.cleanup() }; try await f.launch(nil); f.bindAndStart()
        let (entry, result) = try await f.providerResult(isNew: true)
        XCTAssertTrue(f.auth.state.isCurrent(result.acceptedContext))
        let baseline = f.memory.writes
        try await f.seal()
        XCTAssertTrue(f.auth.state.isCurrent(result.acceptedContext))
        XCTAssertFalse(f.intro.acceptLogin(result, ticket: entry))
        f.intro.cancelAccountEntry(entry)
        XCTAssertFalse(f.intro.retry())
        XCTAssertEqual(f.memory.writes, baseline)
        XCTAssertFalse(f.intro.isPresented)
    }

    func testNormalFreshAndReturningProviderReceiptsKeepExistingIntroductionBehaviour() async throws {
        for isNew in [true, false] {
            let f = Fixture(); defer { f.cleanup() }; try await f.launch(nil); f.bindAndStart()
            let (entry, result) = try await f.providerResult(isNew: isNew)
            XCTAssertTrue(f.intro.acceptLogin(result, ticket: entry))
            XCTAssertEqual(f.intro.step, isNew ? .interests : .welcome)
            XCTAssertEqual(f.intro.isCompleted, !isNew)
            XCTAssertEqual(f.intro.isPresented, isNew)
            XCTAssertFalse(f.intro.acceptLogin(result, ticket: entry))
            XCTAssertEqual(f.memory.writes, 1)
        }
    }

    func testSealRetiresFailedOriginalDraftRetryWithoutRewritingStoredSelection() async throws {
        let f = Fixture(); defer { f.cleanup() }; try await f.launch(); f.bindAndStart()
        XCTAssertTrue(f.intro.setSelectedTopicIDs(["music"]))
        let originalData = f.memory.data
        f.memory.failWrite = true
        XCTAssertFalse(f.intro.setSelectedTopicIDs(["film"]))
        XCTAssertNotNil(f.intro.storageError)
        let baseline = f.memory.writes
        try await f.seal()
        f.memory.failWrite = false
        XCTAssertFalse(f.intro.retry())
        XCTAssertEqual(f.memory.writes, baseline)
        XCTAssertEqual(f.memory.data, originalData)
        XCTAssertFalse(f.intro.isPresented)
    }

    func testSealDoesNotOverwriteStoredOtherOwnerOrGuestDraftAndSeparateGuestInterests() async throws {
        let owners: [String?] = ["reader-B", nil]
        for owner in owners {
            let f = Fixture(); defer { f.cleanup() }
            f.memory.seed(owner: owner, topics: ["stored-draft"])
            let guest = CanonicalSessionState(); _ = guest.adopt(nil)
            let interests = GuestReaderInterestsModel(storage: f.guestMemory.storage)
            XCTAssertTrue(interests.start())
            XCTAssertTrue(interests.save(["guest-interest"], context: guest.contextTicket(), isCurrent: guest.isCurrent))
            let draftBytes = f.memory.data, guestBytes = f.guestMemory.data
            let writes = f.memory.writes, guestWrites = f.guestMemory.writes
            try await f.launch(); f.bindAndStart()
            XCTAssertTrue(f.intro.selectedTopicIDs.isEmpty, "A never adopts B/guest selections")
            try await f.seal()
            XCTAssertFalse(f.intro.toggleTopic("new")); XCTAssertFalse(f.intro.replay()); XCTAssertFalse(f.intro.retry())
            XCTAssertEqual(f.memory.data, draftBytes)
            XCTAssertEqual(f.guestMemory.data, guestBytes)
            XCTAssertEqual(f.memory.writes, writes)
            XCTAssertEqual(f.guestMemory.writes, guestWrites)
            XCTAssertEqual(interests.selectedTopicIDs, ["guest-interest"])
        }
    }

    func testClosureDuringOriginalReadRejectsSnapshotAndKeepsDraftBytes() async throws {
        let f = Fixture(); defer { f.cleanup() }
        f.memory.seed(owner: "reader-A", topics: ["music"])
        let original = f.memory.data
        try await f.launch()
        XCTAssertTrue(f.intro.bindContext(f.auth.state.contextTicket(), isCurrent: f.auth.state.isCurrent))
        let baseline = f.memory.writes
        f.memory.onRead = { [unowned f] in f.closeAtHook() }
        XCTAssertFalse(f.intro.start())
        XCTAssertFalse(f.intro.isPresented)
        XCTAssertTrue(f.intro.selectedTopicIDs.isEmpty)
        XCTAssertEqual(f.memory.data, original)
        XCTAssertEqual(f.memory.writes, baseline)
    }

    func testPureAdmissionStopsOriginalActionsBeforeRecoveryObserverDelivery() async throws {
        let f = Fixture(); defer { f.cleanup() }; try await f.launch(); f.bindAndStart()
        XCTAssertTrue(f.intro.setSelectedTopicIDs(["music"]))
        let before = f.memory.data, reads = f.memory.reads, writes = f.memory.writes
        f.closeAtHook(notify: false)
        XCTAssertTrue(f.auth.state.snapshot.userID == "reader-A")
        XCTAssertFalse(f.intro.permitsIntroduction)
        XCTAssertFalse(f.intro.start()); XCTAssertFalse(f.intro.retry())
        XCTAssertFalse(f.intro.toggleTopic("film")); XCTAssertFalse(f.intro.replay())
        XCTAssertFalse(f.intro.complete()); XCTAssertFalse(f.intro.advance())
        XCTAssertNil(f.intro.beginAccountEntry(actionID: UUID()))
        XCTAssertEqual(f.memory.data, before)
        XCTAssertEqual(f.memory.reads, reads); XCTAssertEqual(f.memory.writes, writes)
    }

    func testCurrentContextHookCannotCloseGateAndThenAuthorizeOriginalWrite() async throws {
        let f = Fixture(); defer { f.cleanup() }; try await f.launch()
        let original = f.auth.state.contextTicket()
        var shouldClose = false
        XCTAssertTrue(f.intro.bindContext(original) { [unowned f] context in
            if shouldClose { shouldClose = false; f.closeAtHook() }
            return f.auth.state.isCurrent(context)
        })
        XCTAssertTrue(f.intro.start())
        let baseline = f.memory.writes
        shouldClose = true
        XCTAssertFalse(f.intro.setSelectedTopicIDs(["music"]))
        XCTAssertTrue(f.auth.state.isCurrent(original))
        XCTAssertEqual(f.memory.writes, baseline)
        XCTAssertFalse(f.intro.isPresented)
    }

    func testClosureDuringWritePublicationPreventsStorageAndReentrantAccountAdoption() async throws {
        let f = Fixture(); defer { f.cleanup() }; try await f.launch(); f.bindAndStart()
        let original = f.auth.state.contextTicket()
        var once = false
        let observation = f.intro.objectWillChange.sink { [unowned f] in
            guard !once else { return }; once = true
            f.closeAtHook()
            XCTAssertFalse(f.intro.bindContext(original, isCurrent: f.auth.state.isCurrent))
        }
        let baseline = f.memory.writes
        XCTAssertFalse(f.intro.setSelectedTopicIDs(["music"]))
        XCTAssertEqual(f.memory.writes, baseline)
        XCTAssertFalse(f.intro.isPresented)
        withExtendedLifetime(observation) {}
    }

    func testAlreadyEnteredWriteKeepsOriginalBytesWithoutReadbackOrUIAcknowledgement() async throws {
        let f = Fixture(); defer { f.cleanup() }; try await f.launch(); f.bindAndStart()
        XCTAssertTrue(f.intro.setSelectedTopicIDs(["music"]))
        let before = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(f.memory.data)) as? [String: Any])
        let baseline = f.memory.writes, reads = f.memory.reads
        f.memory.onWrite = { [unowned f] in f.closeAtHook() }
        XCTAssertFalse(f.intro.setSelectedTopicIDs(["film"]))
        let stored = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(f.memory.data)) as? [String: Any])
        XCTAssertEqual(stored["draftOwner"] as? String, before["draftOwner"] as? String)
        XCTAssertEqual(stored["selectedTopicIDs"] as? [String], ["film"])
        XCTAssertEqual(f.memory.writes, baseline + 1)
        XCTAssertEqual(f.memory.reads, reads, "A denied callback cannot initiate a new readback")
        XCTAssertFalse(f.intro.isPresented)
        XCTAssertTrue(f.intro.selectedTopicIDs.isEmpty)
        XCTAssertNil(f.intro.storageError)
    }

    func testAccountRoundTripRejectsOriginalLoginReceiptAndPreservesNewDraft() async throws {
        let f = Fixture(); defer { f.cleanup() }; try await f.launch(nil); f.bindAndStart()
        let (entry, result) = try await f.providerResult(isNew: true)
        f.observe("reader-B")
        XCTAssertTrue(f.intro.bindContext(f.auth.state.contextTicket(), isCurrent: f.auth.state.isCurrent))
        XCTAssertTrue(f.intro.setSelectedTopicIDs(["B-topic"]))
        let otherBytes = f.memory.data
        f.observe("reader-A")
        XCTAssertTrue(f.intro.bindContext(f.auth.state.contextTicket(), isCurrent: f.auth.state.isCurrent))
        XCTAssertFalse(f.auth.state.isCurrent(result.acceptedContext))
        XCTAssertFalse(f.intro.acceptLogin(result, ticket: entry))
        let writes = f.memory.writes
        try await f.seal()
        XCTAssertFalse(f.intro.retry()); XCTAssertFalse(f.intro.setSelectedTopicIDs(["old-A"]))
        XCTAssertEqual(f.memory.writes, writes)
        XCTAssertEqual(f.memory.data, otherBytes)
    }

    func testLaterMissingReadCannotReviveClosedOriginalDraftDespiteCanonicalA() async throws {
        let f = Fixture(); defer { f.cleanup() }; try await f.launch(); f.bindAndStart()
        XCTAssertTrue(f.intro.setSelectedTopicIDs(["music"]))
        let original = f.auth.state.contextTicket(), before = f.memory.data, baseline = f.memory.writes
        try await f.recovery.bootstrap() // A new physical read closes then reopens the local legacy gate.
        XCTAssertTrue(f.recovery.admission.isAllowed)
        XCTAssertTrue(f.auth.state.isCurrent(original))
        XCTAssertFalse(f.intro.permitsIntroduction)
        XCTAssertFalse(f.intro.bindContext(original, isCurrent: f.auth.state.isCurrent))
        XCTAssertFalse(f.intro.start()); XCTAssertFalse(f.intro.replay()); XCTAssertFalse(f.intro.retry())
        XCTAssertEqual(f.memory.writes, baseline)
        XCTAssertEqual(f.memory.data, before)
    }
}
