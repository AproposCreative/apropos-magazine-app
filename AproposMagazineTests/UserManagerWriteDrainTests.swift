import Combine
import FirebaseCore
import FirebaseFirestore
import XCTest
@testable import Apropos

/// Actual UserManager -> profile coordinator -> writer runtime. Only identity,
/// profile reads and physical Firestore callbacks are local; no SDK is started.
@MainActor
final class UserManagerWriteDrainTests: XCTestCase {
    private enum Failure: Error { case offline }

    @MainActor private final class Fixture {
        struct Merge {
            let uid: String
            let fields: [String: Any]
            let stillCurrent: UserManager.Guard
            var completion: ReaderWriterDrainRuntime.Completion?
        }
        let state = UserProfileState()
        let canonical = CanonicalSessionState()
        let events = PassthroughSubject<Void, Never>()
        var uid: String? = "A"
        var permitted = true
        var missingProfile = false
        var reads = 0, legacyWrites = 0, runtimeEntries = 0, runtimeReturns = 0
        var identityReads = 0, references = 0, drainFactories = 0
        var outcomes: [Bool] = []
        var fcm: [String] = []
        var merges: [Merge] = []
        var documents: [String: [String: Any]] = ["A": [
            "bookmarkedArticles": ["existing-bookmark"],
            "researchAccess": ["editor": true], "unrelatedField": "keep"
        ]]
        var deadlines: [@MainActor () -> Void] = []
        var drains: [ReaderWriterDrainRuntime.Completion?] = []
        var onRuntimeIdentity: (@MainActor () -> Void)?
        var beforeReference: (@MainActor () -> Void)?
        var beforeEnqueue: (@MainActor () -> Void)?
        var observedReservedSlot = false
        private var observation: AnyCancellable?

        lazy var runtime = ReaderWriterDrainRuntime(canonical: canonical, actualUID: { [weak self] in
            guard let self else { return nil }
            self.identityReads += 1
            self.onRuntimeIdentity?()
            return self.uid
        }, schedule: { [weak self] action in
            self?.deadlines.append(action); self?.events.send()
            return {}
        }, makeDrain: { [weak self] in
            guard let self else { throw CancellationError() }
            self.drainFactories += 1
            return .init(wait: { [weak self] completion in
                self?.drains.append(completion); self?.events.send()
            })
        })

        lazy var manager = UserManager(state: state, effects: profileEffects,
            currentProfileSeed: { [weak self] in self?.uid.map { Self.profile($0) } },
            profileWriteEffects: .init(performWrite: { [weak self] uid, original, start in
                guard let self else { throw CancellationError() }
                self.runtimeEntries += 1
                do {
                    try await self.runtime.performWrite(expectedUserID: uid, stillCurrent: original, start: start)
                    self.outcomes.append(true); self.runtimeReturns += 1; self.events.send()
                } catch {
                    self.outcomes.append(false); self.runtimeReturns += 1; self.events.send()
                    throw error
                }
            }, merge: { [weak self] uid, fields, admitted, completion in
                guard let self else { completion(CancellationError()); return }
                self.observedReservedSlot = !self.runtime.isPhysicallyIdle
                self.beforeReference?()
                guard admitted() else { completion(CancellationError()); return }
                self.references += 1
                self.beforeEnqueue?()
                guard admitted() else { completion(CancellationError()); return }
                self.merges.append(.init(uid: uid, fields: fields, stillCurrent: admitted, completion: completion))
                self.events.send()
            }))

        private var profileEffects: UserProfileCoordinator.Effects {
            .init(capturePermission: { [weak self] in
                guard let self, self.permitted else { return nil }
                let original = self.canonical.contextTicket()
                return { [weak self] in
                    guard let self else { return false }
                    return self.permitted && self.canonical.isCurrent(original)
                }
            }, identity: { [weak self] in
                .init(actualUID: self?.uid, canonicalUID: self?.canonical.snapshot.userID)
            }, read: { [weak self] seed, source, _, original in
                guard let self, original() else { throw CancellationError() }
                self.reads += 1
                if self.missingProfile { return .init(profile: nil, isFromCache: source == .standard) }
                return .init(profile: seed, isFromCache: false)
            }, write: { [weak self] _, _, _ in
                self?.legacyWrites += 1
                XCTFail("The new complete composition must use the actual writer runtime seam")
                throw Failure.offline
            }, subscribe: { _, _ in }, unsubscribe: { _, _ in }, updateFCM: { [weak self] uid, original in
                if original() { self?.fcm.append(uid); self?.events.send() }
            })
        }

        init() {
            _ = canonical.adopt(Self.session("A"))
            observation = state.changes.sink { [weak self] _ in self?.events.send() }
        }
        static func session(_ uid: String) -> ReaderAccountSession {
            .init(uid: uid, email: uid + "@example.invalid", isEmailVerified: true)
        }
        static func profile(_ uid: String = "A", name: String = "Original") -> UserProfile {
            .init(uid: uid, email: uid + "@example.invalid", displayName: name, photoURL: "https://example.invalid/avatar.png",
                createdAt: Date(timeIntervalSince1970: 1_700_000_000), lastLoginAt: Date(timeIntervalSince1970: 1_700_000_100),
                favoriteCategories: ["culture"], favoriteAuthors: ["author"],
                notificationPreferences: .init(), readingPreferences: .init(),
                readArticles: ["read"], bookmarkedArticles: ["must-not-overwrite-mirror"], readingProgress: ["read": 0.5])
        }
        func start() {
            manager.changeAccountContext(userID: uid)
            manager.startObservingSession()
        }
        func load(name: String = "Original") async {
            manager.loadUserProfile(Self.profile(uid ?? "A", name: name))
            await wait("Profile loaded") { self.state.snapshot.loaded }
        }
        func select(_ next: String?) {
            uid = next
            _ = canonical.adopt(next.map(Self.session))
            manager.changeAccountContext(userID: next)
        }
        func finishMerge(_ index: Int, error: Error? = nil) {
            guard merges.indices.contains(index), let callback = merges[index].completion else {
                XCTFail("Missing physical profile callback"); return
            }
            merges[index].completion = nil
            if error == nil {
                let write = merges[index]
                documents[write.uid, default: [:]].merge(write.fields) { _, new in new }
            }
            callback(error)
        }
        func finishDrain(_ index: Int, error: Error? = nil) {
            guard drains.indices.contains(index), let callback = drains[index] else {
                XCTFail("Missing physical drain callback"); return
            }
            drains[index] = nil; callback(error)
        }
        func wait(_ description: String, file: StaticString = #filePath, line: UInt = #line,
                  _ predicate: @escaping @MainActor () -> Bool) async {
            if predicate() { return }
            let ready = XCTestExpectation(description: description)
            var finished = false
            let observation = events.sink {
                if !finished && predicate() { finished = true; ready.fulfill() }
            }
            let result = await XCTWaiter.fulfillment(of: [ready], timeout: 3)
            withExtendedLifetime(observation) {}
            XCTAssertEqual(result, .completed, file: file, line: line)
        }
        func close() {
            onRuntimeIdentity = nil; beforeReference = nil; beforeEnqueue = nil
            manager.suspendForAccountChange()
            for index in merges.indices where merges[index].completion != nil { finishMerge(index, error: Failure.offline) }
            for index in drains.indices where drains[index] != nil { finishDrain(index, error: Failure.offline) }
        }
    }

    override func setUp() { super.setUp(); XCTAssertNil(FirebaseApp.allApps) }
    override func tearDown() { XCTAssertNil(FirebaseApp.allApps); super.tearDown() }

    func testConstructionIsInertAndCompleteInjectionNeverUsesLegacyWrite() {
        let f = Fixture(); defer { f.close() }
        _ = f.manager; _ = f.runtime
        XCTAssertEqual(f.reads, 0); XCTAssertEqual(f.identityReads, 0)
        XCTAssertEqual(f.runtimeEntries, 0); XCTAssertEqual(f.references, 0)
        XCTAssertEqual(f.drainFactories, 0); XCTAssertTrue(f.deadlines.isEmpty)
        XCTAssertEqual(f.legacyWrites, 0)
    }

    func testProfileMergeHoldsRealCallbackAndPreservesBookmarkAndResearchFields() async throws {
        let f = Fixture(); defer { f.close() }; f.start(); await f.load()
        let baselineFCM = f.fcm.count
        let ticket = try XCTUnwrap(f.manager.saveUserProfile(Fixture.profile(name: "Updated")))
        await f.wait("Physical merge") { f.merges.count == 1 }
        XCTAssertTrue(f.observedReservedSlot); XCTAssertFalse(f.runtime.isPhysicallyIdle)
        XCTAssertEqual(f.runtimeReturns, 0); XCTAssertEqual(f.fcm.count, baselineFCM)
        let fields = f.merges[0].fields
        XCTAssertEqual(Set(fields.keys), Set(["uid", "email", "displayName", "photoURL", "createdAt", "lastLoginAt",
            "favoriteCategories", "favoriteAuthors", "readArticles", "readingProgress", "notificationPreferences", "readingPreferences"]))
        XCTAssertEqual(fields["uid"] as? String, "A")
        XCTAssertEqual(fields["displayName"] as? String, "Updated")
        XCTAssertEqual((fields["createdAt"] as? Timestamp)?.dateValue(), Fixture.profile().createdAt)
        XCTAssertEqual(fields["readingProgress"] as? [String: Double], ["read": 0.5])
        XCTAssertNil(fields["bookmarkedArticles"])
        f.finishMerge(0)
        await f.wait("Successful profile receipt") { f.runtimeReturns == 1 && f.fcm.count == baselineFCM + 1 }
        XCTAssertEqual(f.outcomes, [true]); XCTAssertTrue(f.manager.isCurrent(ticket))
        XCTAssertNil(f.manager.errorMessage); XCTAssertTrue(f.runtime.isPhysicallyIdle)
        XCTAssertEqual(f.documents["A"]?["bookmarkedArticles"] as? [String], ["existing-bookmark"])
        XCTAssertEqual(f.documents["A"]?["researchAccess"] as? [String: Bool], ["editor": true])
        XCTAssertEqual(f.documents["A"]?["unrelatedField"] as? String, "keep")
        XCTAssertEqual(f.legacyWrites, 0)
    }

    func testPhysicalFailurePublishesErrorAndExplicitNewSaveCanRetry() async throws {
        let f = Fixture(); defer { f.close() }; f.start(); await f.load()
        let baselineFCM = f.fcm.count
        XCTAssertNotNil(f.manager.saveUserProfile(Fixture.profile(name: "First")))
        await f.wait("First merge") { f.merges.count == 1 }
        f.finishMerge(0, error: Failure.offline)
        await f.wait("Profile save error") { f.manager.errorMessage != nil }
        XCTAssertEqual(f.outcomes, [false]); XCTAssertTrue(f.runtime.isPhysicallyIdle)
        XCTAssertEqual(f.fcm.count, baselineFCM)
        XCTAssertNotNil(f.manager.saveUserProfile(Fixture.profile(name: "Retry")))
        await f.wait("Retry merge") { f.merges.count == 2 }
        f.finishMerge(1)
        await f.wait("Retry accepted") { f.runtimeReturns == 2 && f.fcm.count == baselineFCM + 1 }
        XCTAssertNil(f.manager.errorMessage); XCTAssertEqual(f.outcomes, [false, true])
    }

    func testStoppedRuntimeRejectsBeforeAnyProfileReference() async throws {
        let f = Fixture(); defer { f.close() }; f.start(); await f.load()
        _ = try XCTUnwrap(f.runtime.stopWrites(context: f.canonical.contextTicket()))
        XCTAssertNotNil(f.manager.saveUserProfile(Fixture.profile(name: "Blocked")))
        await f.wait("Stopped profile returns") { f.runtimeReturns == 1 }
        XCTAssertEqual(f.references, 0); XCTAssertTrue(f.merges.isEmpty)
        XCTAssertEqual(f.outcomes, [false]); XCTAssertTrue(f.runtime.isPhysicallyIdle)
    }

    func testReentrantStopFromRuntimeIdentityNeverStartsSDKAdapter() async throws {
        let f = Fixture(); defer { f.close() }; f.start(); await f.load()
        f.onRuntimeIdentity = {
            f.onRuntimeIdentity = nil
            XCTAssertNotNil(f.runtime.stopWrites(context: f.canonical.contextTicket()))
        }
        XCTAssertNotNil(f.manager.saveUserProfile(Fixture.profile(name: "Blocked")))
        await f.wait("Reentrant admission returns") { f.runtimeReturns == 1 }
        XCTAssertEqual(f.references, 0); XCTAssertTrue(f.merges.isEmpty)
        XCTAssertFalse(f.observedReservedSlot, "The SDK adapter must not run after identity-hook stop")
        XCTAssertTrue(f.runtime.isPhysicallyIdle)
    }

    func testStopDuringReferencePreparationRefusesEnqueueAndReleasesUnstartedSlot() async throws {
        let f = Fixture(); defer { f.close() }; f.start(); await f.load()
        f.beforeReference = {
            f.beforeReference = nil
            XCTAssertNotNil(f.runtime.stopWrites(context: f.canonical.contextTicket()))
        }
        XCTAssertNotNil(f.manager.saveUserProfile(Fixture.profile(name: "Blocked")))
        await f.wait("Reference admission rejects") { f.runtimeReturns == 1 }
        XCTAssertTrue(f.observedReservedSlot); XCTAssertEqual(f.references, 0)
        XCTAssertTrue(f.merges.isEmpty); XCTAssertTrue(f.runtime.isPhysicallyIdle)
    }

    func testStopAfterReferencePreparationStillRefusesPhysicalEnqueue() async throws {
        let f = Fixture(); defer { f.close() }; f.start(); await f.load()
        f.beforeEnqueue = {
            f.beforeEnqueue = nil
            XCTAssertNotNil(f.runtime.stopWrites(context: f.canonical.contextTicket()))
        }
        XCTAssertNotNil(f.manager.saveUserProfile(Fixture.profile(name: "Blocked")))
        await f.wait("Final SDK guard rejects") { f.runtimeReturns == 1 }
        XCTAssertEqual(f.references, 1); XCTAssertTrue(f.merges.isEmpty)
        XCTAssertTrue(f.runtime.isPhysicallyIdle)
    }

    func testAdmittedProfileCanFinishAfterStopAndDrainWaitsForPhysicalCallback() async throws {
        let f = Fixture(); defer { f.close() }; f.start(); await f.load()
        let baselineFCM = f.fcm.count
        let ticket = try XCTUnwrap(f.manager.saveUserProfile(Fixture.profile(name: "Admitted")))
        await f.wait("Held merge") { f.merges.count == 1 }
        let stop = try XCTUnwrap(f.runtime.stopWrites(context: f.canonical.contextTicket()))
        let drain = Task { try await f.runtime.drain(stop) }
        await f.wait("Drain queued") { f.deadlines.count == 1 }
        XCTAssertEqual(f.drainFactories, 0); XCTAssertEqual(f.runtimeReturns, 0)
        f.finishMerge(0)
        await f.wait("Actual SDK wait begins") { f.drains.count == 1 }
        await f.wait("Profile receipt accepted") { f.runtimeReturns == 1 && f.fcm.count == baselineFCM + 1 }
        XCTAssertEqual(f.outcomes, [true]); XCTAssertTrue(f.manager.isCurrent(ticket))
        f.finishDrain(0)
        let receipt = try await drain.value
        XCTAssertTrue(f.runtime.isCurrent(receipt)); XCTAssertTrue(f.runtime.isPhysicallyIdle)
    }

    func testDrainTimeoutDoesNotFreeHeldProfileOrAllowAnotherSave() async throws {
        let f = Fixture(); defer { f.close() }; f.start(); await f.load()
        XCTAssertNotNil(f.manager.saveUserProfile(Fixture.profile(name: "Held")))
        await f.wait("Held merge") { f.merges.count == 1 }
        let stop = try XCTUnwrap(f.runtime.stopWrites(context: f.canonical.contextTicket()))
        let drain = Task { try await f.runtime.drain(stop) }
        await f.wait("Drain deadline installed") { f.deadlines.count == 1 }
        try XCTUnwrap(f.deadlines.first)()
        do { _ = try await drain.value; XCTFail("Deadline must end presentation") }
        catch { XCTAssertEqual(error as? ReaderWriterDrainCoordinator.Failure, .timedOut) }
        XCTAssertFalse(f.runtime.isPhysicallyIdle); XCTAssertEqual(f.runtimeReturns, 0)
        XCTAssertEqual(f.drainFactories, 0)
        XCTAssertNotNil(f.manager.saveUserProfile(Fixture.profile(name: "Queued")))
        XCTAssertEqual(f.merges.count, 1)
        f.finishMerge(0)
        await f.wait("Both original and queued saves return") { f.runtimeReturns == 2 }
        XCTAssertTrue(f.runtime.isPhysicallyIdle); XCTAssertEqual(f.merges.count, 1)
        XCTAssertEqual(f.drainFactories, 0)
    }

    func testCancelledDrainCannotReleaseHeldProfilePhysicalSlot() async throws {
        let f = Fixture(); defer { f.close() }; f.start(); await f.load()
        XCTAssertNotNil(f.manager.saveUserProfile(Fixture.profile(name: "Held")))
        await f.wait("Held merge") { f.merges.count == 1 }
        let stop = try XCTUnwrap(f.runtime.stopWrites(context: f.canonical.contextTicket()))
        let drain = Task { try await f.runtime.drain(stop) }
        await f.wait("Drain deadline installed") { f.deadlines.count == 1 }
        drain.cancel()
        do { _ = try await drain.value; XCTFail("Cancelled drain must not return a receipt") }
        catch { XCTAssertEqual(error as? ReaderWriterDrainCoordinator.Failure, .cancelled) }
        XCTAssertFalse(f.runtime.isPhysicallyIdle); XCTAssertEqual(f.runtimeReturns, 0)
        f.finishMerge(0)
        await f.wait("Original callback returned") { f.runtimeReturns == 1 }
        XCTAssertTrue(f.runtime.isPhysicallyIdle); XCTAssertEqual(f.drainFactories, 0)
    }

    func testAccountABARetainsOldPhysicalSlotAndCannotPublishOldSuccess() async throws {
        let f = Fixture(); defer { f.close() }; f.start(); await f.load()
        let oldTicket = try XCTUnwrap(f.manager.saveUserProfile(Fixture.profile(name: "Old A")))
        await f.wait("Old A merge") { f.merges.count == 1 }
        f.select(nil); f.select("A"); await f.load(name: "New A")
        let baselineFCM = f.fcm.count
        XCTAssertNotNil(f.manager.saveUserProfile(Fixture.profile(name: "Newest A")))
        XCTAssertFalse(f.manager.isCurrent(oldTicket)); XCTAssertEqual(f.merges.count, 1)
        XCTAssertEqual(f.runtimeEntries, 1); XCTAssertFalse(f.runtime.isPhysicallyIdle)
        f.finishMerge(0)
        await f.wait("New A may start after old physical return") { f.merges.count == 2 }
        XCTAssertEqual(f.outcomes, [false]); XCTAssertEqual(f.fcm.count, baselineFCM)
        XCTAssertEqual(f.manager.currentUser?.displayName, "Newest A")
        XCTAssertEqual(f.merges[1].fields["displayName"] as? String, "Newest A")
        f.finishMerge(1)
        await f.wait("New A receipt") { f.runtimeReturns == 2 && f.fcm.count == baselineFCM + 1 }
        XCTAssertEqual(f.outcomes, [false, true])
    }

    func testStartupDenialAfterEnqueueCannotReviveOldCompletion() async throws {
        let f = Fixture(); defer { f.close() }; f.start(); await f.load()
        let baselineFCM = f.fcm.count
        XCTAssertNotNil(f.manager.saveUserProfile(Fixture.profile(name: "Old")))
        await f.wait("Held merge") { f.merges.count == 1 }
        f.permitted = false
        XCTAssertFalse(f.merges[0].stillCurrent())
        f.permitted = true
        f.finishMerge(0)
        await f.wait("Denied original returns") { f.runtimeReturns == 1 }
        XCTAssertEqual(f.outcomes, [false]); XCTAssertEqual(f.fcm.count, baselineFCM)
        XCTAssertNotNil(f.manager.saveUserProfile(Fixture.profile(name: "Explicit retry")))
        await f.wait("Fresh save") { f.merges.count == 2 }
        f.finishMerge(1)
        await f.wait("Fresh receipt") { f.runtimeReturns == 2 && f.fcm.count == baselineFCM + 1 }
        XCTAssertEqual(f.outcomes, [false, true])
    }

    func testConfirmedMissingProfileAutocreateUsesSamePhysicalBarrierAndMergeProjection() async throws {
        let f = Fixture(); defer { f.close() }; f.missingProfile = true; f.start()
        await f.load(name: "New reader")
        await f.wait("Default profile physical merge") { f.merges.count == 1 }
        XCTAssertEqual(f.reads, 2, "Cached absence alone must not autocreate")
        XCTAssertEqual(f.runtimeEntries, 1); XCTAssertTrue(f.observedReservedSlot)
        XCTAssertEqual(f.merges[0].uid, "A")
        XCTAssertNil(f.merges[0].fields["bookmarkedArticles"])
        XCTAssertTrue(f.fcm.isEmpty)
        f.finishMerge(0)
        await f.wait("Default profile completion") { f.runtimeReturns == 1 && f.fcm.count == 1 }
        XCTAssertEqual(f.outcomes, [true]); XCTAssertEqual(f.legacyWrites, 0)
        XCTAssertEqual(f.documents["A"]?["researchAccess"] as? [String: Bool], ["editor": true])
    }
}
