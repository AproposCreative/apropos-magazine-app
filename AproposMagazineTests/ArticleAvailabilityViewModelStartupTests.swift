import FirebaseCore
import XCTest
@testable import Apropos

/// Actual VM -> service projection -> availability model. All subscriptions,
/// deadlines, persistence and startup verification are injected local effects.
@MainActor
final class ArticleAvailabilityViewModelStartupTests: XCTestCase {
    private typealias VM = ArticleViewModel
    private typealias Service = ArticleAvailabilityService
    private typealias Startup = ReaderStartupCoordinator
    private typealias Contract = ReaderAuthoritativeReadContract

    @MainActor private final class Fixture {
        struct Subscription {
            let articleID: String
            let permission: Service.CurrentGuard
            let completion: @MainActor (Result<Service.Document, Error>) -> Void
        }
        let identity = CanonicalSessionState()
        let sdk: ReaderSDKStartupState
        var actualUID: String?
        var subscriptions: [Subscription] = []
        var cancellations: [Int] = []
        var mirrors: [String] = []
        var saves: [ArticleAvailabilityModel.Snapshot] = []
        var deadlines: [() -> Void] = []
        var onSubscribe: ((Int) -> Void)?
        var onCancel: ((Int) -> Void)?
        var sdkStarts = 0
        lazy var model = ArticleAvailabilityModel(save: { [unowned self] in self.saves.append($0) },
            schedule: { [unowned self] fire in self.deadlines.append(fire); return {} })
        lazy var vm = makeVM()
        func makeVM() -> VM {
            VM(startup: sdk, identity: identity, actualUserID: { [unowned self] in self.actualUID },
            readEffects: VM.ReadEffects(), availabilityModel: model,
            availabilitySubscribe: { [unowned self] id, permission, completion in
                XCTAssertTrue(permission())
                let index = self.subscriptions.count
                self.subscriptions.append(.init(articleID: id, permission: permission, completion: completion))
                self.onSubscribe?(index)
                return { [weak self] in
                    guard let self else { return }
                    self.cancellations.append(index)
                    self.onCancel?(index)
                }
            }, availabilityMirror: { [unowned self] id, _ in self.mirrors.append(id) })
        }

        init(guarded: Bool = false, uid: String? = "A") {
            sdk = guarded ? ReaderSDKStartupState() : .application
            actualUID = uid
            _ = identity.adopt(uid.map(Self.session))
        }
        static func session(_ uid: String) -> ReaderAccountSession {
            .init(uid: uid, email: "reader@example.invalid", isEmailVerified: true)
        }
        func select(_ uid: String?) {
            actualUID = uid
            _ = identity.adopt(uid.map(Self.session))
        }
        func withdraw(_ index: Int) {
            subscriptions[index].completion(.success(.init(exists: false, isFromCache: false,
                hasPendingWrites: false, data: [:])))
        }
        func publish(_ index: Int) {
            let id = subscriptions[index].articleID
            subscriptions[index].completion(.success(.init(exists: true, isFromCache: false,
                hasPendingWrites: false, data: ["id": id, "isDraft": false, "isArchived": false,
                    "lastPublished": "2026-10-24T01:00:00.000Z",
                    "fieldData": ["name": "En lokal artikel", "slug": id, "content": "<p>Tekst</p>"]])))
        }

        /// Open the guarded state through the real coordinator, strict wire
        /// decoder and final admission callback. No real SDK is initialized.
        func openGuardedStartup() async throws {
            let configuration = try Startup.Configuration(projectID: "local-availability-fixture", appID: "local-app",
                installationID: UUID(), writerFenceRevision: String(repeating: "a", count: 64),
                migrationRevision: String(repeating: "b", count: 64))
            let membership: @MainActor (Contract.MembershipRequest) async throws -> Contract.MembershipSnapshot = { request in
                let echoed = try JSONSerialization.jsonObject(with: Contract.encode(request))
                let data = try JSONSerialization.data(withJSONObject: [
                    "schemaVersion": 1, "scope": Contract.membershipScope, "request": echoed,
                    "membership": ["schemaVersion": 1, "ownerUID": request.expectedUID, "epoch": 4, "state": "active"],
                    "validUntilMs": 20_000
                ])
                return try Contract.decodeMembershipResponse(data: data, for: request)
            }
            let verifier: Startup.Verifier = { challenge in
                .init(challenge: challenge, coverage: .allPersistedWritersIncludingPreviousAccounts,
                    writerFenceRevision: configuration.writerFenceRevision,
                    migrationRevision: configuration.migrationRevision, validUntilMs: 20_000)
            }
            let starter: @MainActor (Startup.Receipt, @escaping Startup.StartAdmission) async throws -> Void = { [unowned self] _, admit in
                try admit(); self.sdkStarts += 1
            }
            let coordinator = Startup(canonical: identity, sdkState: sdk, configuration: configuration,
                readMarker: { nil }, readMembership: membership, verify: verifier, startSDK: starter,
                now: { 10_000 }, schedule: { _ in {} })
            _ = try await coordinator.start(context: identity.contextTicket())
        }
    }

    override func setUp() { super.setUp(); XCTAssertNil(FirebaseApp.allApps) }
    override func tearDown() { XCTAssertNil(FirebaseApp.allApps); super.tearDown() }

    func testClosedSelectionStartsOnceAfterRealStartupWithoutCallingVMStart() async throws {
        let f = Fixture(guarded: true)
        _ = f.vm
        XCTAssertTrue(f.subscriptions.isEmpty); XCTAssertTrue(f.deadlines.isEmpty)
        let selection = f.vm.observeArticleAvailability(for: "story")
        f.vm.resumeReaderStartup()
        XCTAssertTrue(f.subscriptions.isEmpty); XCTAssertTrue(f.mirrors.isEmpty)
        XCTAssertTrue(f.saves.isEmpty); XCTAssertNil(f.model.checkingID)
        try await f.openGuardedStartup()
        f.vm.resumeReaderStartup(); f.vm.resumeReaderStartup()
        XCTAssertEqual(f.sdkStarts, 1); XCTAssertEqual(f.subscriptions.count, 1)
        XCTAssertEqual(f.model.checkingID, "story")
        f.publish(0)
        XCTAssertNotNil(f.model.approvedRevision(for: "story")); XCTAssertNil(f.model.checkingID)
        f.vm.stopObservingArticleAvailability(selection)
        XCTAssertEqual(f.cancellations, [0])
    }

    func testViewStopWhileClosedClearsWantedSelectionBeforeStartupOpens() async throws {
        let f = Fixture(guarded: true)
        let selection = f.vm.observeArticleAvailability(for: "story")
        f.vm.stopObservingArticleAvailability(selection)
        try await f.openGuardedStartup()
        f.vm.resumeReaderStartup(); f.vm.resumeReaderStartup()
        XCTAssertTrue(f.subscriptions.isEmpty); XCTAssertTrue(f.deadlines.isEmpty)
        XCTAssertTrue(f.mirrors.isEmpty); XCTAssertTrue(f.saves.isEmpty)
    }

    func testOldSameArticleViewCannotStopNewSelectionOrPublishItsLateResult() {
        let f = Fixture()
        let first = f.vm.observeArticleAvailability(for: "story")
        let second = f.vm.observeArticleAvailability(for: "story")
        XCTAssertNotEqual(first, second); XCTAssertEqual(f.subscriptions.count, 2)
        XCTAssertEqual(f.cancellations, [0])
        f.vm.stopObservingArticleAvailability(first)
        XCTAssertEqual(f.cancellations, [0]); XCTAssertTrue(f.subscriptions[1].permission())
        f.withdraw(0)
        XCTAssertTrue(f.model.withdrawnIDs.isEmpty); XCTAssertTrue(f.mirrors.isEmpty)
        f.withdraw(1)
        XCTAssertEqual(f.model.withdrawnIDs, ["story"]); XCTAssertEqual(f.mirrors, ["story"])
        f.vm.stopObservingArticleAvailability(second)
        XCTAssertEqual(f.cancellations, [0, 1])
    }

    func testAccountRoundTripRetiresOldListenerImmediatelyAndResumesWantedSelection() {
        let f = Fixture()
        let selection = f.vm.observeArticleAvailability(for: "story")
        f.select("B")
        XCTAssertEqual(f.cancellations, [0]); XCTAssertNil(f.model.checkingID)
        f.select("A")
        XCTAssertFalse(f.subscriptions[0].permission())
        f.withdraw(0)
        XCTAssertTrue(f.mirrors.isEmpty); XCTAssertTrue(f.model.withdrawnIDs.isEmpty)
        f.vm.resumeReaderStartup(); f.vm.resumeReaderStartup()
        XCTAssertEqual(f.subscriptions.count, 2); XCTAssertTrue(f.subscriptions[1].permission())
        f.publish(1)
        XCTAssertEqual(f.mirrors, ["story"]); XCTAssertNotNil(f.model.approvedRevision(for: "story"))
        // The visible view's original selection survives the account generation;
        // only its private physical observation was replaced.
        f.vm.stopObservingArticleAvailability(selection)
        XCTAssertEqual(f.cancellations, [0, 1])
    }

    func testSynchronousSubscribeReentryCannotOverwriteNewerSelectionOnReturn() {
        let f = Fixture()
        var nested: VM.AvailabilitySelection?
        f.onSubscribe = { index in
            guard index == 0 else { return }
            f.onSubscribe = nil
            nested = f.vm.observeArticleAvailability(for: "new-story")
        }
        let original = f.vm.observeArticleAvailability(for: "old-story")
        XCTAssertEqual(f.subscriptions.map(\.articleID), ["old-story", "new-story"])
        XCTAssertEqual(f.cancellations, [0]); XCTAssertEqual(f.model.checkingID, "new-story")
        f.vm.stopObservingArticleAvailability(original)
        f.withdraw(0)
        XCTAssertTrue(f.model.withdrawnIDs.isEmpty); XCTAssertTrue(f.mirrors.isEmpty)
        f.withdraw(1)
        XCTAssertEqual(f.model.withdrawnIDs, ["new-story"])
        guard let nested else { return XCTFail("Expected nested view selection") }
        f.vm.stopObservingArticleAvailability(nested)
        XCTAssertEqual(f.cancellations, [0, 1])
    }

    func testCancellationHookSelectionSurvivesOuterReplacementAndOldViewStop() {
        let f = Fixture()
        let first = f.vm.observeArticleAvailability(for: "first")
        var nested: VM.AvailabilitySelection?
        f.onCancel = { index in
            guard index == 0 else { return }
            f.onCancel = nil
            nested = f.vm.observeArticleAvailability(for: "nested")
        }
        let interrupted = f.vm.observeArticleAvailability(for: "interrupted")
        XCTAssertEqual(f.subscriptions.map(\.articleID), ["first", "nested"])
        XCTAssertEqual(f.model.checkingID, "nested")
        f.vm.stopObservingArticleAvailability(first)
        f.vm.stopObservingArticleAvailability(interrupted)
        XCTAssertEqual(f.cancellations, [0]); XCTAssertTrue(f.subscriptions[1].permission())
        f.withdraw(0); f.publish(1)
        XCTAssertTrue(f.model.withdrawnIDs.isEmpty); XCTAssertEqual(f.mirrors, ["nested"])
        guard let nested else { return XCTFail("Expected cancellation-hook selection") }
        f.vm.stopObservingArticleAvailability(nested)
        XCTAssertEqual(f.cancellations, [0, 1])
    }

    func testActualProviderMismatchBlocksCallbacksAndReattachmentBeforeCanonicalNotification() {
        let f = Fixture()
        let selection = f.vm.observeArticleAvailability(for: "story")
        f.actualUID = "B" // Provider changed before the canonical notification.
        f.withdraw(0)
        XCTAssertTrue(f.model.withdrawnIDs.isEmpty); XCTAssertTrue(f.mirrors.isEmpty)
        f.vm.resumeReaderStartup()
        XCTAssertEqual(f.cancellations, [0]); XCTAssertEqual(f.subscriptions.count, 1)
        XCTAssertNil(f.model.checkingID)
        f.actualUID = "A"
        f.vm.resumeReaderStartup()
        XCTAssertEqual(f.subscriptions.count, 2)
        XCTAssertFalse(f.subscriptions[0].permission()); XCTAssertTrue(f.subscriptions[1].permission())
        f.vm.stopObservingArticleAvailability(selection)
        XCTAssertEqual(f.cancellations, [0, 1])
    }

    func testObservedProviderDenialCannotReviveOldTicketWhenUIDReturnsBeforeResume() {
        let f = Fixture()
        let selection = f.vm.observeArticleAvailability(for: "story")
        let originalContext = f.identity.contextTicket()
        f.actualUID = "B"
        f.withdraw(0) // The real service guard observes and latches this denial.
        XCTAssertTrue(f.mirrors.isEmpty); XCTAssertTrue(f.model.withdrawnIDs.isEmpty)
        f.actualUID = "A" // No canonical publication occurs during this race.
        XCTAssertEqual(f.identity.contextTicket(), originalContext)
        XCTAssertFalse(f.subscriptions[0].permission())
        f.vm.resumeReaderStartup(); f.vm.resumeReaderStartup()
        guard f.subscriptions.count == 2 else {
            return XCTFail("A revoked model ticket must be replaced, not mistaken for a live subscription")
        }
        XCTAssertEqual(f.cancellations, [0]); XCTAssertTrue(f.subscriptions[1].permission())
        f.withdraw(0); f.deadlines[0]()
        XCTAssertEqual(f.model.checkingID, "story"); XCTAssertNil(f.model.errorMessage)
        XCTAssertTrue(f.mirrors.isEmpty); XCTAssertTrue(f.model.withdrawnIDs.isEmpty)
        f.publish(1)
        XCTAssertNotNil(f.model.approvedRevision(for: "story")); XCTAssertEqual(f.mirrors, ["story"])
        f.vm.stopObservingArticleAvailability(selection)
        XCTAssertEqual(f.cancellations, [0, 1])
    }

    func testGuestRetryOwnsFreshListenerAndRejectsFailedAttemptsLateWithdrawal() {
        let f = Fixture(uid: nil)
        let failed = f.vm.observeArticleAvailability(for: "story")
        f.subscriptions[0].completion(.failure(URLError(.notConnectedToInternet)))
        XCTAssertNotNil(f.model.errorMessage)
        let retry = f.vm.observeArticleAvailability(for: "story")
        XCTAssertNotEqual(failed, retry); XCTAssertNil(f.model.errorMessage)
        f.vm.stopObservingArticleAvailability(failed)
        f.withdraw(0); f.publish(1)
        XCTAssertTrue(f.model.withdrawnIDs.isEmpty); XCTAssertNil(f.model.errorMessage)
        XCTAssertNotNil(f.model.approvedRevision(for: "story")); XCTAssertEqual(f.mirrors, ["story"])
        f.vm.stopObservingArticleAvailability(retry)
        XCTAssertEqual(f.cancellations, [0, 1])
    }

    func testDeallocationRetiresOnlyOriginalListenerAndCannotStopSameArticleReplacement() async {
        for replaceBeforeCleanup in [false, true] {
            let f = Fixture()
            let cancelled = expectation(description: "Original physical listener retired")
            f.onCancel = { index in if index == 0 { cancelled.fulfill() } }
            var original: VM? = f.makeVM() // Do not retain it in the fixture's lazy vm.
            _ = original?.observeArticleAvailability(for: "story")
            weak var releasedVM = original
            original = nil
            XCTAssertNil(releasedVM)
            XCTAssertFalse(f.subscriptions[0].permission())
            f.withdraw(0) // Must already be inert before deferred MainActor cleanup.
            XCTAssertTrue(f.mirrors.isEmpty); XCTAssertTrue(f.model.withdrawnIDs.isEmpty)

            var replacement: VM?
            var replacementSelection: VM.AvailabilitySelection?
            if replaceBeforeCleanup {
                replacement = f.makeVM()
                replacementSelection = replacement?.observeArticleAvailability(for: "story")
                XCTAssertEqual(f.subscriptions.count, 2)
            }
            await fulfillment(of: [cancelled], timeout: 3)
            // Give the finite deinit cleanup Task its actor turn also when the
            // replacement synchronously retired the original listener first.
            for _ in 0..<8 { await Task.yield() }
            XCTAssertEqual(f.cancellations, [0])
            if let replacement, let replacementSelection {
                XCTAssertTrue(f.subscriptions[1].permission())
                XCTAssertEqual(f.model.checkingID, "story")
                f.withdraw(0); f.deadlines[0]()
                XCTAssertEqual(f.model.checkingID, "story"); XCTAssertNil(f.model.errorMessage)
                f.publish(1)
                XCTAssertEqual(f.mirrors, ["story"])
                replacement.stopObservingArticleAvailability(replacementSelection)
                XCTAssertEqual(f.cancellations, [0, 1])
            } else {
                XCTAssertNil(f.model.checkingID)
                XCTAssertTrue(f.mirrors.isEmpty); XCTAssertTrue(f.saves.isEmpty)
            }
        }
    }
}
