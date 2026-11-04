import Combine
import Foundation
import XCTest
@testable import Apropos

@MainActor
final class ReaderLaunchRecoveryTests: XCTestCase {
    func testColdClosedStartReplayAndCleanupDoNotConsumeLaterNormalStartup() {
        var allowed = false
        let coordinator = ReaderLaunchCoordinator(presentationAllowed: { allowed })
        coordinator.start(needsIntroduction: true, needsWhatsNew: true, blocked: false)
        coordinator.replay(); coordinator.suspend(); coordinator.coverDidDismiss(); coordinator.sheetDidDismiss()
        XCTAssertTrue(coordinator.isIdle); XCTAssertNil(coordinator.cover); XCTAssertNil(coordinator.sheet)
        allowed = true
        coordinator.start(needsIntroduction: true, needsWhatsNew: true, blocked: false)
        XCTAssertEqual(coordinator.cover?.kind, .introduction)
        XCTAssertNil(coordinator.sheet)
    }

    func testObservedDenialAfterPresentationCannotBeReopenedByStaleFallback() {
        var allowed = true
        let coordinator = ReaderLaunchCoordinator(presentationAllowed: { allowed })
        coordinator.replay()
        XCTAssertNotNil(coordinator.cover)
        allowed = false; coordinator.suspend()
        XCTAssertNil(coordinator.cover); XCTAssertTrue(coordinator.isAwaitingDismissal)
        coordinator.coverDidDismiss()
        XCTAssertTrue(coordinator.isIdle)
        allowed = true
        coordinator.replay()
        coordinator.start(needsIntroduction: false, needsWhatsNew: true, blocked: false)
        XCTAssertNil(coordinator.cover); XCTAssertNil(coordinator.sheet)
    }

    func testPendingAccountAndNewsletterCannotOpenFromDismissalAfterClosure() {
        let followUps: [ReaderLaunchCoordinator.FollowUp] = [.account(.init(topicIDs: ["music"])), .newsletter]
        for followUp in followUps {
            var allowed = true
            let coordinator = ReaderLaunchCoordinator(presentationAllowed: { allowed })
            coordinator.replay(); coordinator.finishIntroduction(then: followUp)
            XCTAssertTrue(coordinator.isAwaitingDismissal)
            allowed = false
            coordinator.coverDidDismiss()
            XCTAssertNil(coordinator.sheet); XCTAssertNil(coordinator.cover)
            XCTAssertTrue(coordinator.isIdle, "The original dismissal barrier may finish while admission is closed")
            allowed = true; coordinator.replay()
            XCTAssertTrue(coordinator.isIdle, "The old handoff must not recover authority from a later open value")
        }
    }

    func testColdClosedWhatsNewDoesNotPresentUntilFreshAllowedStartup() {
        var allowed = false
        let coordinator = ReaderLaunchCoordinator(presentationAllowed: { allowed })
        coordinator.start(needsIntroduction: false, needsWhatsNew: true, blocked: false)
        XCTAssertNil(coordinator.sheet)
        allowed = true
        coordinator.start(needsIntroduction: false, needsWhatsNew: true, blocked: false)
        XCTAssertEqual(coordinator.sheet?.kind, .whatsNew)
        allowed = false; coordinator.dismissSheet(); coordinator.sheetDidDismiss()
        XCTAssertTrue(coordinator.isIdle)
        allowed = true; coordinator.replay()
        XCTAssertNil(coordinator.cover)
    }

    func testDenialInsideWillChangeRevokesPresentationBeforeStartReturns() {
        var allowed = true, closed = false
        let coordinator = ReaderLaunchCoordinator(presentationAllowed: { allowed })
        let observation = coordinator.objectWillChange.sink {
            if !closed, coordinator.cover != nil { closed = true; allowed = false }
        }
        coordinator.start(needsIntroduction: true, needsWhatsNew: false, blocked: false)
        XCTAssertTrue(closed)
        XCTAssertNil(coordinator.cover); XCTAssertTrue(coordinator.isAwaitingDismissal)
        coordinator.coverDidDismiss()
        allowed = true; coordinator.replay()
        XCTAssertTrue(coordinator.isIdle)
        withExtendedLifetime(observation) { }
    }

    func testPermissionChangedByHookIsRecheckedBeforePendingHandoffCommits() {
        var allowed = true, revokeOnCheck = false
        let coordinator = ReaderLaunchCoordinator(presentationAllowed: {
            let original = allowed
            if revokeOnCheck { revokeOnCheck = false; allowed = false }
            return original
        })
        coordinator.replay()
        revokeOnCheck = true
        coordinator.finishIntroduction(then: .newsletter)
        XCTAssertNil(coordinator.cover); XCTAssertNil(coordinator.sheet)
        coordinator.coverDidDismiss()
        XCTAssertTrue(coordinator.isIdle)
    }

    func testReentrantDismissalPermissionHookIsBoundedAndCannotOpenPendingSheet() {
        var hook: (() -> Void)?
        var calls = 0
        let coordinator = ReaderLaunchCoordinator(presentationAllowed: {
            calls += 1; hook?(); return true
        })
        coordinator.replay(); coordinator.finishIntroduction(then: .account(.init(topicIDs: ["music"])))
        let before = calls
        hook = { coordinator.coverDidDismiss() }
        coordinator.coverDidDismiss()
        XCTAssertEqual(calls - before, 1, "Recursive permission checks must not recurse or manufacture authorization")
        XCTAssertNil(coordinator.sheet); XCTAssertTrue(coordinator.isAwaitingDismissal)
        hook = nil
        coordinator.coverDidDismiss()
        XCTAssertEqual(coordinator.sheet?.kind, .account)
        XCTAssertEqual(coordinator.sheet?.selectedTopicIDs, ["music"])
    }

    func testOldPublicationCannotClearNewPresentationCreatedBySubscriberCleanup() {
        let coordinator = ReaderLaunchCoordinator()
        var armed = true
        var oldID: UUID?, replacementID: UUID?
        let observation = coordinator.objectWillChange.sink {
            guard armed, let original = coordinator.cover else { return }
            armed = false; oldID = original.id
            coordinator.suspend(); coordinator.coverDidDismiss(); coordinator.replay()
            replacementID = coordinator.cover?.id
        }
        coordinator.replay()
        XCTAssertNotNil(oldID); XCTAssertNotNil(replacementID)
        XCTAssertNotEqual(oldID, replacementID)
        XCTAssertEqual(coordinator.cover?.id, replacementID)
        XCTAssertFalse(coordinator.isAwaitingDismissal)
        withExtendedLifetime(observation) { }
    }

    func testDenialDuringAccountAppearanceCannotKeepOrReplaceItsSheet() {
        var allowed = true
        let coordinator = ReaderLaunchCoordinator(presentationAllowed: { allowed })
        coordinator.replay(); coordinator.finishIntroduction(then: .account(.init(topicIDs: ["private-a"])))
        coordinator.coverDidDismiss()
        XCTAssertEqual(coordinator.sheet?.kind, .account)
        allowed = false; coordinator.accountDidAppear()
        XCTAssertNil(coordinator.sheet); XCTAssertTrue(coordinator.isAwaitingDismissal)
        coordinator.sheetDidDismiss()
        allowed = true; coordinator.replay()
        XCTAssertTrue(coordinator.isIdle)
    }

    func testActualRecoveryKeepsOpenStorageErrorFallbackButRejectsItAfterSeal() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("reader-launch-recovery-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let recovery = ReaderTransitionRecovery(store: ReaderTransitionRecoveryStore(rootDirectory: root))
        try await recovery.bootstrap()
        var reads = 0, writes = 0
        let model = ReaderIntroductionModel(storage: .init(read: {
            reads += 1; return Data("malformed local introduction".utf8)
        }, write: { _ in writes += 1 }), recovery: recovery)
        let canonical = CanonicalSessionState(); canonical.adopt(nil)
        XCTAssertTrue(model.bindContext(canonical.contextTicket(), isCurrent: canonical.isCurrent))
        let coordinator = ReaderLaunchCoordinator(presentationAllowed: { model.permitsIntroduction })
        let observation = model.changes.sink { _ in
            if !model.permitsIntroduction { coordinator.suspend() }
        }
        XCTAssertFalse(model.start()); XCTAssertNotNil(model.storageError)
        coordinator.replay()
        XCTAssertEqual(coordinator.cover?.kind, .introduction, "The existing local storage-error retry screen remains usable")
        let originalReads = reads
        _ = try await recovery.seal(binding: .init(ownerUID: "reader-a", epoch: 7))
        XCTAssertFalse(model.permitsIntroduction)
        XCTAssertFalse(model.start())
        coordinator.replay(); coordinator.coverDidDismiss(); coordinator.replay()
        XCTAssertNil(coordinator.cover); XCTAssertNil(coordinator.sheet)
        XCTAssertEqual(reads, originalReads); XCTAssertEqual(writes, 0)
        withExtendedLifetime(observation) { }
    }
}
