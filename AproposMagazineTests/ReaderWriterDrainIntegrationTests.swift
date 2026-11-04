import XCTest
@testable import Apropos

/// Actual runtime admission and the existing favorites/preferences pipelines;
/// only the physical SDK callbacks/client factory are replaced. No services,
/// Firebase application, credentials, network or production stores are started.
@MainActor
final class ReaderWriterDrainIntegrationTests: XCTestCase {
    func testConstructionIsInertAndNormalWriteNeedsItsRealCallback() async {
        let h = DrainIntegrationHarness()
        _ = h.runtime
        XCTAssertEqual(h.identityReads, 0)
        XCTAssertEqual(h.factoryCalls, 0)
        XCTAssertTrue(h.deadlines.isEmpty)
        var finished = false
        let task = Task { let ok = await h.write("favorite"); finished = true; return ok }
        await h.waitForWrites(1)
        XCTAssertFalse(finished)
        XCTAssertEqual(h.factoryCalls, 0)
        h.completeWrite(0)
        let ok = await task.value
        XCTAssertTrue(ok)
        XCTAssertTrue(h.drainCallbacks.isEmpty)
    }

    func testWrongOwnerAndExpiredOriginalIntentNeverReachSDKStart() async {
        let h = DrainIntegrationHarness()
        let wrongOwner = await h.write("favorite", uid: "B")
        let stale = await h.write("preferences", stillCurrent: { false })
        XCTAssertFalse(wrongOwner)
        XCTAssertFalse(stale)
        XCTAssertTrue(h.writes.isEmpty)
        XCTAssertEqual(h.factoryCalls, 0)
    }

    func testDelayedOldIntentCannotAdoptSameUIDAfterGuestRoundTrip() async {
        let h = DrainIntegrationHarness()
        let original = h.canonical.contextTicket()
        h.select(nil); h.select("A")
        let ok = await h.write("favorite", stillCurrent: { h.canonical.isCurrent(original) })
        XCTAssertFalse(ok)
        XCTAssertTrue(h.writes.isEmpty)
    }

    func testLastGuardRejectsStopDuringReferencePreparationAndReleasesUnstartedLease() async throws {
        let h = DrainIntegrationHarness()
        var stop: ReaderWriterDrainCoordinator.StopTicket?
        let ok = await h.write("favorite", beforeEnqueue: {
            stop = h.runtime.stopWrites(context: h.canonical.contextTicket())
        })
        XCTAssertFalse(ok)
        XCTAssertTrue(h.writes.isEmpty)
        let drain = Task { try await h.runtime.drain(try XCTUnwrap(stop)) }
        await h.waitForDrains(1)
        h.completeDrain(0)
        let receipt = try await drain.value
        XCTAssertTrue(h.runtime.isCurrent(receipt))
    }

    func testFactoryAccountChangeRefusesWaitOnCapturedClient() async throws {
        let h = DrainIntegrationHarness()
        let stop = try XCTUnwrap(h.runtime.stopWrites(context: h.canonical.contextTicket()))
        h.onFactory = { h.select("B") }
        do { _ = try await h.runtime.drain(stop); XCTFail("Changed owner must not drain") }
        catch {}
        XCTAssertEqual(h.factoryCalls, 1)
        XCTAssertTrue(h.drainCallbacks.isEmpty)
    }

    func testDrainRetainsOneCapturedClientEvenIfFactorySelectionChanges() async throws {
        let h = DrainIntegrationHarness()
        let stop = try XCTUnwrap(h.runtime.stopWrites(context: h.canonical.contextTicket()))
        let task = Task { try await h.runtime.drain(stop) }
        await h.waitForDrains(1)
        h.selectedClient = "replacement"
        XCTAssertEqual(h.drainClients, ["original"])
        XCTAssertEqual(h.factoryCalls, 1)
        h.completeDrain(0)
        let receipt = try await task.value
        XCTAssertTrue(h.runtime.isCurrent(receipt))
        XCTAssertEqual(h.factoryCalls, 1)
    }

    func testActualFavoritesPipelineStopsBeforeBookmarkMirrorAfterFavoriteCallback() async throws {
        let h = DrainIntegrationHarness(), favorites = try await makeFavorite()
        let task = Task {
            await succeeds {
                try await FavoritesMutationTransport.perform(model: favorites.model, ticket: favorites.ticket,
                    expectedUserID: "A", writeFavorite: { mutation, uid in
                        try await h.runtime.performWrite(expectedUserID: uid,
                            stillCurrent: { favorites.model.isCurrent(mutation) }, start: h.start("favorite"))
                    }, setBookmark: { ticket, uid, originalModel in
                        try await FavoritesProfileMirror.perform(model: originalModel, ticket: ticket, expectedUserID: uid,
                            effects: .init(identity: { .init(actualUID: h.actualUID, canonicalUID: h.canonical.snapshot.userID) },
                                updateExisting: { originalUID, _, _ in
                                    try await h.runtime.performWrite(expectedUserID: originalUID,
                                        stillCurrent: { originalModel.isCurrent(ticket) }, start: h.start("bookmark"))
                                }))
                    })
            }
        }
        await h.waitForWrites(1)
        let stop = try XCTUnwrap(h.runtime.stopWrites(context: h.canonical.contextTicket()))
        let drain = Task { try await h.runtime.drain(stop) }
        await h.waitForDeadlines(1)
        XCTAssertEqual(h.factoryCalls, 0)
        h.completeWrite(0)
        let pipelineSucceeded = await task.value
        XCTAssertFalse(pipelineSucceeded)
        await h.waitForDrains(1)
        XCTAssertEqual(h.writes.map(\.name), ["favorite"])
        // Stopping a future writer never claims to undo the acknowledged first
        // write, complete its mirror, or finish the durable outbox intent.
        XCTAssertTrue(favorites.model.isCurrent(favorites.ticket))
        h.completeDrain(0)
        let receipt = try await drain.value
        XCTAssertTrue(h.runtime.isCurrent(receipt))
    }

    func testActualPreferencesAndFavoriteCallbacksBothDrainBeforeSDKWait() async throws {
        let h = DrainIntegrationHarness()
        let preferences = try await makePreferences(h)
        let request = try XCTUnwrap(preferences.captureSave(ids: ["music"], context: preferences.contextTicket()))
        let favorite = Task { await h.write("favorite") }
        let preference = Task { await preferences.saveInterests(request) }
        await h.waitForWrites(2)
        let stop = try XCTUnwrap(h.runtime.stopWrites(context: h.canonical.contextTicket()))
        let drain = Task { try await h.runtime.drain(stop) }
        await h.waitForDeadlines(1)
        XCTAssertEqual(h.factoryCalls, 0)
        let preferenceIndex = try XCTUnwrap(h.writes.firstIndex { $0.name == "preferences" })
        let favoriteIndex = try XCTUnwrap(h.writes.firstIndex { $0.name == "favorite" })
        h.completeWrite(preferenceIndex)
        let saved = await preference.value
        XCTAssertTrue(saved)
        XCTAssertEqual(preferences.preferences.interestTopicIDs, ["music"])
        XCTAssertEqual(h.factoryCalls, 0)
        h.completeWrite(favoriteIndex)
        let favoriteSaved = await favorite.value
        XCTAssertTrue(favoriteSaved)
        await h.waitForDrains(1)
        h.completeDrain(0)
        let receipt = try await drain.value
        XCTAssertTrue(h.runtime.isCurrent(receipt))
    }

    func testPreferencePresentationDeadlineDoesNotReleasePhysicalWriter() async throws {
        let h = DrainIntegrationHarness()
        let preferences = try await makePreferences(h)
        let request = try XCTUnwrap(preferences.captureSave(ids: ["culture"], context: preferences.contextTicket()))
        let task = Task { await preferences.saveInterests(request) }
        await h.waitForWrites(1)
        try XCTUnwrap(h.preferenceDeadlines.last)()
        let saved = await task.value
        XCTAssertFalse(saved)
        XCTAssertEqual(preferences.preferences.interestTopicIDs, ["before"])
        let stop = try XCTUnwrap(h.runtime.stopWrites(context: h.canonical.contextTicket()))
        let drain = Task { try await h.runtime.drain(stop) }
        await h.waitForDeadlines(1)
        XCTAssertEqual(h.factoryCalls, 0)
        h.completeWrite(0)
        await h.waitForDrains(1)
        XCTAssertEqual(preferences.preferences.interestTopicIDs, ["before"])
        h.completeDrain(0)
        _ = try await drain.value
    }

    func testCancelledWriterRemainsPhysicalBarrierUntilCallback() async throws {
        let h = DrainIntegrationHarness()
        var finished = false
        let write = Task { let result = await h.write("bookmark"); finished = true; return result }
        await h.waitForWrites(1)
        write.cancel()
        let stop = try XCTUnwrap(h.runtime.stopWrites(context: h.canonical.contextTicket()))
        let drain = Task { try await h.runtime.drain(stop) }
        await h.waitForDeadlines(1)
        XCTAssertFalse(finished)
        XCTAssertEqual(h.factoryCalls, 0)
        h.completeWrite(0)
        let saved = await write.value
        XCTAssertFalse(saved)
        await h.waitForDrains(1)
        h.completeWrite(0) // A duplicated callback cannot free another slot.
        h.completeDrain(0)
        _ = try await drain.value
        XCTAssertEqual(h.factoryCalls, 1)
    }

    func testAccountRoundTripRetainsOldPhysicalWriteWithoutPublishingItsReceipt() async throws {
        let h = DrainIntegrationHarness()
        var finished = false
        let write = Task { let result = await h.write("preferences"); finished = true; return result }
        await h.waitForWrites(1)
        h.select(nil); h.select("A")
        let stop = try XCTUnwrap(h.runtime.stopWrites(context: h.canonical.contextTicket()))
        let drain = Task { try await h.runtime.drain(stop) }
        await h.waitForDeadlines(1)
        XCTAssertFalse(finished)
        XCTAssertEqual(h.factoryCalls, 0)
        h.completeWrite(0)
        let saved = await write.value
        XCTAssertFalse(saved)
        await h.waitForDrains(1)
        h.completeDrain(0)
        let receipt = try await drain.value
        XCTAssertTrue(h.runtime.isCurrent(receipt))
    }

    func testDrainTimeoutCannotStartAnotherFactoryWhileOriginalCallbackIsPending() async throws {
        let h = DrainIntegrationHarness()
        let stop = try XCTUnwrap(h.runtime.stopWrites(context: h.canonical.contextTicket()))
        let first = Task { try await h.runtime.drain(stop) }
        await h.waitForDrains(1)
        try XCTUnwrap(h.deadlines.first)()
        do { _ = try await first.value; XCTFail("Expected deadline failure") } catch {}
        do { _ = try await h.runtime.drain(stop); XCTFail("Original physical wait is still occupied") } catch {}
        XCTAssertEqual(h.factoryCalls, 1)
        h.completeDrain(0)
    }

    func testActualPreferencesKeepOldSDKSlotAcrossSameUIDRoundTrip() async throws {
        let h = DrainIntegrationHarness()
        let preferences = try await makePreferences(h)
        let first = try XCTUnwrap(preferences.captureSave(ids: ["old"], context: preferences.contextTicket()))
        let oldSave = Task { await preferences.saveInterests(first) }
        await h.waitForWrites(1)
        _ = preferences.changeContext(to: .confirmed(userID: nil)); h.select(nil)
        h.select("A")
        let context = try XCTUnwrap(preferences.changeContext(to: .confirmed(userID: "A")))
        await preferences.load(context)
        let next = try XCTUnwrap(preferences.captureSave(ids: ["new"], context: context))
        let nextSave = Task { await preferences.saveInterests(next) }
        let oldAccepted = await oldSave.value
        XCTAssertFalse(oldAccepted)
        // The new UI operation starts its own deadline while its physical
        // transport remains queued behind the previous generation's callback.
        await h.waitForPreferenceDeadlines(2)
        XCTAssertEqual(h.writes.count, 1)
        h.completeWrite(0)
        await h.waitForWrites(2)
        XCTAssertEqual(preferences.preferences.interestTopicIDs, ["before"])
        h.completeWrite(1)
        let nextAccepted = await nextSave.value
        XCTAssertTrue(nextAccepted)
        XCTAssertEqual(preferences.preferences.interestTopicIDs, ["new"])
    }

    func testCapturedDrainClientSurvivesPresentationTimeoutUntilPhysicalCallback() async throws {
        let canonical = CanonicalSessionState()
        _ = canonical.adopt(.init(uid: "A", email: "reader@example.invalid", isEmailVerified: true))
        weak var client: EphemeralClient?
        var callback: ReaderWriterDrainRuntime.Completion?
        var deadline: (@MainActor () -> Void)?
        let started = XCTestExpectation(description: "Ephemeral client registered callback")
        let runtime = ReaderWriterDrainRuntime(canonical: canonical, actualUID: { "A" }, schedule: {
            deadline = $0; return {}
        }, makeDrain: {
            let heldClient = EphemeralClient(); client = heldClient
            return .init(wait: { completion in
                withExtendedLifetime(heldClient) { callback = completion; started.fulfill() }
            })
        })
        XCTAssertNil(client)
        let stop = try XCTUnwrap(runtime.stopWrites(context: canonical.contextTicket()))
        let drain = Task { try await runtime.drain(stop) }
        let startedResult = await XCTWaiter.fulfillment(of: [started], timeout: 3)
        XCTAssertEqual(startedResult, .completed)
        XCTAssertNotNil(client)
        try XCTUnwrap(deadline)()
        do { _ = try await drain.value; XCTFail("Expected timeout") } catch {}
        XCTAssertNotNil(client)
        // Remove the fake SDK's completion just as a real callback lifecycle
        // does; after physical return it must not retain the held client.
        func returnCallback() { let held = callback; callback = nil; held?(nil) }
        returnCallback()
        XCTAssertNil(client)
    }

    func testSDKWriteErrorDoesNotBecomeSuccessfulPreferenceSave() async throws {
        let h = DrainIntegrationHarness()
        let preferences = try await makePreferences(h)
        let request = try XCTUnwrap(preferences.captureSave(ids: ["new"], context: preferences.contextTicket()))
        let task = Task { await preferences.saveInterests(request) }
        await h.waitForWrites(1)
        h.completeWrite(0, error: URLError(.notConnectedToInternet))
        let saved = await task.value
        XCTAssertFalse(saved)
        XCTAssertEqual(preferences.preferences.interestTopicIDs, ["before"])
    }

    private func makeFavorite() async throws -> (model: FavoritesModel, ticket: FavoritesModel.DispatchTicket) {
        let box = FavoriteBox()
        let model = FavoritesModel(storage: .init(read: { box.records[$0] }, write: { box.records[$0] = $1 }))
        model.changeContext(to: .confirmed(userID: "A"))
        let recovery = try XCTUnwrap(model.recoveryTicket())
        XCTAssertTrue(model.beginRecovery(recovery))
        let recovered = await model.finishRecovery(recovery, success: true)
        XCTAssertTrue(recovered)
        let article = Article(id: "article", name: "Original", slug: "article", content: "", intro: "", topicID: "topic",
                              lastPublished: "2026-10-20T12:00:00Z", contentRevision: "r1")
        let mutation = try XCTUnwrap(model.setFavorite(article, enabled: true))
        let ticket = await model.beginDispatch(mutation)
        return (model, try XCTUnwrap(ticket))
    }

    private func makePreferences(_ h: DrainIntegrationHarness) async throws -> ReaderPreferencesModel {
        let model = ReaderPreferencesModel(capturePermission: { { true } }, identity: {
            .init(actualUID: h.actualUID, canonicalUID: h.canonical.snapshot.userID)
        }, load: { _, stillCurrent in
            guard stillCurrent() else { throw CancellationError() }
            return .init(preferences: ReaderPreferences(interestTopicIDs: ["before"]), isFromCache: false)
        }, save: { request, stillCurrent in
            try await h.runtime.performWrite(expectedUserID: request.userID,
                stillCurrent: stillCurrent, start: h.start("preferences"))
        }, schedule: { deadline in
            h.recordPreferenceDeadline(deadline)
            return {}
        })
        model.start()
        let context = try XCTUnwrap(model.changeContext(to: .confirmed(userID: "A")))
        await model.load(context)
        XCTAssertTrue(model.hasLoaded)
        return model
    }

    private final class FavoriteBox { var records: [FavoritesNamespace: Data] = [:] }
    private final class EphemeralClient {}
}

@MainActor
private func succeeds(_ action: () async throws -> Void) async -> Bool {
    do { try await action(); return true } catch { return false }
}

@MainActor
private final class DrainIntegrationHarness {
    typealias Completion = ReaderWriterDrainCoordinator.Completion
    struct Write { let name: String; let completion: Completion }
    let canonical = CanonicalSessionState()
    var actualUID: String? = "A"
    var identityReads = 0, factoryCalls = 0
    var selectedClient = "original"
    var onFactory: (() -> Void)?
    var writes: [Write] = []
    var drainCallbacks: [Completion] = [], drainClients: [String] = []
    var deadlines: [@MainActor () -> Void] = []
    var preferenceDeadlines: [@MainActor () -> Void] = []
    private var writeObservers: [(Int, XCTestExpectation)] = []
    private var drainObservers: [(Int, XCTestExpectation)] = []
    private var deadlineObservers: [(Int, XCTestExpectation)] = []
    private var preferenceDeadlineObservers: [(Int, XCTestExpectation)] = []

    lazy var runtime = ReaderWriterDrainRuntime(canonical: canonical, actualUID: { [unowned self] in
        self.identityReads += 1; return self.actualUID
    }, schedule: { [unowned self] deadline in
        self.deadlines.append(deadline)
        self.notify(&self.deadlineObservers, count: self.deadlines.count)
        return {}
    }, makeDrain: { [unowned self] in
        self.factoryCalls += 1
        let heldClient = self.selectedClient
        self.onFactory?()
        return .init(wait: { [unowned self] completion in
            self.drainClients.append(heldClient); self.drainCallbacks.append(completion)
            self.notify(&self.drainObservers, count: self.drainCallbacks.count)
        })
    })

    init() { select("A") }
    func select(_ uid: String?) {
        actualUID = uid
        _ = canonical.adopt(uid.map { .init(uid: $0, email: "reader@example.invalid", isEmailVerified: true) })
    }
    func start(_ name: String, beforeEnqueue: @escaping @MainActor () -> Void = {}) -> ReaderWriterDrainRuntime.Start {
        { [unowned self] stillAdmitted, completion in
            beforeEnqueue()
            guard stillAdmitted() else { completion(CancellationError()); return }
            self.writes.append(.init(name: name, completion: completion))
            self.notify(&self.writeObservers, count: self.writes.count)
        }
    }
    func write(_ name: String, uid: String = "A", stillCurrent: @escaping ReaderWriterDrainRuntime.Guard = { true },
               beforeEnqueue: @escaping @MainActor () -> Void = {}) async -> Bool {
        await succeeds { try await runtime.performWrite(expectedUserID: uid, stillCurrent: stillCurrent,
            start: start(name, beforeEnqueue: beforeEnqueue)) }
    }
    func completeWrite(_ index: Int, error: Error? = nil) { writes[index].completion(error) }
    func completeDrain(_ index: Int, error: Error? = nil) { drainCallbacks[index](error) }
    func waitForWrites(_ count: Int) async {
        if writes.count >= count { return }
        let event = XCTestExpectation(description: "Physical writer callback registered")
        writeObservers.append((count, event)); await wait(event)
    }
    func waitForDrains(_ count: Int) async {
        if drainCallbacks.count >= count { return }
        let event = XCTestExpectation(description: "Physical SDK drain registered")
        drainObservers.append((count, event)); await wait(event)
    }
    func waitForDeadlines(_ count: Int) async {
        if deadlines.count >= count { return }
        let event = XCTestExpectation(description: "Drain presentation deadline registered")
        deadlineObservers.append((count, event)); await wait(event)
    }
    func recordPreferenceDeadline(_ deadline: @escaping @MainActor () -> Void) {
        preferenceDeadlines.append(deadline)
        notify(&preferenceDeadlineObservers, count: preferenceDeadlines.count)
    }
    func waitForPreferenceDeadlines(_ count: Int) async {
        if preferenceDeadlines.count >= count { return }
        let event = XCTestExpectation(description: "Preference operation queued")
        preferenceDeadlineObservers.append((count, event)); await wait(event)
    }
    private func wait(_ event: XCTestExpectation) async {
        let result = await XCTWaiter.fulfillment(of: [event], timeout: 3)
        XCTAssertEqual(result, .completed)
    }
    private func notify(_ observers: inout [(Int, XCTestExpectation)], count: Int) {
        let ready = observers.filter { $0.0 <= count }
        observers.removeAll { $0.0 <= count }
        ready.forEach { $0.1.fulfill() }
    }
}
