import Combine
import FirebaseCore
import XCTest
@testable import Apropos

@MainActor
final class SavedOfflineReadinessTests: XCTestCase {
    @MainActor private final class Fixture {
        let article = Article(id: "saved-readiness-story", name: "Artikel", slug: "saved-readiness-story",
            content: "<p>Faktisk gemt tekst.</p>", intro: "", topicID: "film", isDraft: false,
            lastPublished: "2026-11-01T08:00:00Z", contentRevision: "current-source")
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        lazy var bodies = OfflineManager.BodyStorage(directory: directory)
        var records: [FavoritesNamespace: Data] = [:]
        lazy var model = FavoritesModel(storage: .init(read: { [unowned self] in records[$0] },
            write: { [unowned self] in records[$0] = $1 }))
        var state: FavoritesOfflineCoordinator.AudioState = .downloading
        var hasAudioProof = false
        var exposesAsset = true
        var bodyReads = 0
        var indexReads = 0
        var pinHook: (() -> Void)?
        var proofHook: (() -> Void)?
        var progress: Double?
        var progressHook: (() -> Void)?
        var recoveryCalls = 0
        lazy var asset = PodcastAudioAsset(episodeID: "recording", canonicalArticleID: article.id,
            kind: .human, sourceRevision: article.bodyRevision!, remoteURL: URL(string: "https://fixtures.example.invalid/audio.m4a")!)!
        lazy var offline = FavoritesOfflineCoordinator(model: model, requiresAccount: true,
            storage: .init(read: { [unowned self] in bodyReads += 1; return try bodies.read($0) },
                write: { [unowned self] in try bodies.write($0, article: $1) },
                contains: { [unowned self] in indexReads += 1; return try bodies.contains($0) }),
            permitsBody: { _ in true }, effects: .init(cacheImages: { _, _ in },
                audioAsset: { [unowned self] _ in exposesAsset ? asset : nil },
                audioIsCached: { [unowned self] _ in
                    let value = hasAudioProof; proofHook?(); return value
                },
                pinAudio: { [unowned self] _, _, _ in pinHook?() }, releaseAudio: { _, _, _ in },
                scheduleRetry: { _, _ in {} }, audioState: { [unowned self] _ in state },
                audioProgress: { [unowned self] _ in
                    let value = progress; progressHook?(); return value
                }))
        lazy var manager = OfflineManager(coordinator: offline, recoverAudioDownloads: { [unowned self] in recoveryCalls += 1 })

        func saveText() throws -> FavoritesOfflineCoordinator.AccessTicket {
            model.changeContext(to: .confirmed(userID: "readiness-A"))
            XCTAssertNotNil(model.setFavorite(article, enabled: true))
            let ticket = try XCTUnwrap(offline.captureAccess(articleID: article.id))
            XCTAssertTrue(offline.saveBody(article, ticket: ticket))
            XCTAssertEqual(try bodies.read(ticket.contentKey)?.content, article.content)
            return ticket
        }
    }

    override func setUp() { super.setUp(); XCTAssertNil(FirebaseApp.allApps) }
    override func tearDown() { XCTAssertNil(FirebaseApp.allApps); super.tearDown() }

    func testTextAloneNeverClaimsCombinedOfflineReadyAndStatusQueriesDoNoDiskIO() throws {
        let f = Fixture(); defer { try? FileManager.default.removeItem(at: f.directory) }
        let ticket = try f.saveText()
        let reads = f.bodyReads, indexes = f.indexReads
        let states: [FavoritesOfflineCoordinator.AudioState] = [.waiting, .checking, .downloading, .failed, .storageLimit, .disabled]
        for state in states {
            f.state = state
            for _ in 0..<10 {
                XCTAssertEqual(f.offline.audioState(ticket: ticket), state)
                let summary = f.offline.libraryOfflineSummary
                XCTAssertEqual(summary.textAvailable, 1)
                XCTAssertEqual(summary.audioAvailable, 0)
                XCTAssertEqual(summary.ready, 0)
                XCTAssertEqual(summary.storageLimited, state == .storageLimit ? 1 : 0)
            }
        }
        f.exposesAsset = false
        XCTAssertEqual(f.offline.audioState(ticket: ticket), .waitingForPublication)
        XCTAssertEqual(f.offline.libraryOfflineSummary.awaitingAudio, 1)
        XCTAssertEqual(f.bodyReads, reads); XCTAssertEqual(f.indexReads, indexes)
    }

    func testAvailableProgressNeedsExistingAudioProofAndBothCurrentFilesForReady() throws {
        let f = Fixture(); defer { try? FileManager.default.removeItem(at: f.directory) }
        let ticket = try f.saveText()
        f.state = .available
        XCTAssertEqual(f.offline.audioState(ticket: ticket), .checking, "A progress label cannot manufacture byte proof")
        XCTAssertEqual(f.offline.libraryOfflineSummary.ready, 0)
        f.hasAudioProof = true
        XCTAssertEqual(f.offline.audioState(ticket: ticket), .available)
        XCTAssertEqual(f.offline.libraryOfflineSummary.ready, 1)
        XCTAssertEqual(f.offline.libraryOfflineSummary.audioAvailable, 1)
        f.hasAudioProof = false
        XCTAssertEqual(f.offline.libraryOfflineSummary.ready, 0)
    }

    func testDownloadProgressIsReadOnlyAndNeverManufacturesCompletedFiles() throws {
        let f = Fixture(); defer { try? FileManager.default.removeItem(at: f.directory) }
        let ticket = try f.saveText(), reads = f.bodyReads, indexes = f.indexReads
        for value in [0.0, 0.42, 1.0] {
            f.progress = value
            XCTAssertEqual(f.manager.audioProgress(ticket: ticket), value)
            XCTAssertEqual(f.offline.libraryOfflineSummary.ready, 0)
        }
        XCTAssertEqual(f.bodyReads, reads); XCTAssertEqual(f.indexReads, indexes)
        XCTAssertEqual(f.recoveryCalls, 0)
        f.state = .available
        XCTAssertNil(f.manager.audioProgress(ticket: ticket))
        XCTAssertEqual(f.offline.audioState(ticket: ticket), .checking)
        XCTAssertEqual(f.offline.libraryOfflineSummary.ready, 0)
        f.hasAudioProof = true
        XCTAssertEqual(f.offline.libraryOfflineSummary.ready, 1)
        XCTAssertNil(f.manager.audioProgress(ticket: ticket))
    }

    func testUnknownInvalidAndInactiveProgressAreNotDisplayed() throws {
        let f = Fixture(); defer { try? FileManager.default.removeItem(at: f.directory) }
        let ticket = try f.saveText()
        for value in [nil, Double.nan, Double.infinity, -Double.infinity, -0.1, 1.01] as [Double?] {
            f.progress = value
            XCTAssertNil(f.manager.audioProgress(ticket: ticket))
        }
        f.progress = 0.42
        for state in [FavoritesOfflineCoordinator.AudioState.waiting, .checking, .failed, .storageLimit, .disabled] {
            f.state = state
            XCTAssertNil(f.manager.audioProgress(ticket: ticket))
        }
        f.state = .downloading; f.exposesAsset = false
        XCTAssertNil(f.manager.audioProgress(ticket: ticket))
        XCTAssertEqual(f.offline.audioState(ticket: ticket), .waitingForPublication)
    }

    func testPercentageKeepsExactByteBoundariesAndWaitsForValidatedCompletion() {
        XCTAssertEqual(ArticleOfflineStatusControl.downloadPercentage(29.0 / 100), 29)
        XCTAssertEqual(ArticleOfflineStatusControl.downloadPercentage(58.0 / 100), 58)
        XCTAssertEqual(ArticleOfflineStatusControl.downloadPercentage(28.9 / 100), 28)
        XCTAssertEqual(ArticleOfflineStatusControl.downloadPercentage(0), 0)
        XCTAssertEqual(ArticleOfflineStatusControl.downloadPercentage(1), 99)
        for invalid in [nil, Double.nan, Double.infinity, -0.01, 1.01] as [Double?] {
            XCTAssertNil(ArticleOfflineStatusControl.downloadPercentage(invalid))
        }
    }

    func testProgressCallbackCannotCrossAccountRemovalSourceOrTransferChange() throws {
        for change in 0..<4 {
            let f = Fixture(); defer { try? FileManager.default.removeItem(at: f.directory) }
            let ticket = try f.saveText(); f.progress = 0.42
            f.progressHook = {
                switch change {
                case 0: f.model.changeContext(to: .confirmed(userID: "readiness-B"))
                case 1: _ = f.model.setFavorite(f.article, enabled: false)
                case 2: f.exposesAsset = false
                default: f.state = .failed
                }
            }
            XCTAssertNil(f.manager.audioProgress(ticket: ticket))
            XCTAssertEqual(f.offline.libraryOfflineSummary.ready, 0)
            XCTAssertEqual(f.recoveryCalls, 0)
            f.progressHook = nil
        }
    }

    func testAccountSwitchAndRemovedSourceCannotExposeThePreviousReadyLibrary() throws {
        let f = Fixture(); defer { try? FileManager.default.removeItem(at: f.directory) }
        let ticket = try f.saveText(); f.state = .available; f.hasAudioProof = true
        XCTAssertEqual(f.offline.libraryOfflineSummary.ready, 1)
        f.exposesAsset = false
        XCTAssertEqual(f.offline.libraryOfflineSummary.ready, 0)
        f.exposesAsset = true
        f.model.changeContext(to: .confirmed(userID: "readiness-B")); f.offline.synchronizeCurrentMembership()
        XCTAssertNil(f.offline.audioState(ticket: ticket))
        XCTAssertEqual(f.offline.libraryOfflineSummary.total, 0)
        XCTAssertEqual(f.offline.libraryOfflineSummary.ready, 0)
    }

    func testRecoveryIsAnExplicitOnlineEventAndCannotCrossAReentrantOwnerChange() throws {
        let f = Fixture(); defer { try? FileManager.default.removeItem(at: f.directory) }
        _ = try f.saveText()
        f.manager.isOnline = false; f.manager.recoverSavedAudioDownloads()
        XCTAssertEqual(f.recoveryCalls, 0)
        f.manager.isOnline = true; f.manager.recoverSavedAudioDownloads()
        XCTAssertEqual(f.recoveryCalls, 1)
        _ = f.offline.libraryOfflineSummary; _ = f.offline.libraryOfflineSummary
        XCTAssertEqual(f.recoveryCalls, 1, "Read-only rendering is not a retry event")
        f.pinHook = { [unowned f] in f.model.changeContext(to: .confirmed(userID: "readiness-B")) }
        f.manager.recoverSavedAudioDownloads()
        XCTAssertEqual(f.recoveryCalls, 1, "An original A event must not become a B recovery after a hook")
    }

    func testEitherByteProofResultRejectsOriginalPresentationAfterReentrantOwnerChange() throws {
        for proof in [false, true] {
            let f = Fixture(); defer { try? FileManager.default.removeItem(at: f.directory) }
            let original = try f.saveText(); f.state = .available; f.hasAudioProof = proof
            f.proofHook = {
                f.proofHook = nil
                f.model.changeContext(to: .confirmed(userID: "readiness-B"))
                f.offline.synchronizeCurrentMembership()
            }
            XCTAssertNil(f.offline.audioState(ticket: original), "Even a negative proof must recheck its original owner")
            XCTAssertFalse(f.offline.isCurrent(original))
            XCTAssertEqual(f.offline.libraryOfflineSummary.ready, 0)
            XCTAssertEqual(f.offline.libraryOfflineSummary.total, 0)
        }
    }

    func testEitherByteProofResultRejectsDescriptorReplacedDuringItsQuery() throws {
        for proof in [false, true] {
            let f = Fixture(); defer { try? FileManager.default.removeItem(at: f.directory) }
            let original = try f.saveText(); f.state = .available; f.hasAudioProof = proof
            let previous = f.asset
            f.proofHook = {
                f.proofHook = nil
                f.asset = PodcastAudioAsset(episodeID: "recording-replacement", canonicalArticleID: f.article.id,
                    kind: .human, sourceRevision: original.contentRevision,
                    remoteURL: URL(string: "https://fixtures.example.invalid/replacement.m4a")!)!
            }
            XCTAssertNil(f.offline.audioState(ticket: original), "The old proof query cannot relabel a replacement descriptor")
            XCTAssertTrue(f.offline.isCurrent(original), "The membership itself did not change")
            XCTAssertNotEqual(previous, f.asset)
        }
    }

    func testOnlinePublicationRunsAfterActualValueCommitsAndOnlyOnce() async throws {
        let f = Fixture(); defer { try? FileManager.default.removeItem(at: f.directory) }
        _ = try f.saveText(); f.manager.isOnline = false
        var storedValuesDuringPublication: [Bool] = []
        var tasks: [Task<Void, Never>] = []
        var actions = 0
        let subscription = f.manager.$isOnline.dropFirst().filter { $0 }.sink { _ in
            storedValuesDuringPublication.append(f.manager.isOnline)
            tasks.append(f.manager.performAfterOnlinePublication(isActive: { true }) {
                XCTAssertTrue(f.manager.isOnline)
                actions += 1
                f.manager.recoverSavedAudioDownloads()
            })
        }
        f.manager.isOnline = true
        XCTAssertEqual(storedValuesDuringPublication, [false], "The real publisher exposes the former wrapped value during willSet")
        XCTAssertEqual(actions, 0, "The recovery is deferred out of the publication callback")
        for task in tasks { await task.value }
        XCTAssertEqual(actions, 1)
        XCTAssertEqual(f.recoveryCalls, 1)
        _ = f.offline.libraryOfflineSummary
        XCTAssertEqual(f.recoveryCalls, 1, "A read-only status query does not repeat the online event")
        withExtendedLifetime(subscription) {}
    }

    func testQueuedOnlinePublicationDropsStaleConnectivityOrInactiveScene() async throws {
        for becomesOffline in [false, true] {
            let f = Fixture(); defer { try? FileManager.default.removeItem(at: f.directory) }
            _ = try f.saveText(); f.manager.isOnline = false
            var active = true, actions = 0
            var tasks: [Task<Void, Never>] = []
            let subscription = f.manager.$isOnline.dropFirst().filter { $0 }.sink { _ in
                tasks.append(f.manager.performAfterOnlinePublication(isActive: { active }) {
                    actions += 1; f.manager.recoverSavedAudioDownloads()
                })
            }
            f.manager.isOnline = true
            if becomesOffline { f.manager.isOnline = false } else { active = false }
            for task in tasks { await task.value }
            XCTAssertEqual(tasks.count, 1)
            XCTAssertEqual(actions, 0)
            XCTAssertEqual(f.recoveryCalls, 0)
            withExtendedLifetime(subscription) {}
        }
    }

    func testRecoveryRechecksActualOnlineStateAfterPinHook() throws {
        let f = Fixture(); defer { try? FileManager.default.removeItem(at: f.directory) }
        _ = try f.saveText()
        f.pinHook = { [unowned f] in f.manager.isOnline = false }
        f.manager.recoverSavedAudioDownloads()
        XCTAssertEqual(f.recoveryCalls, 0)
    }
}
