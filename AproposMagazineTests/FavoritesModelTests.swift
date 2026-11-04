import Combine
import XCTest
@testable import Apropos

@MainActor
final class FavoritesModelTests: XCTestCase {
    @MainActor private final class Memory {
        struct Operation { let writing: Bool; let run: @MainActor () -> Void }
        var data: [FavoritesNamespace: Data] = [:]
        var reads: [FavoritesNamespace] = []
        var writes: [(FavoritesNamespace, FavoritesRecord, UUID?)] = []
        var queue: [Operation] = []
        var active: Operation?
        var holdWrites = false
        var holdReads = false
        var failRead = false
        var failWrite = false
        var failReleased = false
        var onWrite: (@MainActor () -> Void)?
        var onRead: (@MainActor () -> Void)?
        var storage: FavoritesModel.Storage {
            .init(read: { namespace, complete in
                self.reads.append(namespace)
                self.enqueue(.init(writing: false, run: {
                    self.onRead?()
                    complete(Result {
                        if self.failRead { throw FavoritesJournalFailure.readFailed }
                        return try self.data[namespace].map { try FavoritesRecordCodec.decode($0, namespace: namespace) }
                    })
                }))
            }, write: { namespace, record, expected, complete in
                self.writes.append((namespace, record, expected)); self.onWrite?()
                self.enqueue(.init(writing: true, run: {
                    complete(Result {
                        if self.failWrite || self.failReleased { self.failReleased = false; throw FavoritesJournalFailure.writeFailed }
                        let old = try self.data[namespace].map { try FavoritesRecordCodec.decode($0, namespace: namespace) }
                        guard old?.recordRevision == expected else { throw FavoritesJournalFailure.staleRevision }
                        self.data[namespace] = try FavoritesRecordCodec.encode(record, namespace: namespace)
                    })
                }))
            })
        }
        func enqueue(_ operation: Operation) { queue.append(operation); drain() }
        func drain() {
            guard active == nil, !queue.isEmpty else { return }
            let operation = queue.removeFirst()
            if operation.writing ? holdWrites : holdReads { active = operation; return }
            operation.run(); drain()
        }
        func release(failing: Bool = false) {
            let operation = active; active = nil; failReleased = failing
            operation?.run(); drain()
        }
        func record(_ namespace: FavoritesNamespace) throws -> FavoritesRecord {
            try FavoritesRecordCodec.decode(XCTUnwrap(data[namespace]), namespace: namespace)
        }
    }
    private final class DiskGate: @unchecked Sendable {
        private let lock = NSLock()
        private var shouldHold = false
        private var throwAfterReplacement = false
        let entered = DispatchSemaphore(value: 0)
        let released = DispatchSemaphore(value: 0)
        func holdNext() { lock.lock(); shouldHold = true; lock.unlock() }
        func failAfterNextReplacement() { lock.lock(); throwAfterReplacement = true; lock.unlock() }
        func waitUntilEntered() -> Bool { entered.wait(timeout: .now() + 3) == .success }
        func replace(_ data: Data, at url: URL) throws {
            lock.lock(); let hold = shouldHold; shouldHold = false
            let fail = throwAfterReplacement; throwAfterReplacement = false; lock.unlock()
            if hold {
                entered.signal()
                guard released.wait(timeout: .now() + 5) == .success else { throw FavoritesJournalFailure.writeFailed }
            }
            try data.write(to: url, options: .atomic)
            if fail { throw FavoritesJournalFailure.writeFailed }
        }
    }
    private func article(_ id: String = "a", revision: String = "r1", name: String = "Artikel") -> Article {
        Article(id: id, name: name, slug: id, content: "<p>BODY</p>", trailer: "<iframe>EMBED</iframe>", intro: "INTRO",
                topicID: "topic", lastPublished: "2026-10-20T10:00:00Z", contentRevision: revision)
    }
    private func ids(_ model: FavoritesModel) -> [String] { model.snapshot.articles.map(\.id) }
    private func remote(_ articles: [Article], cache: Bool = false, pending: Bool = false) -> FavoritesModel.RemoteSnapshot {
        .init(articles: articles, isFromCache: cache, hasPendingWrites: pending)
    }
    private func recover(_ model: FavoritesModel) async throws {
        let ticket = try XCTUnwrap(model.recoveryTicket())
        XCTAssertTrue(model.beginRecovery(ticket))
        let success = await model.finishRecovery(ticket, success: true)
        XCTAssertTrue(success); XCTAssertTrue(model.snapshot.recoveryReady)
    }
    private func dispatch(_ model: FavoritesModel, _ mutation: FavoritesModel.Mutation) async throws -> FavoritesModel.DispatchTicket {
        let ticket = await model.beginDispatch(mutation)
        return try XCTUnwrap(ticket)
    }
    private func checkTrue(_ value: Bool, file: StaticString = #filePath, line: UInt = #line) { XCTAssertTrue(value, file: file, line: line) }
    private func checkFalse(_ value: Bool, file: StaticString = #filePath, line: UInt = #line) { XCTAssertFalse(value, file: file, line: line) }
    func testConstructionAndUnknownContextAreInert() {
        let memory = Memory(); let model = FavoritesModel(storage: memory.storage)
        XCTAssertNil(model.setFavorite(article(), enabled: true)); XCTAssertNil(model.observationTicket())
        XCTAssertNil(model.recoveryTicket()); XCTAssertNil(model.membershipTicket(articleID: "a"))
        model.retryStorage(); XCTAssertTrue(memory.reads.isEmpty); XCTAssertTrue(memory.writes.isEmpty)
    }
    func testButtonFeedbackTracksGuestPhysicalWriteFailureAndRetryWithoutCloudIntent() {
        let memory = Memory(); let model = FavoritesModel(storage: memory.storage)
        model.changeContext(to: .guest); memory.holdWrites = true
        _ = model.setFavorite(article(), enabled: true)
        XCTAssertTrue(model.snapshot.pendingArticleIDs.isEmpty)
        XCTAssertEqual(FavoriteButtonStatus(model.snapshot), .pending)
        let remove = FavoriteSelectionIntent(snapshot: model.snapshot, articleID: "a")
        XCTAssertTrue(remove.selected)
        memory.release(failing: true)
        XCTAssertEqual(FavoriteButtonStatus(model.snapshot), .issue)
        XCTAssertTrue(model.snapshot.canRetry)
        XCTAssertTrue(remove.isCurrent(in: model.snapshot, articleID: "a"))
        model.retryStorage()
        // An unresolved retry retains the last physical failure until its
        // callback confirms storage; beginning a retry is not success.
        XCTAssertEqual(FavoriteButtonStatus(model.snapshot), .issue)
        memory.release()
        XCTAssertEqual(FavoriteButtonStatus(model.snapshot), .ready)
        XCTAssertFalse(model.snapshot.serverConfirmed)
        XCTAssertEqual(try memory.record(.guest).base.map(\.id), ["a"])
    }

    func testInitialReadFailureKeepsRetryButCannotOfferSelectionUntilLoaded() {
        let memory = Memory(); memory.failRead = true
        let model = FavoritesModel(storage: memory.storage)
        XCTAssertFalse(model.canChangeSelection)
        model.changeContext(to: .guest)
        XCTAssertEqual(FavoriteButtonStatus(model.snapshot), .issue)
        XCTAssertTrue(model.snapshot.canRetry)
        XCTAssertFalse(model.canChangeSelection)
        XCTAssertNil(model.setFavorite(article(), enabled: true))
        memory.failRead = false; model.retryStorage()
        XCTAssertTrue(model.canChangeSelection)
        XCTAssertEqual(FavoriteButtonStatus(model.snapshot), .ready)
        _ = model.setFavorite(article(), enabled: true)
        XCTAssertEqual(model.snapshot.articles.map(\.id), ["a"])
        model.changeContext(to: .unresolved)
        XCTAssertFalse(model.canChangeSelection)
    }

    func testDisplayedSelectionIntentCannotInvertAfterAnotherControlChangesChoice() {
        let memory = Memory(); let model = FavoritesModel(storage: memory.storage)
        model.changeContext(to: .guest); _ = model.setFavorite(article(), enabled: true)
        let remove = FavoriteSelectionIntent(snapshot: model.snapshot, articleID: "a")
        _ = model.setFavorite(article(), enabled: false)
        XCTAssertFalse(remove.isCurrent(in: model.snapshot, articleID: "a"))
        let save = FavoriteSelectionIntent(snapshot: model.snapshot, articleID: "a")
        XCTAssertFalse(save.selected)
        XCTAssertFalse(save.isCurrent(in: model.snapshot, articleID: "b"))
        _ = model.setFavorite(article(), enabled: true)
        XCTAssertFalse(save.isCurrent(in: model.snapshot, articleID: "a"))
    }

    func testDisplayedActionRejectsSameSelectedValueAfterABAAndLateLocalWrite() {
        let memory = Memory(); let model = FavoritesModel(storage: memory.storage)
        model.changeContext(to: .confirmed(userID: "A")); memory.holdWrites = true
        _ = model.setFavorite(article(), enabled: true)
        let original = FavoriteSelectionIntent(snapshot: model.snapshot, articleID: "a")
        model.changeContext(to: .confirmed(userID: "B"))
        XCTAssertFalse(original.isCurrent(in: model.snapshot, articleID: "a"))
        model.changeContext(to: .confirmed(userID: "A")); memory.release()
        XCTAssertEqual(model.snapshot.articles.map(\.id), ["a"])
        XCTAssertFalse(original.isCurrent(in: model.snapshot, articleID: "a"))
        XCTAssertEqual(FavoriteButtonStatus(model.snapshot), .pending) // recovery, not an article error
    }

    func testCollectionIssueOnOtherArticleDoesNotAlterThisArticlesSelection() async throws {
        let memory = Memory(); let model = FavoritesModel(storage: memory.storage)
        model.changeContext(to: .confirmed(userID: "A")); try await recover(model)
        let mutation = try XCTUnwrap(model.setFavorite(article("other"), enabled: true))
        let ticket = try await dispatch(model, mutation)
        _ = await model.finishDispatch(ticket, result: .failed)
        XCTAssertEqual(FavoriteButtonStatus(model.snapshot), .issue)
        XCTAssertEqual(model.snapshot.pendingArticleIDs, ["other"])
        let thisArticle = FavoriteSelectionIntent(snapshot: model.snapshot, articleID: "a")
        XCTAssertFalse(thisArticle.selected)
        XCTAssertTrue(thisArticle.isCurrent(in: model.snapshot, articleID: "a"))
    }

    func testButtonDoesNotPresentCloudACKAsConfirmedBeforeFreshReadAndLocalRetirement() async throws {
        let memory = Memory(); let model = FavoritesModel(storage: memory.storage)
        model.changeContext(to: .confirmed(userID: "A")); try await recover(model)
        let observation = try XCTUnwrap(model.observationTicket())
        let mutation = try XCTUnwrap(model.setFavorite(article(), enabled: true))
        let ticket = try await dispatch(model, mutation)
        _ = await model.finishDispatch(ticket, result: .acknowledged)
        XCTAssertEqual(FavoriteButtonStatus(model.snapshot), .pending)
        _ = model.applyRemote(remote([article()], cache: true), ticket: observation)
        XCTAssertEqual(FavoriteButtonStatus(model.snapshot), .pending)
        memory.holdWrites = true
        _ = model.applyRemote(remote([article()]), ticket: observation)
        XCTAssertEqual(FavoriteButtonStatus(model.snapshot), .pending)
        memory.release(); memory.release()
        XCTAssertEqual(FavoriteButtonStatus(model.snapshot), .ready)
        XCTAssertTrue(model.snapshot.serverConfirmed)
    }
    func testGuestAndAccountsRetainSeparateDurableRecordsAndPendingAcrossABA() async throws {
        let memory = Memory(); let model = FavoritesModel(storage: memory.storage)
        model.changeContext(to: .confirmed(userID: "A")); let old = try XCTUnwrap(model.setFavorite(article(), enabled: true))
        let originalGeneration = model.snapshot.generation
        model.changeContext(to: .guest); _ = model.setFavorite(article("guest"), enabled: true)
        XCTAssertTrue(model.snapshot.pendingArticleIDs.isEmpty); XCTAssertTrue(model.snapshot.recoveryReady)
        model.changeContext(to: .confirmed(userID: "B")); XCTAssertTrue(ids(model).isEmpty)
        model.changeContext(to: .confirmed(userID: "A")); XCTAssertEqual(ids(model), ["a"])
        XCTAssertNotEqual(originalGeneration, model.snapshot.generation); XCTAssertFalse(model.isCurrent(old))
        XCTAssertEqual(model.snapshot.pendingArticleIDs, ["a"]); XCTAssertFalse(model.snapshot.recoveryReady)
        let restored = try XCTUnwrap(model.pendingMutations.first); XCTAssertEqual(restored.id, old.id)
        let beforeRecovery = await model.beginDispatch(restored); XCTAssertNil(beforeRecovery)
        try await recover(model); XCTAssertEqual(model.dispatchableMutations.map(\.id), [old.id])
    }
    func testAdmissionAndRemovalTombstoneSurviveFreshModelAndContradictoryServer() async throws {
        let memory = Memory(); let first = FavoritesModel(storage: memory.storage)
        first.changeContext(to: .confirmed(userID: "A")); try await recover(first)
        _ = first.setFavorite(article(), enabled: true)
        let remove = try XCTUnwrap(first.setFavorite(article(), enabled: false))
        let cold = FavoritesModel(storage: memory.storage); cold.changeContext(to: .confirmed(userID: "A"))
        XCTAssertEqual(cold.pendingMutations.first?.id, remove.id); XCTAssertTrue(ids(cold).isEmpty)
        try await recover(cold); let observation = try XCTUnwrap(cold.observationTicket())
        XCTAssertTrue(cold.applyRemote(remote([article()]), ticket: observation)); XCTAssertTrue(ids(cold).isEmpty)
        XCTAssertEqual(cold.snapshot.pendingArticleIDs, ["a"])
    }
    func testAsyncAdmissionRegistersBeforeAccountSwitchAndReadWaitsOldCommit() throws {
        let memory = Memory(); let model = FavoritesModel(storage: memory.storage)
        model.changeContext(to: .confirmed(userID: "A")); memory.holdWrites = true
        let old = try XCTUnwrap(model.setFavorite(article(), enabled: true))
        model.changeContext(to: .guest); model.changeContext(to: .confirmed(userID: "A"))
        XCTAssertTrue(ids(model).isEmpty); XCTAssertEqual(model.snapshot.state, .loading)
        memory.release(); XCTAssertEqual(ids(model), ["a"])
        XCTAssertEqual(model.pendingMutations.first?.id, old.id); XCTAssertFalse(model.isCurrent(old))
    }
    func testStorageAdmissionFailureNeverCreatesDispatchAuthorityAndRetryUsesDurableHead() async throws {
        let memory = Memory(); let model = FavoritesModel(storage: memory.storage)
        model.changeContext(to: .confirmed(userID: "A")); try await recover(model)
        memory.failWrite = true; let mutation = try XCTUnwrap(model.setFavorite(article(), enabled: true))
        XCTAssertEqual(model.snapshot.state, .writeFailed); XCTAssertEqual(ids(model), ["a"])
        XCTAssertTrue(model.dispatchableMutations.isEmpty)
        let blocked = await model.beginDispatch(mutation); XCTAssertNil(blocked)
        memory.failWrite = false; model.retryStorage()
        XCTAssertEqual(model.dispatchableMutations.map(\.id), [mutation.id])
        let ticket = await model.beginDispatch(mutation); XCTAssertNotNil(ticket)
    }
    func testStartedCommitMustFinishBeforeDispatchAndLateContextCompletionCannotGrantAuthority() async throws {
        let memory = Memory(); let model = FavoritesModel(storage: memory.storage)
        model.changeContext(to: .confirmed(userID: "A")); try await recover(model)
        let mutation = try XCTUnwrap(model.setFavorite(article(), enabled: true)); memory.holdWrites = true
        let registered = expectation(description: "started record registered")
        memory.onWrite = { registered.fulfill() }
        let task = Task { await model.beginDispatch(mutation) }
        await fulfillment(of: [registered], timeout: 2); memory.onWrite = nil
        XCTAssertEqual(memory.writes.last?.1.pending.first?.phase, .started)
        model.changeContext(to: .guest); memory.release()
        let ticket = await task.value; XCTAssertNil(ticket); XCTAssertTrue(ids(model).isEmpty)
        let namespace = try XCTUnwrap(FavoritesContext.confirmed(userID: "A").namespace)
        XCTAssertEqual(try memory.record(namespace).pending.first?.phase, .started)
    }
    func testRestartedStartedAttemptNeedsDrainAndGetsFreshAttemptWithoutInventedACK() async throws {
        let memory = Memory(); let model = FavoritesModel(storage: memory.storage)
        model.changeContext(to: .confirmed(userID: "A")); try await recover(model)
        let mutation = try XCTUnwrap(model.setFavorite(article(), enabled: true))
        let first = try await dispatch(model, mutation)
        let cold = FavoritesModel(storage: memory.storage); cold.changeContext(to: .confirmed(userID: "A"))
        XCTAssertNil(cold.observationTicket()); XCTAssertTrue(cold.dispatchableMutations.isEmpty)
        try await recover(cold); let restored = try XCTUnwrap(cold.dispatchableMutations.first)
        let next = try await dispatch(cold, restored)
        XCTAssertEqual(next.mutation.id, first.mutation.id); XCTAssertNotEqual(next.attemptID, first.attemptID)
        XCTAssertFalse(cold.isCurrent(first)); XCTAssertEqual(cold.snapshot.pendingArticleIDs, ["a"])
    }
    func testACKRequiresFreshMatchingServerProofAndDurableRetirement() async throws {
        let memory = Memory(); let model = FavoritesModel(storage: memory.storage)
        model.changeContext(to: .confirmed(userID: "A")); try await recover(model)
        let observation = try XCTUnwrap(model.observationTicket())
        let mutation = try XCTUnwrap(model.setFavorite(article(), enabled: true))
        let ticket = try await dispatch(model, mutation)
        checkTrue(await model.finishDispatch(ticket, result: .acknowledged))
        XCTAssertEqual(model.snapshot.pendingArticleIDs, ["a"])
        _ = model.applyRemote(remote([article()], cache: true), ticket: observation)
        _ = model.applyRemote(remote([article()], pending: true), ticket: observation)
        XCTAssertEqual(model.snapshot.pendingArticleIDs, ["a"])
        memory.holdWrites = true; _ = model.applyRemote(remote([article()]), ticket: observation)
        XCTAssertEqual(model.snapshot.pendingArticleIDs, ["a"])
        memory.release(); XCTAssertEqual(model.snapshot.pendingArticleIDs, ["a"])
        memory.release(); XCTAssertTrue(model.snapshot.pendingArticleIDs.isEmpty)
        let namespace = try XCTUnwrap(model.context.namespace); XCTAssertTrue(try memory.record(namespace).pending.isEmpty)
    }
    func testProofBeforeACKCanRetireButProofIsNotPersistedAcrossRestart() async throws {
        let memory = Memory(); let model = FavoritesModel(storage: memory.storage)
        model.changeContext(to: .confirmed(userID: "A")); try await recover(model)
        let observation = try XCTUnwrap(model.observationTicket())
        let mutation = try XCTUnwrap(model.setFavorite(article(), enabled: true))
        let ticket = try await dispatch(model, mutation)
        _ = model.applyRemote(remote([article()]), ticket: observation)
        checkTrue(await model.finishDispatch(ticket, result: .acknowledged)); XCTAssertTrue(model.snapshot.pendingArticleIDs.isEmpty)
        let next = try XCTUnwrap(model.setFavorite(article(), enabled: false))
        let nextTicket = try await dispatch(model, next)
        checkTrue(await model.finishDispatch(nextTicket, result: .acknowledged))
        let cold = FavoritesModel(storage: memory.storage); cold.changeContext(to: .confirmed(userID: "A")); try await recover(cold)
        XCTAssertFalse(cold.snapshot.serverConfirmed); XCTAssertEqual(cold.snapshot.pendingArticleIDs, ["a"])
        let fresh = try XCTUnwrap(cold.observationTicket()); _ = cold.applyRemote(remote([]), ticket: fresh)
        XCTAssertTrue(cold.snapshot.pendingArticleIDs.isEmpty)
    }
    func testAcknowledgedAddSurvivesContradictoryUnconfirmedSnapshotAndReconstruction() async throws {
        try await assertAcknowledgedChoiceSurvivesUnconfirmedSnapshot(enabled: true)
    }
    func testAcknowledgedRemovalSurvivesContradictoryUnconfirmedSnapshotAndReconstruction() async throws {
        try await assertAcknowledgedChoiceSurvivesUnconfirmedSnapshot(enabled: false)
    }
    private func assertAcknowledgedChoiceSurvivesUnconfirmedSnapshot(enabled: Bool) async throws {
        let cases = [
            (name: "cache-only", cache: true, pending: false, ignoredEmpty: false),
            (name: "pending-only", cache: false, pending: true, ignoredEmpty: false),
            (name: "cache-and-pending", cache: true, pending: true, ignoredEmpty: false),
            (name: "ignored-empty-cache", cache: true, pending: false, ignoredEmpty: true)
        ]
        for scenario in cases {
            let memory = Memory(); let model = FavoritesModel(storage: memory.storage)
            model.changeContext(to: .confirmed(userID: "B"))
            XCTAssertNotNil(model.setFavorite(article("only-b"), enabled: true))
            let otherNamespace = try XCTUnwrap(model.context.namespace)
            let otherBytes = try XCTUnwrap(memory.data[otherNamespace])
            model.changeContext(to: .guest)
            XCTAssertNotNil(model.setFavorite(article("guest-only"), enabled: true))
            let guestBytes = try XCTUnwrap(memory.data[.guest])
            model.changeContext(to: .confirmed(userID: "A")); try await recover(model)
            let namespace = try XCTUnwrap(model.context.namespace)
            let observation = try XCTUnwrap(model.observationTicket())
            let selected = enabled ? [article(), article("b")] : [article("b")]
            let contradicted = enabled ? [article("b")] : [article(), article("b")]
            let expectedIDs = selected.map(\.id)
            XCTAssertTrue(model.applyRemote(remote(contradicted), ticket: observation), scenario.name)
            let mutation = try XCTUnwrap(model.setFavorite(article(), enabled: enabled))
            let ticket = try await dispatch(model, mutation)
            XCTAssertTrue(model.applyRemote(remote(selected), ticket: observation), scenario.name)
            XCTAssertEqual(model.snapshot.pendingArticleIDs, ["a"], scenario.name)

            // The empty cache is intentionally ignored by the model. Every
            // other case accepts a nonempty base contradicting the local choice.
            let unconfirmed = scenario.ignoredEmpty ? [] : contradicted
            XCTAssertTrue(model.applyRemote(remote(unconfirmed, cache: scenario.cache, pending: scenario.pending), ticket: observation), scenario.name)
            XCTAssertEqual(ids(model), expectedIDs, scenario.name)
            checkTrue(await model.finishDispatch(ticket, result: .acknowledged))
            checkTrue(await model.waitForStorage())
            let stored = try memory.record(namespace)
            XCTAssertEqual(stored.articles.map(\.id), expectedIDs, scenario.name)

            let cold = FavoritesModel(storage: memory.storage)
            cold.changeContext(to: .confirmed(userID: "A"))
            checkTrue(await cold.waitForStorage())
            XCTAssertEqual(ids(cold), expectedIDs, scenario.name)
            if scenario.ignoredEmpty {
                // A discarded empty cache does not invalidate the retained
                // matching server base, so no additional server proof is needed.
                XCTAssertTrue(stored.pending.isEmpty, scenario.name)
                XCTAssertTrue(model.snapshot.pendingArticleIDs.isEmpty, scenario.name)
                XCTAssertTrue(cold.snapshot.pendingArticleIDs.isEmpty, scenario.name)
            } else {
                XCTAssertEqual(model.snapshot.pendingArticleIDs, ["a"], scenario.name)
                XCTAssertEqual(stored.pending.map(\.intentID), [mutation.id], scenario.name)
                XCTAssertEqual(stored.pending.first?.enabled, enabled, scenario.name)
                XCTAssertEqual(stored.pending.first?.phase, .acknowledged, scenario.name)
                XCTAssertEqual(cold.snapshot.pendingArticleIDs, ["a"], scenario.name)
                XCTAssertEqual(cold.pendingMutations.first?.id, mutation.id, scenario.name)
                XCTAssertFalse(cold.isCurrent(ticket))
                try await recover(cold)
                let freshObservation = try XCTUnwrap(cold.observationTicket())
                _ = cold.applyRemote(remote(selected), ticket: freshObservation)
                checkTrue(await cold.waitForStorage())
                XCTAssertEqual(ids(cold), expectedIDs, scenario.name)
                XCTAssertTrue(cold.snapshot.pendingArticleIDs.isEmpty, scenario.name)
                XCTAssertTrue(try memory.record(namespace).pending.isEmpty, scenario.name)
                XCTAssertEqual(try memory.record(namespace).articles.map(\.id), expectedIDs, scenario.name)
            }
            XCTAssertEqual(memory.data[otherNamespace], otherBytes, scenario.name)
            XCTAssertEqual(memory.data[.guest], guestBytes, scenario.name)
            cold.changeContext(to: .confirmed(userID: "B"))
            XCTAssertEqual(ids(cold), ["only-b"], scenario.name)
            cold.changeContext(to: .guest)
            XCTAssertEqual(ids(cold), ["guest-only"], scenario.name)
        }
    }
    func testACKCommitFailureLeavesStartedOnDiskAndNoFalseRetirement() async throws {
        let memory = Memory(); let model = FavoritesModel(storage: memory.storage)
        model.changeContext(to: .confirmed(userID: "A")); try await recover(model)
        let mutation = try XCTUnwrap(model.setFavorite(article(), enabled: true))
        let ticket = try await dispatch(model, mutation); memory.failWrite = true
        checkFalse(await model.finishDispatch(ticket, result: .acknowledged))
        XCTAssertEqual(model.snapshot.pendingArticleIDs, ["a"]); XCTAssertEqual(model.snapshot.state, .writeFailed)
        let namespace = try XCTUnwrap(model.context.namespace)
        XCTAssertEqual(try memory.record(namespace).pending.first?.phase, .started)
    }
    func testLateOldAttemptCannotRetireNewOppositeIntent() async throws {
        let memory = Memory(); let model = FavoritesModel(storage: memory.storage)
        model.changeContext(to: .confirmed(userID: "A")); try await recover(model)
        let first = try XCTUnwrap(model.setFavorite(article(), enabled: true))
        let ticket = try await dispatch(model, first)
        let remove = try XCTUnwrap(model.setFavorite(article(), enabled: false))
        checkFalse(await model.finishDispatch(ticket, result: .acknowledged))
        XCTAssertEqual(model.pendingMutations.first?.id, remove.id); XCTAssertTrue(ids(model).isEmpty)
        let namespace = try XCTUnwrap(model.context.namespace); XCTAssertTrue(try memory.record(namespace).requiresRecovery)
    }
    func testRecoveryFailureNeedsExplicitRetryAndABATicketCannotGrantNextEpoch() async throws {
        let memory = Memory(); let model = FavoritesModel(storage: memory.storage)
        model.changeContext(to: .confirmed(userID: "A")); let first = try XCTUnwrap(model.recoveryTicket())
        XCTAssertTrue(model.beginRecovery(first)); checkFalse(await model.finishRecovery(first, success: false))
        XCTAssertEqual(model.snapshot.state, .recoveryFailed); XCTAssertFalse(model.beginRecovery(first))
        model.retryRecovery(); let second = try XCTUnwrap(model.recoveryTicket()); XCTAssertFalse(model.isCurrent(first))
        XCTAssertTrue(model.beginRecovery(second)); model.changeContext(to: .guest); model.changeContext(to: .confirmed(userID: "A"))
        checkFalse(await model.finishRecovery(second, success: true)); XCTAssertFalse(model.snapshot.recoveryReady)
    }
    func testReadFailureAndUnknownDataPreserveDiskAndBlockAdmission() {
        let memory = Memory(); let namespace = FavoritesNamespace.guest
        memory.data[namespace] = Data("not json".utf8)
        let model = FavoritesModel(storage: memory.storage); model.changeContext(to: .guest)
        XCTAssertEqual(model.snapshot.state, .invalidRecord); XCTAssertNil(model.setFavorite(article(), enabled: true))
        model.retryStorage(); XCTAssertEqual(memory.data[namespace], Data("not json".utf8)); XCTAssertTrue(memory.writes.isEmpty)
    }
    func testPublicationSwitchClearsMembershipAndRejectsOriginalIntentBeforeReturn() {
        let memory = Memory(); let model = FavoritesModel(storage: memory.storage); model.changeContext(to: .guest)
        var switchOnFavorite = true
        let observation = model.changes.sink { value in
            if switchOnFavorite && !value.articles.isEmpty { switchOnFavorite = false; model.changeContext(to: .confirmed(userID: "B")) }
        }
        XCTAssertNil(model.setFavorite(article(), enabled: true)); XCTAssertTrue(ids(model).isEmpty)
        withExtendedLifetime(observation) {}
        XCTAssertNotNil(memory.data[.guest])
    }
    func testSameRevisionEnrichmentKeepsMembershipAndImmutableTransportPayload() async throws {
        let memory = Memory(); let model = FavoritesModel(storage: memory.storage)
        model.changeContext(to: .confirmed(userID: "A")); try await recover(model)
        let mutation = try XCTUnwrap(model.setFavorite(article(name: "Original"), enabled: true))
        let member = try XCTUnwrap(model.membershipTicket(articleID: "a"))
        XCTAssertTrue(model.updateMetadata(article(name: "Ny titel"), ticket: member)); XCTAssertTrue(model.isCurrent(member))
        let ticket = try await dispatch(model, mutation); XCTAssertEqual(ticket.mutation.article.name, "Original")
        let persisted = try memory.record(XCTUnwrap(model.context.namespace)).pending.first
        XCTAssertEqual(persisted?.payload.name, "Original"); XCTAssertEqual(persisted?.article.name, "Ny titel")
    }
    func testWithdrawalPreservesUnknownAttemptAndRecoveryObligationWithoutVisibleMember() async throws {
        let memory = Memory(); var permits = true
        let model = FavoritesModel(storage: memory.storage, sanitize: { permits ? $0 : nil })
        model.changeContext(to: .confirmed(userID: "A")); try await recover(model)
        let mutation = try XCTUnwrap(model.setFavorite(article(), enabled: true))
        let ticket = try await dispatch(model, mutation); permits = false; model.reconcileAvailability()
        XCTAssertTrue(ids(model).isEmpty); XCTAssertFalse(model.isCurrent(ticket)); XCTAssertTrue(model.dispatchableMutations.isEmpty)
        let persisted = try memory.record(XCTUnwrap(model.context.namespace))
        XCTAssertEqual(persisted.pending.first?.intentID, mutation.id); XCTAssertEqual(persisted.pending.first?.phase, .blocked)
        XCTAssertEqual(persisted.pending.first?.attemptID, ticket.attemptID); XCTAssertTrue(persisted.requiresRecovery)
    }
    func testCorrectionBlocksOriginalPayloadUntilExplicitFreshRetry() async throws {
        let memory = Memory(); var revision = "r1"
        let model = FavoritesModel(storage: memory.storage, sanitize: { self.article($0.id, revision: revision) })
        model.changeContext(to: .confirmed(userID: "A")); try await recover(model)
        let original = try XCTUnwrap(model.setFavorite(article(), enabled: true)); revision = "r2"; model.reconcileAvailability()
        XCTAssertEqual(ids(model), ["a"]); XCTAssertEqual(model.snapshot.articles.first?.bodyRevision, "r2")
        XCTAssertTrue(model.dispatchableMutations.isEmpty)
        let retry = try XCTUnwrap(model.retryMutation(articleID: "a"))
        XCTAssertNotEqual(original.id, retry.id); XCTAssertEqual(retry.article.bodyRevision, "r2")
    }
    func testSequentialAsyncSnapshotsChainExpectedRevisionAndOldCommitCannotClearNewDirty() throws {
        let memory = Memory(); let model = FavoritesModel(storage: memory.storage); model.changeContext(to: .guest)
        memory.holdWrites = true
        _ = model.setFavorite(article("first"), enabled: true); _ = model.setFavorite(article("second"), enabled: true)
        XCTAssertNil(memory.writes[0].2); XCTAssertEqual(memory.writes[1].2, memory.writes[0].1.recordRevision)
        memory.release(); XCTAssertEqual(model.snapshot.state, .pending); XCTAssertEqual(ids(model), ["first", "second"])
        memory.release(); XCTAssertEqual(model.snapshot.state, .ready)
    }
    func testFailureOfEarlierSnapshotDoesNotAuthorizeLaterChainedSnapshotAndRetryRebasesKnownHead() throws {
        let memory = Memory(); let model = FavoritesModel(storage: memory.storage); model.changeContext(to: .guest)
        memory.holdWrites = true
        _ = model.setFavorite(article("first"), enabled: true); _ = model.setFavorite(article("second"), enabled: true)
        memory.release(failing: true); memory.release(); XCTAssertEqual(model.snapshot.state, .writeFailed)
        memory.holdWrites = false; model.retryStorage()
        XCTAssertEqual(model.snapshot.state, .ready); XCTAssertEqual(try memory.record(.guest).articles.map(\.id), ["first", "second"])
    }
    func testVisibleAndPendingLimitsDoNotPruneChoicesOrTombstones() throws {
        let memory = Memory(); let model = FavoritesModel(storage: memory.storage); model.changeContext(to: .confirmed(userID: "A"))
        for index in 0..<FavoritesRecordCodec.maximumEntries { XCTAssertNotNil(model.setFavorite(article("a-\(index)"), enabled: true)) }
        XCTAssertNil(model.setFavorite(article("extra"), enabled: true)); XCTAssertEqual(ids(model).count, 200)
        XCTAssertEqual(model.snapshot.pendingArticleIDs.count, 200)
    }
    func testFailedRetirementCanRetryWithoutLosingACKOrClearingPendingBeforeCommit() async throws {
        let memory = Memory(); let model = FavoritesModel(storage: memory.storage)
        model.changeContext(to: .confirmed(userID: "A")); try await recover(model)
        let mutation = try XCTUnwrap(model.setFavorite(article(), enabled: true))
        let ticket = try await dispatch(model, mutation)
        checkTrue(await model.finishDispatch(ticket, result: .acknowledged))
        let observation = try XCTUnwrap(model.observationTicket()); memory.holdWrites = true
        _ = model.applyRemote(remote([article()]), ticket: observation)
        memory.release(); memory.release(failing: true)
        XCTAssertEqual(model.snapshot.pendingArticleIDs, ["a"]); XCTAssertEqual(model.snapshot.state, .writeFailed)
        XCTAssertEqual(try memory.record(XCTUnwrap(model.context.namespace)).pending.first?.phase, .acknowledged)
        memory.holdWrites = false; model.retryStorage()
        XCTAssertTrue(model.snapshot.pendingArticleIDs.isEmpty)
        XCTAssertTrue(try memory.record(XCTUnwrap(model.context.namespace)).pending.isEmpty)
    }
    func testActualJournalCoalescedRetirementCarriesExclusionIntoNewerUnrelatedIntent() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("favorites-retirement-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let gate = DiskGate()
        let journal = FavoritesFileJournal(rootDirectory: root, replace: { try gate.replace($0, at: $1) })
        let model = FavoritesModel(storage: journal.storage)
        model.changeContext(to: .confirmed(userID: "A")); checkTrue(await model.waitForStorage()); try await recover(model)
        let mutation = try XCTUnwrap(model.setFavorite(article(), enabled: true)); checkTrue(await model.waitForStorage())
        let ticket = try await dispatch(model, mutation); checkTrue(await model.finishDispatch(ticket, result: .acknowledged))
        let observation = try XCTUnwrap(model.observationTicket()); gate.holdNext()
        _ = model.applyRemote(remote([article()]), ticket: observation)
        let entered = await Task.detached { gate.waitUntilEntered() }.value
        XCTAssertTrue(entered)
        // The retirement is queued behind the held base write. This mutation
        // replaces that queued snapshot in the actual journal.
        _ = model.setFavorite(article("b"), enabled: true)
        XCTAssertEqual(model.snapshot.pendingArticleIDs, ["a", "b"])
        gate.released.signal(); checkTrue(await model.waitForStorage())
        XCTAssertEqual(model.snapshot.pendingArticleIDs, ["b"])
        let cold = FavoritesModel(storage: journal.storage); cold.changeContext(to: .confirmed(userID: "A"))
        checkTrue(await cold.waitForStorage()); XCTAssertEqual(cold.snapshot.pendingArticleIDs, ["b"])
        XCTAssertEqual(ids(cold), ["a", "b"])
    }

    func testActualReplacementCommittedThenThrowsRetriesExactRecordBeforeAdvancingHead() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("favorites-uncertain-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let gate = DiskGate(); let journal = FavoritesFileJournal(rootDirectory: root, replace: { try gate.replace($0, at: $1) })
        let storage = journal.storage; var records: [FavoritesRecord] = []
        let model = FavoritesModel(storage: .init(read: storage.read, write: { namespace, record, expected, complete in
            records.append(record); storage.write(namespace, record, expected, complete)
        }))
        model.changeContext(to: .confirmed(userID: "A")); checkTrue(await model.waitForStorage()); try await recover(model)
        gate.failAfterNextReplacement()
        let mutation = try XCTUnwrap(model.setFavorite(article(), enabled: true)); checkTrue(await model.waitForStorage())
        XCTAssertEqual(model.snapshot.state, .writeFailed); XCTAssertTrue(model.dispatchableMutations.isEmpty)
        let firstRevision = try XCTUnwrap(records.first?.recordRevision)
        model.retryStorage(); checkTrue(await model.waitForStorage())
        XCTAssertEqual(records.count, 2); XCTAssertEqual(records[1].recordRevision, firstRevision)
        XCTAssertEqual(model.dispatchableMutations.map(\.id), [mutation.id])
        let cold = FavoritesModel(storage: journal.storage); cold.changeContext(to: .confirmed(userID: "A"))
        checkTrue(await cold.waitForStorage()); XCTAssertEqual(cold.pendingMutations.first?.id, mutation.id)
    }

    func testRecoveryCopyDoesNotClaimLocalCommitWhileActualJournalAdmissionIsHeld() async throws {
        for recoveryFailed in [false, true] {
            let root = FileManager.default.temporaryDirectory.appendingPathComponent("favorites-held-copy-" + UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: root) }
            let gate = DiskGate()
            let journal = FavoritesFileJournal(rootDirectory: root, replace: { try gate.replace($0, at: $1) })
            let model = FavoritesModel(storage: journal.storage)
            model.changeContext(to: .confirmed(userID: "A")); checkTrue(await model.waitForStorage())
            if recoveryFailed {
                let ticket = try XCTUnwrap(model.recoveryTicket())
                XCTAssertTrue(model.beginRecovery(ticket)); checkFalse(await model.finishRecovery(ticket, success: false))
            }
            gate.holdNext(); _ = model.setFavorite(article(), enabled: true)
            let entered = await Task.detached { gate.waitUntilEntered() }.value
            XCTAssertTrue(entered)
            let namespace = try XCTUnwrap(model.context.namespace)
            XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent(namespace.recordBinding + ".json").path))
            XCTAssertEqual(ids(model), ["a"]); XCTAssertEqual(model.snapshot.pendingArticleIDs, ["a"])
            XCTAssertTrue(model.dispatchableMutations.isEmpty)
            XCTAssertEqual(model.snapshot.state, recoveryFailed ? .recoveryFailed : .recovering)
            XCTAssertEqual(model.snapshot.issueMessage, recoveryFailed
                           ? "Synkroniseringen kunne ikke genoptages. Prøv igen."
                           : "Dine valg afventer synkronisering.")
            gate.released.signal(); checkTrue(await model.waitForStorage())
            XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent(namespace.recordBinding + ".json").path))
        }
    }

}
