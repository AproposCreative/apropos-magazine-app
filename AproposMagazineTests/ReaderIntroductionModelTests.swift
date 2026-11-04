import Combine
import XCTest
@testable import Apropos

@MainActor
final class ReaderIntroductionModelTests: XCTestCase {
    private final class Memory {
        var data: Data?
        var reads = 0
        var writes = 0
        var failRead = false
        var failWrite = false
        var ignoreWrite = false
        var onRead: (() -> Void)?
        var onWrite: (() -> Void)?
        var storage: ReaderIntroductionStorage {
            .init(read: {
                self.reads += 1; self.onRead?()
                if self.failRead { throw CocoaError(.fileReadUnknown) }; return self.data
            }, write: {
                self.writes += 1; self.onWrite?()
                if self.failWrite { throw CocoaError(.fileWriteUnknown) }
                if !self.ignoreWrite { self.data = $0 }
            })
        }
    }
    private func guest() -> CanonicalSessionState {
        let value = CanonicalSessionState(); value.adopt(nil); return value
    }
    private func bind(_ model: ReaderIntroductionModel, _ canonical: CanonicalSessionState) {
        XCTAssertTrue(model.bindContext(canonical.contextTicket(), isCurrent: canonical.isCurrent))
    }
    private func account(_ id: String) -> ReaderAccountSession {
        ReaderAccountSession(uid: id, email: "fixture@example.invalid", isEmailVerified: true)
    }

    func testConstructionIsInertAndFreshStartIsIndependentAndIdempotent() {
        let memory = Memory(), canonical = guest()
        let model = ReaderIntroductionModel(storage: memory.storage)
        XCTAssertEqual(memory.reads, 0); XCTAssertEqual(memory.writes, 0)
        XCTAssertFalse(model.isPresented)
        bind(model, canonical); XCTAssertTrue(model.start())
        XCTAssertTrue(model.isPresented); XCTAssertEqual(model.step, .welcome)
        XCTAssertFalse(model.isCompleted); XCTAssertTrue(model.start())
        XCTAssertEqual(memory.reads, 1); XCTAssertEqual(memory.writes, 0)
    }

    func testInterruptedStepAndNormalizedDraftResumeWithoutProviderSuccess() {
        let memory = Memory(), canonical = guest()
        let first = ReaderIntroductionModel(storage: memory.storage)
        bind(first, canonical); first.start()
        XCTAssertTrue(first.advance())
        XCTAssertTrue(first.setSelectedTopicIDs([" music ", "music", "culture", "", "bad/path"]))
        XCTAssertEqual(first.selectedTopicIDs, ["culture", "music"])
        let second = ReaderIntroductionModel(storage: memory.storage)
        bind(second, canonical); XCTAssertTrue(second.start())
        XCTAssertEqual(second.step, .interests); XCTAssertEqual(second.selectedTopicIDs, ["culture", "music"])
        XCTAssertFalse(second.isCompleted); XCTAssertTrue(second.isPresented)
    }

    func testCompletionSurvivesRestartAndReplayPreservesGuestInterests() {
        let memory = Memory(), interestsMemory = Memory(), canonical = guest()
        let interests = GuestReaderInterestsModel(storage: interestsMemory.storage)
        interests.start()
        XCTAssertTrue(interests.save(["existing"], context: canonical.contextTicket(), isCurrent: canonical.isCurrent))
        let model = ReaderIntroductionModel(storage: memory.storage)
        bind(model, canonical); model.start(); model.setSelectedTopicIDs(["music"])
        XCTAssertTrue(model.skip()); XCTAssertTrue(model.isCompleted); XCTAssertFalse(model.isPresented)
        let restarted = ReaderIntroductionModel(storage: memory.storage)
        bind(restarted, canonical); restarted.start()
        XCTAssertTrue(restarted.isCompleted); XCTAssertFalse(restarted.isPresented)
        let previousGuestData = interestsMemory.data
        XCTAssertTrue(restarted.replay()); XCTAssertTrue(restarted.isCompleted); XCTAssertTrue(restarted.isPresented)
        XCTAssertEqual(restarted.step, .welcome); XCTAssertEqual(restarted.selectedTopicIDs, ["music"])
        XCTAssertEqual(interestsMemory.data, previousGuestData)
        XCTAssertEqual(interests.selectedTopicIDs, ["existing"])
        XCTAssertEqual(canonical.snapshot.context, .guest)
    }

    func testFailedCompletionKeepsIntroductionOpenAndRetryRepeatsExactProposal() {
        let memory = Memory(), canonical = guest()
        let intro = ReaderIntroductionModel(storage: memory.storage)
        bind(intro, canonical); intro.start(); intro.advance()
        memory.failWrite = true
        XCTAssertFalse(intro.complete()); XCTAssertFalse(intro.isCompleted); XCTAssertTrue(intro.isPresented)
        XCTAssertNotNil(intro.storageError)
        memory.failWrite = false
        XCTAssertTrue(intro.retry()); XCTAssertTrue(intro.isCompleted); XCTAssertFalse(intro.isPresented)
        XCTAssertNil(intro.storageError)
    }

    func testUnconfirmedWriteAndReadFailureCannotReportCompletion() {
        let memory = Memory(), canonical = guest()
        let model = ReaderIntroductionModel(storage: memory.storage)
        bind(model, canonical); memory.failRead = true
        XCTAssertFalse(model.start()); XCTAssertFalse(model.hasLoaded); XCTAssertTrue(model.isPresented)
        XCTAssertFalse(model.complete()); XCTAssertEqual(memory.writes, 0)
        memory.failRead = false; XCTAssertTrue(model.retry())
        memory.ignoreWrite = true
        XCTAssertFalse(model.complete()); XCTAssertFalse(model.isCompleted); XCTAssertNotNil(model.storageError)
    }

    func testCorruptUnsupportedAndOversizedRecordsAreNotOverwritten() throws {
        for data in [Data("broken".utf8), Data(repeating: 65, count: 16_385),
                     Data(#"{"schemaVersion":99,"completed":true,"replaying":false,"step":"welcome","selectedTopicIDs":[]}"#.utf8)] {
            let memory = Memory(); memory.data = data
            let canonical = guest(), model = ReaderIntroductionModel(storage: memory.storage)
            bind(model, canonical)
            XCTAssertFalse(model.start()); XCTAssertFalse(model.hasLoaded); XCTAssertNotNil(model.storageError)
            XCTAssertFalse(model.skip()); XCTAssertEqual(memory.writes, 0); XCTAssertEqual(memory.data, data)
        }
    }

    func testTopicBoundsAndRemovalDoNotExceedTwenty() {
        let memory = Memory(), canonical = guest()
        let intro = ReaderIntroductionModel(storage: memory.storage)
        bind(intro, canonical); intro.start()
        XCTAssertTrue(intro.setSelectedTopicIDs((0..<30).map { "topic-\($0)" } + [String(repeating: "x", count: 129), "\n", "../invalid"]))
        XCTAssertEqual(intro.selectedTopicIDs.count, 20)
        XCTAssertFalse(intro.toggleTopic("extra"))
        let first = intro.selectedTopicIDs[0]
        XCTAssertTrue(intro.toggleTopic(first)); XCTAssertTrue(intro.toggleTopic("extra"))
        XCTAssertEqual(intro.selectedTopicIDs.count, 20)
    }

    func testOwnerSwitchHidesDraftAndPreservesGlobalCompletionWithoutRawUIDPersistence() throws {
        let memory = Memory(), canonical = CanonicalSessionState()
        canonical.adopt(account("private-account-a"))
        let model = ReaderIntroductionModel(storage: memory.storage)
        bind(model, canonical); model.start(); model.advance(); model.setSelectedTopicIDs(["private-topic"]); model.complete()
        XCTAssertFalse(String(decoding: try XCTUnwrap(memory.data), as: UTF8.self).contains("private-account-a"))
        canonical.adopt(account("account-b")); bind(model, canonical)
        XCTAssertTrue(model.isCompleted); XCTAssertFalse(model.isPresented); XCTAssertEqual(model.selectedTopicIDs, [])
        XCTAssertTrue(model.replay()); XCTAssertEqual(model.selectedTopicIDs, [])
        canonical.adopt(nil); bind(model, canonical)
        XCTAssertEqual(model.selectedTopicIDs, []); XCTAssertTrue(model.isCompleted); XCTAssertFalse(model.isPresented)
    }

    func testOwnerSwitchDuringWillChangeRejectsOldCompletionBeforeWrite() {
        let memory = Memory(), canonical = guest()
        let intro = ReaderIntroductionModel(storage: memory.storage)
        bind(intro, canonical); intro.start()
        let subscription = intro.objectWillChange.sink {
            canonical.adopt(self.account("B"))
            _ = intro.bindContext(canonical.contextTicket(), isCurrent: canonical.isCurrent)
        }
        XCTAssertFalse(intro.complete()); XCTAssertFalse(intro.isCompleted); XCTAssertEqual(memory.writes, 0)
        withExtendedLifetime(subscription) {}
    }

    func testPostCommitSubscribersNeverReceiveSupersededSnapshot() {
        let memory = Memory(), canonical = guest(), model = ReaderIntroductionModel(storage: memory.storage)
        bind(model, canonical); model.start()
        var nested = false
        var nestedAccepted: Bool?
        var receivedAccount = false
        var seen: [[ReaderIntroductionModel.Step]] = [[], []]
        func receive(_ snapshot: ReaderIntroductionModel.Snapshot, subscriber: Int) {
            XCTAssertEqual(snapshot, model.snapshot, "Every callback must receive the state current at delivery")
            if receivedAccount {
                XCTAssertEqual(snapshot.step, .account, "An older interests snapshot must not follow the nested account commit")
            }
            seen[subscriber].append(snapshot.step)
            if snapshot.step == .account { receivedAccount = true }
            // Either subscriber may run first. Whichever receives interests
            // advances immediately, so the other must filter that stale send.
            if !nested && snapshot.step == .interests {
                nested = true
                nestedAccepted = model.advance()
            }
        }
        let first = model.changes.sink { receive($0, subscriber: 0) }
        let second = model.changes.sink { receive($0, subscriber: 1) }
        XCTAssertFalse(model.advance(), "The outer publication was superseded by a later accepted action")
        XCTAssertEqual(nestedAccepted, true)
        XCTAssertEqual(model.step, .account)
        XCTAssertEqual(seen[0].last, .account); XCTAssertEqual(seen[1].last, .account)
        let delivered = seen.flatMap { $0 }
        XCTAssertEqual(delivered.filter { $0 == .interests }.count, 1)
        XCTAssertEqual(delivered.filter { $0 == .account }.count, 2)
        withExtendedLifetime((first, second)) {}
    }

    func testReentrantWriteCannotStartAnotherStorageMutation() {
        let memory = Memory(), canonical = guest(), model = ReaderIntroductionModel(storage: memory.storage)
        bind(model, canonical); model.start()
        var nested: Bool?
        memory.onWrite = { nested = model.skip() }
        XCTAssertTrue(model.advance()); XCTAssertEqual(nested, false)
        XCTAssertEqual(memory.writes, 1); XCTAssertEqual(model.step, .interests); XCTAssertFalse(model.isCompleted)
    }

    func testGuestStoreRejectsUnresolvedAccountAndStaleGuestTickets() {
        let memory = Memory(), canonical = CanonicalSessionState()
        let guestModel = GuestReaderInterestsModel(storage: memory.storage)
        XCTAssertEqual(memory.reads, 0); guestModel.start()
        XCTAssertFalse(guestModel.save(["wrong"], context: canonical.contextTicket(), isCurrent: canonical.isCurrent))
        canonical.adopt(nil); let original = canonical.contextTicket()
        canonical.adopt(account("A"))
        XCTAssertFalse(guestModel.save(["wrong"], context: original, isCurrent: canonical.isCurrent))
        XCTAssertFalse(guestModel.save(["wrong"], context: canonical.contextTicket(), isCurrent: canonical.isCurrent))
        canonical.adopt(nil)
        XCTAssertFalse(guestModel.save(["old-guest"], context: original, isCurrent: canonical.isCurrent))
        XCTAssertEqual(memory.writes, 0)
        XCTAssertTrue(guestModel.save([" guest "], context: canonical.contextTicket(), isCurrent: canonical.isCurrent))
        XCTAssertEqual(guestModel.selectedTopicIDs, ["guest"])
    }

    func testGuestOriginalContextIsRecheckedAfterWillChangeAndGuardReentry() {
        let memory = Memory(), canonical = guest(), model = GuestReaderInterestsModel(storage: memory.storage)
        model.start(); let original = canonical.contextTicket()
        let subscription = model.objectWillChange.sink { canonical.adopt(self.account("A")) }
        XCTAssertFalse(model.save(["wrong"], context: original, isCurrent: canonical.isCurrent))
        XCTAssertEqual(memory.writes, 0); XCTAssertEqual(model.selectedTopicIDs, [])
        withExtendedLifetime(subscription) {}
    }

    func testGuestStorageFailurePreservesExistingInterestsAndRestartHasNoAccountTransfer() {
        let memory = Memory(), canonical = guest(), model = GuestReaderInterestsModel(storage: memory.storage)
        model.start(); XCTAssertTrue(model.save(["old"], context: canonical.contextTicket(), isCurrent: canonical.isCurrent))
        memory.failWrite = true
        XCTAssertFalse(model.save(["new"], context: canonical.contextTicket(), isCurrent: canonical.isCurrent))
        XCTAssertEqual(model.selectedTopicIDs, ["old"]); XCTAssertNotNil(model.storageError)
        let restored = GuestReaderInterestsModel(storage: memory.storage)
        XCTAssertTrue(restored.start()); XCTAssertEqual(restored.selectedTopicIDs, ["old"])
        canonical.adopt(account("A"))
        XCTAssertFalse(restored.save(["account"], context: canonical.contextTicket(), isCurrent: canonical.isCurrent))
        XCTAssertEqual(restored.selectedTopicIDs, ["old"])
    }
}

extension ReaderIntroductionModelTests {
    private func legacyRecord(_ memory: Memory, step: ReaderIntroductionModel.Step,
                              schemaVersion: Int = 1, completed: Bool = false, replaying: Bool = false) throws {
        var record = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(memory.data)) as? [String: Any])
        record["schemaVersion"] = schemaVersion
        record["step"] = step.rawValue
        record["completed"] = completed
        record["replaying"] = replaying
        memory.data = try JSONSerialization.data(withJSONObject: record)
    }
    private func loginResult(_ ticket: ReaderIntroductionModel.AccountEntryTicket,
                             canonical: CanonicalSessionState, isNewUser: Bool,
                             session: ReaderAccountSession? = nil, actionID: UUID? = nil,
                             originalContext: CanonicalSessionState.ContextTicket? = nil) throws -> ReaderLoginResult {
        ReaderLoginResult(originalContext: originalContext ?? ticket.originalContext,
            acceptedContext: canonical.contextTicket(),
            session: try XCTUnwrap(session ?? canonical.snapshot.session),
            isNewUser: isNewUser, actionID: actionID ?? ticket.actionID)
    }

    func testLegacyIncompleteStepsRestartAtWelcomeWithSameOwnerDraftAndNoWrite() throws {
        for version in [1, 2] {
            for signedIn in [false, true] {
                for step in [ReaderIntroductionModel.Step.welcome, .interests, .account] {
                    let memory = Memory(), canonical = guest()
                    if signedIn { canonical.adopt(account("reader")) }
                    let old = ReaderIntroductionModel(storage: memory.storage)
                    bind(old, canonical); old.start(); old.setSelectedTopicIDs(["music", "culture"])
                    try legacyRecord(memory, step: step, schemaVersion: version)
                    let before = memory.data, writes = memory.writes
                    let migrated = ReaderIntroductionModel(storage: memory.storage)
                    bind(migrated, canonical); XCTAssertTrue(migrated.start())
                    XCTAssertEqual(migrated.step, .welcome)
                    XCTAssertEqual(migrated.selectedTopicIDs, ["culture", "music"])
                    XCTAssertFalse(migrated.isCompleted); XCTAssertTrue(migrated.isPresented)
                    XCTAssertEqual(memory.writes, writes); XCTAssertEqual(memory.data, before)
                    XCTAssertTrue(migrated.setSelectedTopicIDs(["film"]))
                    let record = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(memory.data)) as? [String: Any])
                    XCTAssertEqual(record["schemaVersion"] as? Int, 3)
                }
            }
        }
    }

    func testLegacyCompletedIntroductionDoesNotStartAnUnrequestedReplay() throws {
        for version in [1, 2] {
            for signedIn in [false, true] {
                for replaying in (version == 1 ? [false, true] : [false]) {
                    let memory = Memory(), canonical = guest()
                    if signedIn { canonical.adopt(account("reader")) }
                    let old = ReaderIntroductionModel(storage: memory.storage)
                    bind(old, canonical); old.start(); old.setSelectedTopicIDs(["culture"])
                    try legacyRecord(memory, step: .account, schemaVersion: version, completed: true, replaying: replaying)
                    let writes = memory.writes, before = memory.data
                    let migrated = ReaderIntroductionModel(storage: memory.storage)
                    bind(migrated, canonical); XCTAssertTrue(migrated.start())
                    XCTAssertTrue(migrated.isCompleted); XCTAssertFalse(migrated.isPresented)
                    XCTAssertEqual(migrated.step, .welcome); XCTAssertEqual(migrated.selectedTopicIDs, ["culture"])
                    XCTAssertEqual(memory.writes, writes); XCTAssertEqual(memory.data, before)
                }
            }
        }
    }

    func testLegacyTwoActiveReplayRestartsAtWelcomeAndSurvivesSaveFailureUntilCompletion() throws {
        for signedIn in [false, true] {
            for step in [ReaderIntroductionModel.Step.interests, .account] {
                let memory = Memory(), canonical = guest()
                if signedIn { canonical.adopt(account("reader")) }
                let old = ReaderIntroductionModel(storage: memory.storage)
                bind(old, canonical); old.start(); old.setSelectedTopicIDs(["culture"])
                try legacyRecord(memory, step: step, schemaVersion: 2, completed: true, replaying: true)
                let before = memory.data, writes = memory.writes
                let migrated = ReaderIntroductionModel(storage: memory.storage)
                bind(migrated, canonical); XCTAssertTrue(migrated.start())
                XCTAssertEqual(migrated.step, .welcome)
                XCTAssertTrue(migrated.isCompleted); XCTAssertTrue(migrated.isPresented)
                XCTAssertEqual(migrated.selectedTopicIDs, ["culture"])
                XCTAssertEqual(memory.writes, writes); XCTAssertEqual(memory.data, before)

                memory.failWrite = true
                XCTAssertFalse(migrated.advance()); XCTAssertNotNil(migrated.storageError)
                XCTAssertEqual(migrated.step, .welcome)
                XCTAssertTrue(migrated.isCompleted); XCTAssertTrue(migrated.isPresented)
                XCTAssertEqual(migrated.selectedTopicIDs, ["culture"])
                XCTAssertEqual(memory.data, before)
                memory.failWrite = false
                XCTAssertTrue(migrated.retry()); XCTAssertNil(migrated.storageError)
                XCTAssertEqual(migrated.step, .interests)
                let record = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(memory.data)) as? [String: Any])
                XCTAssertEqual(record["schemaVersion"] as? Int, 3)
                XCTAssertEqual(record["completed"] as? Bool, true)
                XCTAssertEqual(record["replaying"] as? Bool, true)

                let resumed = ReaderIntroductionModel(storage: memory.storage)
                bind(resumed, canonical); XCTAssertTrue(resumed.start())
                XCTAssertEqual(resumed.step, .interests); XCTAssertTrue(resumed.isPresented)
                XCTAssertEqual(resumed.selectedTopicIDs, ["culture"])
                XCTAssertTrue(resumed.complete()); XCTAssertFalse(resumed.isPresented)
                let completed = ReaderIntroductionModel(storage: memory.storage)
                bind(completed, canonical); XCTAssertTrue(completed.start())
                XCTAssertTrue(completed.isCompleted); XCTAssertFalse(completed.isPresented)
            }
        }
    }

    func testLegacyMigrationNeverTransfersAnotherOwnersDraft() throws {
        for version in [1, 2] {
            for completed in [false, true] {
                for replaying in (completed ? [false, true] : [false]) {
                    let memory = Memory(), canonical = guest()
                    canonical.adopt(account("A"))
                    let old = ReaderIntroductionModel(storage: memory.storage)
                    bind(old, canonical); old.start(); old.setSelectedTopicIDs(["private-topic"])
                    try legacyRecord(memory, step: .interests, schemaVersion: version, completed: completed, replaying: replaying)
                    canonical.adopt(account("B"))
                    let migrated = ReaderIntroductionModel(storage: memory.storage)
                    bind(migrated, canonical); XCTAssertTrue(migrated.start())
                    XCTAssertEqual(migrated.step, .welcome); XCTAssertEqual(migrated.selectedTopicIDs, [])
                    XCTAssertEqual(migrated.isCompleted, completed); XCTAssertEqual(migrated.isPresented, !completed)
                }
            }
        }
    }

    func testSchemaThreeInterruptedFlowResumesItsStepForTheSameGuestOrAccount() throws {
        for signedIn in [false, true] {
            for completed in [false, true] {
                for step in [ReaderIntroductionModel.Step.interests, .account] {
                    let memory = Memory(), canonical = guest()
                    if signedIn { canonical.adopt(account("reader")) }
                    let first = ReaderIntroductionModel(storage: memory.storage)
                    bind(first, canonical); first.start()
                    if completed { XCTAssertTrue(first.complete()); XCTAssertTrue(first.replay()) }
                    XCTAssertTrue(first.advance()); XCTAssertTrue(first.setSelectedTopicIDs(["culture"]))
                    if step == .account { XCTAssertTrue(first.advance()) }
                    let record = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(memory.data)) as? [String: Any])
                    XCTAssertEqual(record["schemaVersion"] as? Int, 3)
                    let writes = memory.writes
                    let restarted = ReaderIntroductionModel(storage: memory.storage)
                    bind(restarted, canonical); XCTAssertTrue(restarted.start())
                    XCTAssertEqual(restarted.step, step); XCTAssertEqual(restarted.selectedTopicIDs, ["culture"])
                    XCTAssertEqual(restarted.isCompleted, completed); XCTAssertTrue(restarted.isPresented)
                    XCTAssertEqual(memory.writes, writes)
                }
            }
        }
    }

    func testLegacyReadFailureRetryStartsAtWelcomeAndScopesChoicesToCurrentOwner() throws {
        for switchOwner in [false, true] {
            let memory = Memory(), canonical = guest()
            canonical.adopt(account("A"))
            let old = ReaderIntroductionModel(storage: memory.storage)
            bind(old, canonical); old.start(); old.setSelectedTopicIDs(["culture"])
            try legacyRecord(memory, step: .account, schemaVersion: 2)
            let before = memory.data, writes = memory.writes
            memory.failRead = true
            let migrated = ReaderIntroductionModel(storage: memory.storage)
            bind(migrated, canonical); XCTAssertFalse(migrated.start())
            XCTAssertFalse(migrated.hasLoaded); XCTAssertNotNil(migrated.storageError)
            if switchOwner { canonical.adopt(account("B")); bind(migrated, canonical) }
            memory.failRead = false
            XCTAssertTrue(migrated.retry()); XCTAssertNil(migrated.storageError)
            XCTAssertEqual(migrated.step, .welcome); XCTAssertFalse(migrated.isCompleted)
            XCTAssertEqual(migrated.selectedTopicIDs, switchOwner ? [] : ["culture"])
            XCTAssertEqual(memory.data, before); XCTAssertEqual(memory.writes, writes)
        }
    }

    func testLegacyAdvanceFailureRetriesSchemaThreeWithoutLosingSameOwnerDraft() throws {
        for step in [ReaderIntroductionModel.Step.interests, .account] {
            let memory = Memory(), canonical = guest()
            canonical.adopt(account("A"))
            let old = ReaderIntroductionModel(storage: memory.storage)
            bind(old, canonical); old.start(); old.setSelectedTopicIDs(["culture"])
            try legacyRecord(memory, step: step, schemaVersion: 2)
            let before = memory.data
            let migrated = ReaderIntroductionModel(storage: memory.storage)
            bind(migrated, canonical); XCTAssertTrue(migrated.start())
            memory.failWrite = true
            XCTAssertFalse(migrated.advance()); XCTAssertNotNil(migrated.storageError)
            XCTAssertEqual(migrated.step, .welcome); XCTAssertEqual(migrated.selectedTopicIDs, ["culture"])
            XCTAssertEqual(memory.data, before); XCTAssertFalse(migrated.isCompleted)
            memory.failWrite = false
            XCTAssertTrue(migrated.retry()); XCTAssertNil(migrated.storageError)
            XCTAssertEqual(migrated.step, .interests); XCTAssertEqual(migrated.selectedTopicIDs, ["culture"])
            let record = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(memory.data)) as? [String: Any])
            XCTAssertEqual(record["schemaVersion"] as? Int, 3)
            let restarted = ReaderIntroductionModel(storage: memory.storage)
            bind(restarted, canonical); XCTAssertTrue(restarted.start())
            XCTAssertEqual(restarted.step, .interests); XCTAssertEqual(restarted.selectedTopicIDs, ["culture"])
        }
    }

    func testLegacyPendingWriteCannotRetryAcrossAccountSwitchAndReturn() throws {
        let memory = Memory(), canonical = guest()
        canonical.adopt(account("A"))
        let old = ReaderIntroductionModel(storage: memory.storage)
        bind(old, canonical); old.start(); old.setSelectedTopicIDs(["private-topic"])
        try legacyRecord(memory, step: .account, schemaVersion: 2)
        let before = memory.data
        let migrated = ReaderIntroductionModel(storage: memory.storage)
        bind(migrated, canonical); XCTAssertTrue(migrated.start())
        memory.failWrite = true; XCTAssertFalse(migrated.advance())
        let writes = memory.writes
        memory.failWrite = false
        canonical.adopt(account("B")); bind(migrated, canonical)
        XCTAssertTrue(migrated.retry()); XCTAssertEqual(migrated.selectedTopicIDs, [])
        XCTAssertEqual(migrated.step, .welcome); XCTAssertEqual(memory.writes, writes)
        canonical.adopt(account("A")); bind(migrated, canonical)
        XCTAssertTrue(migrated.retry()); XCTAssertEqual(migrated.selectedTopicIDs, ["private-topic"])
        XCTAssertEqual(migrated.step, .welcome); XCTAssertEqual(memory.writes, writes)
        XCTAssertEqual(memory.data, before, "Returning to A must not revive the old generation's pending advance")
    }

    func testExactNewUserReceiptMovesToInterestsThenNewsletterWithoutCompletingEarly() throws {
        let memory = Memory(), canonical = guest(), model = ReaderIntroductionModel(storage: memory.storage)
        bind(model, canonical); model.start(); model.setSelectedTopicIDs(["music"])
        let ticket = try XCTUnwrap(model.beginAccountEntry(actionID: UUID()))
        XCTAssertEqual(ticket.originalContext, canonical.contextTicket())
        canonical.adopt(account("new-reader")); bind(model, canonical)
        XCTAssertEqual(model.step, .welcome, "A canonical login alone is not an introduction receipt")
        XCTAssertEqual(model.selectedTopicIDs, [])
        let result = try loginResult(ticket, canonical: canonical, isNewUser: true)
        XCTAssertTrue(model.acceptLogin(result, ticket: ticket))
        XCTAssertEqual(model.step, .interests); XCTAssertEqual(model.selectedTopicIDs, ["music"])
        XCTAssertTrue(model.isPresented); XCTAssertFalse(model.isCompleted)
        XCTAssertTrue(model.advance()); XCTAssertEqual(model.step, .account)
        XCTAssertFalse(model.isCompleted)
        XCTAssertTrue(model.complete()); XCTAssertTrue(model.isCompleted); XCTAssertFalse(model.isPresented)
        let restarted = ReaderIntroductionModel(storage: memory.storage)
        bind(restarted, canonical); XCTAssertTrue(restarted.start()); XCTAssertFalse(restarted.isPresented)
        XCTAssertFalse(model.acceptLogin(result, ticket: ticket), "A receipt is single-use")
    }

    func testExistingUserReceiptCompletesWithoutApplyingGuestDraftInterests() throws {
        let memory = Memory(), canonical = guest(), model = ReaderIntroductionModel(storage: memory.storage)
        bind(model, canonical); model.start(); model.setSelectedTopicIDs(["guest-choice"])
        let ticket = try XCTUnwrap(model.beginAccountEntry(actionID: UUID()))
        canonical.adopt(account("returning-reader")); bind(model, canonical)
        XCTAssertTrue(model.acceptLogin(try loginResult(ticket, canonical: canonical, isNewUser: false), ticket: ticket))
        XCTAssertTrue(model.isCompleted); XCTAssertFalse(model.isPresented)
        XCTAssertEqual(model.selectedTopicIDs, [])
        XCTAssertEqual(canonical.snapshot.session, account("returning-reader"))
    }

    func testUnrelatedActionAndOriginCannotConsumeCurrentIntroductionIntent() throws {
        let memory = Memory(), canonical = guest(), model = ReaderIntroductionModel(storage: memory.storage)
        bind(model, canonical); model.start()
        let ticket = try XCTUnwrap(model.beginAccountEntry(actionID: UUID()))
        let foreignGuest = guest()
        canonical.adopt(account("new-reader")); bind(model, canonical)
        let writes = memory.writes
        XCTAssertFalse(model.acceptLogin(try loginResult(ticket, canonical: canonical, isNewUser: true, actionID: UUID()), ticket: ticket))
        XCTAssertFalse(model.acceptLogin(try loginResult(ticket, canonical: canonical, isNewUser: true,
            originalContext: foreignGuest.contextTicket()), ticket: ticket))
        XCTAssertFalse(model.acceptLogin(try loginResult(ticket, canonical: canonical, isNewUser: true,
            session: account("other-reader")), ticket: ticket))
        XCTAssertEqual(memory.writes, writes); XCTAssertEqual(model.step, .welcome)
        XCTAssertTrue(model.acceptLogin(try loginResult(ticket, canonical: canonical, isNewUser: true), ticket: ticket))
    }

    func testCancelledEntryAndUnrelatedCanonicalLoginLeaveWelcomeIncomplete() throws {
        let memory = Memory(), canonical = guest(), model = ReaderIntroductionModel(storage: memory.storage)
        bind(model, canonical); model.start()
        let ticket = try XCTUnwrap(model.beginAccountEntry(actionID: UUID()))
        model.cancelAccountEntry(ticket)
        canonical.adopt(account("reader")); bind(model, canonical)
        XCTAssertFalse(model.acceptLogin(try loginResult(ticket, canonical: canonical, isNewUser: false), ticket: ticket))
        XCTAssertEqual(memory.writes, 0); XCTAssertEqual(model.step, .welcome)
        XCTAssertFalse(model.isCompleted)
    }

    func testSupersededEntryCannotCancelOrAcceptNewerEntry() throws {
        let memory = Memory(), canonical = guest(), model = ReaderIntroductionModel(storage: memory.storage)
        bind(model, canonical); model.start()
        let old = try XCTUnwrap(model.beginAccountEntry(actionID: UUID()))
        let latest = try XCTUnwrap(model.beginAccountEntry(actionID: UUID()))
        model.cancelAccountEntry(old)
        canonical.adopt(account("reader")); bind(model, canonical)
        XCTAssertFalse(model.acceptLogin(try loginResult(old, canonical: canonical, isNewUser: false), ticket: old))
        XCTAssertTrue(model.acceptLogin(try loginResult(latest, canonical: canonical, isNewUser: true), ticket: latest))
        XCTAssertEqual(model.step, .interests); XCTAssertFalse(model.isCompleted)
    }

    func testAccountSwitchAndUnresolvedTransitionInvalidateOriginalEntry() throws {
        for transitionThroughUnresolved in [false, true] {
            let memory = Memory(), canonical = guest(), model = ReaderIntroductionModel(storage: memory.storage)
            bind(model, canonical); model.start()
            let ticket = try XCTUnwrap(model.beginAccountEntry(actionID: UUID()))
            canonical.adopt(account("A")); bind(model, canonical)
            if transitionThroughUnresolved { canonical.suspend() }
            else { canonical.adopt(account("B")) }
            bind(model, canonical)
            canonical.adopt(account("A")); bind(model, canonical)
            XCTAssertFalse(model.acceptLogin(try loginResult(ticket, canonical: canonical, isNewUser: false), ticket: ticket))
            XCTAssertEqual(memory.writes, 0); XCTAssertFalse(model.isCompleted)
        }
    }

    func testStaleCanonicalReceiptFailsEvenBeforePresenterRebinds() throws {
        let memory = Memory(), canonical = guest(), model = ReaderIntroductionModel(storage: memory.storage)
        bind(model, canonical); model.start()
        let ticket = try XCTUnwrap(model.beginAccountEntry(actionID: UUID()))
        canonical.adopt(account("A")); bind(model, canonical)
        let stale = try loginResult(ticket, canonical: canonical, isNewUser: false)
        canonical.adopt(account("B"))
        XCTAssertFalse(model.acceptLogin(stale, ticket: ticket))
        XCTAssertEqual(memory.writes, 0); XCTAssertFalse(model.isCompleted)
    }

    func testFailedLoginTransitionRetriesExactNewOrExistingDecisionWithoutReusingReceipt() throws {
        for isNewUser in [false, true] {
            let memory = Memory(), canonical = guest(), model = ReaderIntroductionModel(storage: memory.storage)
            bind(model, canonical); model.start(); model.setSelectedTopicIDs(["culture"])
            let ticket = try XCTUnwrap(model.beginAccountEntry(actionID: UUID()))
            canonical.adopt(account("reader")); bind(model, canonical)
            let receipt = try loginResult(ticket, canonical: canonical, isNewUser: isNewUser)
            memory.failWrite = true
            XCTAssertFalse(model.acceptLogin(receipt, ticket: ticket))
            XCTAssertFalse(model.isCompleted); XCTAssertEqual(model.step, .welcome); XCTAssertNotNil(model.storageError)
            model.cancelAccountEntry(ticket)
            memory.failWrite = false
            XCTAssertTrue(model.retry()); XCTAssertNil(model.storageError)
            XCTAssertEqual(model.isCompleted, !isNewUser)
            XCTAssertEqual(model.isPresented, isNewUser)
            XCTAssertEqual(model.selectedTopicIDs, isNewUser ? ["culture"] : [])
            if isNewUser { XCTAssertEqual(model.step, .interests) }
            XCTAssertFalse(model.acceptLogin(receipt, ticket: ticket))
        }
    }

    func testFailedAcceptedLoginIsNotRetriedForAChangedAccount() throws {
        let memory = Memory(), canonical = guest(), model = ReaderIntroductionModel(storage: memory.storage)
        bind(model, canonical); model.start()
        let ticket = try XCTUnwrap(model.beginAccountEntry(actionID: UUID()))
        canonical.adopt(account("A")); bind(model, canonical)
        memory.failWrite = true
        XCTAssertFalse(model.acceptLogin(try loginResult(ticket, canonical: canonical, isNewUser: false), ticket: ticket))
        memory.failWrite = false
        canonical.adopt(account("B")); bind(model, canonical)
        let writes = memory.writes
        XCTAssertTrue(model.retry()); XCTAssertEqual(memory.writes, writes)
        XCTAssertFalse(model.isCompleted); XCTAssertEqual(model.selectedTopicIDs, [])
    }

    func testLoginCompletionRechecksOwnerAfterWillChangeBeforeStorageWrite() throws {
        let memory = Memory(), canonical = guest(), model = ReaderIntroductionModel(storage: memory.storage)
        bind(model, canonical); model.start()
        let ticket = try XCTUnwrap(model.beginAccountEntry(actionID: UUID()))
        canonical.adopt(account("A")); bind(model, canonical)
        let receipt = try loginResult(ticket, canonical: canonical, isNewUser: false)
        let subscription = model.objectWillChange.sink {
            canonical.adopt(self.account("B"))
            _ = model.bindContext(canonical.contextTicket(), isCurrent: canonical.isCurrent)
        }
        XCTAssertFalse(model.acceptLogin(receipt, ticket: ticket))
        XCTAssertEqual(memory.writes, 0); XCTAssertFalse(model.isCompleted)
        withExtendedLifetime(subscription) {}
    }

    func testManualReplayAlwaysStartsAtWelcomeForGuestAndSignedInReader() {
        for signedIn in [false, true] {
            for completed in [false, true] {
                let memory = Memory(), canonical = guest(), model = ReaderIntroductionModel(storage: memory.storage)
                if signedIn { canonical.adopt(account("reader")) }
                bind(model, canonical); model.start(); model.advance(); model.setSelectedTopicIDs(["culture"]); model.advance()
                if completed { XCTAssertTrue(model.complete()) }
                XCTAssertEqual(model.step, .account)
                XCTAssertTrue(model.replay()); XCTAssertEqual(model.step, .welcome)
                XCTAssertEqual(model.isCompleted, completed); XCTAssertTrue(model.isPresented)
                XCTAssertEqual(model.selectedTopicIDs, ["culture"])
                if signedIn { XCTAssertNil(model.beginAccountEntry(actionID: UUID())) }
            }
        }
    }

    func testGuestReplayStaysMountedAcrossAcceptedCanonicalPublication() throws {
        let memory = Memory(), canonical = guest(), model = ReaderIntroductionModel(storage: memory.storage)
        bind(model, canonical); model.start(); model.complete(); model.replay()
        let ticket = try XCTUnwrap(model.beginAccountEntry(actionID: UUID()))
        canonical.adopt(account("new-reader")); bind(model, canonical)
        XCTAssertTrue(model.isPresented, "Publishing the account must not tear down the pending provider view")
        XCTAssertTrue(model.isCompleted); XCTAssertEqual(model.step, .welcome)
        XCTAssertTrue(model.acceptLogin(try loginResult(ticket, canonical: canonical, isNewUser: true), ticket: ticket))
        XCTAssertTrue(model.isPresented); XCTAssertEqual(model.step, .interests)
        XCTAssertTrue(model.complete()); XCTAssertFalse(model.isPresented)
    }

    private func manualExistingReader() throws -> (ReaderIntroductionModel, Memory, CanonicalSessionState) {
        let memory = Memory(), canonical = guest(), model = ReaderIntroductionModel(storage: memory.storage)
        bind(model, canonical); XCTAssertTrue(model.start()); XCTAssertTrue(model.complete()); XCTAssertTrue(model.replay())
        XCTAssertTrue(model.setSelectedTopicIDs(["guest-only"]))
        let ticket = try XCTUnwrap(model.beginAccountEntry(actionID: UUID()))
        canonical.adopt(account("returning-reader")); bind(model, canonical)
        XCTAssertTrue(model.acceptLogin(try loginResult(ticket, canonical: canonical, isNewUser: false), ticket: ticket))
        XCTAssertTrue(model.isAwaitingSavedInterests); XCTAssertEqual(model.selectedTopicIDs, [])
        return (model, memory, canonical)
    }

    func testManualExistingSeedIsLocalSingleUseAndColdDraftKeepsCurrentAccountChoices() throws {
        let (model, memory, canonical) = try manualExistingReader(), context = canonical.contextTicket()
        let writes = memory.writes
        XCTAssertTrue(model.seedSavedInterests(["culture", "music"], context: context, stillCurrent: { canonical.isCurrent(context) }))
        XCTAssertEqual(memory.writes, writes + 1); XCTAssertFalse(model.isAwaitingSavedInterests)
        XCTAssertEqual(model.selectedTopicIDs, ["culture", "music"])
        XCTAssertFalse(model.seedSavedInterests(["late"], context: context, stillCurrent: { true }))
        let restarted = ReaderIntroductionModel(storage: memory.storage)
        bind(restarted, canonical); XCTAssertTrue(restarted.start())
        XCTAssertEqual(restarted.selectedTopicIDs, ["culture", "music"])
        let record = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(memory.data)) as? [String: Any])
        XCTAssertEqual(record["schemaVersion"] as? Int, 3)
        XCTAssertEqual(Set(record.keys), ["schemaVersion", "completed", "replaying", "step", "selectedTopicIDs", "draftOwner"])
    }

    func testManualExistingLateSeedCannotOverwriteEditSkipBackOrAnotherAccount() throws {
        for action in 0..<4 {
            let (model, memory, canonical) = try manualExistingReader(), context = canonical.contextTicket()
            switch action {
            case 0: XCTAssertTrue(model.setSelectedTopicIDs(["deliberate-edit"]))
            case 1: XCTAssertTrue(model.advance())
            case 2: XCTAssertTrue(model.back())
            default: canonical.adopt(account("another-reader")); bind(model, canonical)
            }
            let bytes = memory.data, writes = memory.writes, selection = model.selectedTopicIDs
            XCTAssertFalse(model.seedSavedInterests(["old-account-choice"], context: context, stillCurrent: { true }))
            XCTAssertEqual(memory.data, bytes); XCTAssertEqual(memory.writes, writes)
            XCTAssertEqual(model.selectedTopicIDs, selection); XCTAssertFalse(model.isAwaitingSavedInterests)
        }
    }

    func testManualExistingSeedRechecksSourceAfterPublicationAndDoesNotWriteStaleSnapshot() throws {
        let (model, memory, canonical) = try manualExistingReader(), context = canonical.contextTicket()
        let writes = memory.writes
        XCTAssertFalse(model.seedSavedInterests(["unconfirmed"], context: context, stillCurrent: { false }))
        var sourceCurrent = true
        let subscription = model.objectWillChange.sink { sourceCurrent = false }
        XCTAssertFalse(model.seedSavedInterests(["became-stale"], context: context, stillCurrent: { sourceCurrent }))
        XCTAssertEqual(memory.writes, writes); XCTAssertEqual(model.selectedTopicIDs, [])
        XCTAssertTrue(model.isAwaitingSavedInterests)
        subscription.cancel()
        XCTAssertTrue(model.seedSavedInterests(["fresh"], context: context, stillCurrent: { true }))
        XCTAssertEqual(model.selectedTopicIDs, ["fresh"])
    }

    func testManualExistingSeedStorageFailureBlocksContinueUntilExactLocalRetry() throws {
        let (model, memory, canonical) = try manualExistingReader(), context = canonical.contextTicket()
        memory.failWrite = true
        XCTAssertFalse(model.seedSavedInterests(["culture"], context: context, stillCurrent: { true }))
        XCTAssertNotNil(model.storageError); XCTAssertTrue(model.isAwaitingSavedInterests)
        XCTAssertEqual(model.selectedTopicIDs, [])
        memory.failWrite = false
        XCTAssertTrue(model.retry()); XCTAssertFalse(model.isAwaitingSavedInterests)
        XCTAssertEqual(model.selectedTopicIDs, ["culture"]); XCTAssertTrue(model.isPresented)
    }

    func testManualExistingFailedSeedCannotRetryOldPreferenceRevision() throws {
        let (model, memory, canonical) = try manualExistingReader(), context = canonical.contextTicket()
        var originalSourceIsCurrent = true
        memory.failWrite = true
        XCTAssertFalse(model.seedSavedInterests(["old-source"], context: context,
            stillCurrent: { originalSourceIsCurrent }))
        let writes = memory.writes
        originalSourceIsCurrent = false; memory.failWrite = false
        let failedRevision = model.snapshot.revision
        var feedAttempts = 0
        // Feed the fresh snapshot only in response to actual model publication,
        // as the presentation's revision observer does; no extra manual seed.
        let subscription = model.changes.sink { _ in
            guard model.isAwaitingSavedInterests else { return }
            feedAttempts += 1
            XCTAssertTrue(model.seedSavedInterests(["new-source"], context: context, stillCurrent: { true }))
        }
        XCTAssertFalse(model.retry()); XCTAssertEqual(memory.writes, writes + 1)
        XCTAssertNotEqual(model.snapshot.revision, failedRevision); XCTAssertNil(model.storageError)
        XCTAssertEqual(feedAttempts, 1)
        XCTAssertFalse(model.isAwaitingSavedInterests); XCTAssertEqual(model.selectedTopicIDs, ["new-source"])
        withExtendedLifetime(subscription) {}
    }

    func testManualExistingSeedRetryReentryPreservesNewerFailedDraftProposal() throws {
        let (model, memory, canonical) = try manualExistingReader(), context = canonical.contextTicket()
        var editDuringSourceCheck = false
        memory.failWrite = true
        XCTAssertFalse(model.seedSavedInterests(["old-source"], context: context, stillCurrent: {
            if editDuringSourceCheck {
                editDuringSourceCheck = false
                XCTAssertFalse(model.setSelectedTopicIDs(["newer-deliberate-edit"]))
                return false
            }
            return true
        }))
        editDuringSourceCheck = true
        XCTAssertFalse(model.retry())
        XCTAssertFalse(model.isAwaitingSavedInterests); XCTAssertNotNil(model.storageError)
        memory.failWrite = false
        XCTAssertTrue(model.retry(), "Retiring an old seed must not clear the newer failed edit's pending bytes")
        XCTAssertEqual(model.selectedTopicIDs, ["newer-deliberate-edit"])
    }

    func testManualExistingSeedSourceCheckCannotConsumeReentrantNewReservation() throws {
        let (model, memory, canonical) = try manualExistingReader(), context = canonical.contextTicket()
        var writesAfterNewReservation = 0
        XCTAssertFalse(model.seedSavedInterests(["old-source"], context: context, stillCurrent: {
            XCTAssertTrue(model.back()); XCTAssertTrue(model.advance())
            writesAfterNewReservation = memory.writes
            return true
        }))
        XCTAssertEqual(memory.writes, writesAfterNewReservation); XCTAssertEqual(model.selectedTopicIDs, [])
        XCTAssertTrue(model.isAwaitingSavedInterests)
        XCTAssertTrue(model.seedSavedInterests(["current-source"], context: context, stillCurrent: { true }))
        XCTAssertEqual(model.selectedTopicIDs, ["current-source"])
    }

    func testAlreadySignedInManualReplaySeedsOnlyAfterContinueWithoutProviderLogin() {
        for completed in [false, true] {
            let memory = Memory(), canonical = guest(), model = ReaderIntroductionModel(storage: memory.storage)
            canonical.adopt(account("current-reader")); bind(model, canonical); model.start()
            if completed { XCTAssertTrue(model.complete()) }
            XCTAssertTrue(model.replay()); XCTAssertEqual(model.step, .welcome)
            XCTAssertNil(model.beginAccountEntry(actionID: UUID()))
            XCTAssertTrue(model.advance()); XCTAssertTrue(model.isAwaitingSavedInterests)
            let context = canonical.contextTicket()
            XCTAssertTrue(model.seedSavedInterests(["culture"], context: context, stillCurrent: { canonical.isCurrent(context) }))
            XCTAssertEqual(model.isCompleted, completed); XCTAssertEqual(model.selectedTopicIDs, ["culture"])
            XCTAssertTrue(model.advance()); XCTAssertEqual(model.step, .account)
        }
    }

    func testManualReplayExplicitEmptyAndNonemptyDraftSurviveBackWelcomeAndContinue() throws {
        for deliberateChoice in [[], ["music"]] as [[String]] {
            let (model, memory, canonical) = try manualExistingReader(), context = canonical.contextTicket()
            XCTAssertTrue(model.seedSavedInterests(["culture"], context: context, stillCurrent: { true }))
            XCTAssertTrue(model.setSelectedTopicIDs(deliberateChoice))
            XCTAssertTrue(model.back()); XCTAssertEqual(model.step, .welcome)
            XCTAssertTrue(model.advance()); XCTAssertEqual(model.step, .interests)
            XCTAssertFalse(model.isAwaitingSavedInterests)
            let bytes = memory.data, writes = memory.writes
            XCTAssertFalse(model.seedSavedInterests(["culture"], context: context, stillCurrent: { true }))
            XCTAssertEqual(model.selectedTopicIDs, deliberateChoice)
            XCTAssertEqual(memory.data, bytes); XCTAssertEqual(memory.writes, writes)
        }
    }

    func testManualReplayProviderCancellationKeepsIntentButUnrelatedEpochRetiresIt() throws {
        for unrelatedEpoch in [false, true] {
            let memory = Memory(), canonical = guest(), model = ReaderIntroductionModel(storage: memory.storage)
            bind(model, canonical); model.start(); model.replay()
            let cancelled = try XCTUnwrap(model.beginAccountEntry(actionID: UUID()))
            model.cancelAccountEntry(cancelled)
            if unrelatedEpoch { canonical.adopt(nil, forceNewGeneration: true); bind(model, canonical) }
            let ticket = try XCTUnwrap(model.beginAccountEntry(actionID: UUID()))
            canonical.adopt(account("reader")); bind(model, canonical)
            XCTAssertTrue(model.acceptLogin(try loginResult(ticket, canonical: canonical, isNewUser: false), ticket: ticket))
            XCTAssertEqual(model.isPresented, !unrelatedEpoch)
            XCTAssertEqual(model.step, unrelatedEpoch ? .welcome : .interests)
        }
    }

    func testPermissionReentryCancelsLoginReceiptBeforeAnyWrite() throws {
        let memory = Memory(), canonical = guest(), model = ReaderIntroductionModel(storage: memory.storage)
        var cancelDuringPermission: (() -> Void)?
        func isCurrent(_ context: CanonicalSessionState.ContextTicket) -> Bool {
            let callback = cancelDuringPermission
            cancelDuringPermission = nil
            callback?()
            return canonical.isCurrent(context)
        }
        XCTAssertTrue(model.bindContext(canonical.contextTicket(), isCurrent: isCurrent)); model.start()
        let ticket = try XCTUnwrap(model.beginAccountEntry(actionID: UUID()))
        canonical.adopt(account("reader"))
        XCTAssertTrue(model.bindContext(canonical.contextTicket(), isCurrent: isCurrent))
        let receipt = try loginResult(ticket, canonical: canonical, isNewUser: false)
        cancelDuringPermission = { model.cancelAccountEntry(ticket) }
        XCTAssertFalse(model.acceptLogin(receipt, ticket: ticket))
        XCTAssertEqual(memory.writes, 0); XCTAssertFalse(model.isCompleted)
    }

    func testGuestCompletionRevokesPendingProviderReceiptWithoutCreatingAnAccount() throws {
        let memory = Memory(), canonical = guest(), model = ReaderIntroductionModel(storage: memory.storage)
        bind(model, canonical); model.start()
        let ticket = try XCTUnwrap(model.beginAccountEntry(actionID: UUID()))
        XCTAssertTrue(model.skip()); XCTAssertEqual(canonical.snapshot.context, .guest)
        canonical.adopt(account("reader")); bind(model, canonical)
        let writes = memory.writes
        XCTAssertFalse(model.acceptLogin(try loginResult(ticket, canonical: canonical, isNewUser: true), ticket: ticket))
        XCTAssertEqual(memory.writes, writes); XCTAssertTrue(model.isCompleted); XCTAssertFalse(model.isPresented)
    }
}

extension ReaderIntroductionModelTests {
    func testGuestReentrantPermissionCannotCommitSupersededDraft() {
        let memory = Memory(), canonical = guest(), model = GuestReaderInterestsModel(storage: memory.storage)
        model.start(); let ticket = canonical.contextTicket()
        var nested = false
        XCTAssertFalse(model.save(["old"], context: ticket, isCurrent: { original in
            if !nested {
                nested = true
                XCTAssertTrue(model.save(["new"], context: ticket, isCurrent: canonical.isCurrent))
            }
            return canonical.isCurrent(original)
        }))
        XCTAssertEqual(model.selectedTopicIDs, ["new"]); XCTAssertEqual(memory.writes, 1)
    }

    func testGuestCorruptionIsNotSilentlyReplacedAndValidIdsAreBounded() {
        let memory = Memory(), canonical = guest()
        memory.data = Data(#"{"schemaVersion":99,"selectedTopicIDs":["old"]}"#.utf8)
        let model = GuestReaderInterestsModel(storage: memory.storage)
        XCTAssertFalse(model.start()); XCTAssertFalse(model.hasLoaded)
        XCTAssertFalse(model.save(["new"], context: canonical.contextTicket(), isCurrent: canonical.isCurrent))
        XCTAssertEqual(memory.writes, 0)
        memory.data = nil
        XCTAssertTrue(model.start())
        XCTAssertTrue(model.save((0..<25).map { "topic-\($0)" } + ["", "topic-1", "invalid/path"],
            context: canonical.contextTicket(), isCurrent: canonical.isCurrent))
        XCTAssertEqual(model.selectedTopicIDs.count, 20)
    }

    func testFailedCompletionIsNotRetriedAfterAnotherAcceptedDraftAction() {
        let memory = Memory(), canonical = guest(), model = ReaderIntroductionModel(storage: memory.storage)
        bind(model, canonical); model.start()
        memory.failWrite = true; XCTAssertFalse(model.complete())
        memory.failWrite = false; XCTAssertTrue(model.setSelectedTopicIDs(["music"]))
        XCTAssertTrue(model.retry()); XCTAssertFalse(model.isCompleted); XCTAssertTrue(model.isPresented)
        XCTAssertEqual(model.selectedTopicIDs, ["music"])
    }

    func testUnresolvedBindingRevokesVisibleDraftAndOldTicketCannotWrite() {
        let memory = Memory(), canonical = guest(), model = ReaderIntroductionModel(storage: memory.storage)
        bind(model, canonical); model.start(); model.setSelectedTopicIDs(["private"])
        canonical.suspend(); bind(model, canonical)
        XCTAssertEqual(model.selectedTopicIDs, []); XCTAssertFalse(model.isPresented)
        let writes = memory.writes
        XCTAssertFalse(model.complete()); XCTAssertEqual(memory.writes, writes)
        canonical.adopt(nil); bind(model, canonical)
        XCTAssertEqual(model.selectedTopicIDs, ["private"], "The same stable guest owner may resume its own accepted draft")
    }
}
