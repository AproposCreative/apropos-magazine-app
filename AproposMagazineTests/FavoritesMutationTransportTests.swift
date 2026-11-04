import Combine
import XCTest
@testable import Apropos

final class FavoritesMutationTransportTests: XCTestCase {
    @MainActor func testProfileReceivesExactDispatchTicketUIDAndOriginalCustomModel() async throws {
        let f = Pipeline()
        f.coordinator.submit(try XCTUnwrap(f.model.setFavorite(f.article, enabled: true)), expectedUserID: "a")
        await wait { f.favorite.count == 1 }
        XCTAssertTrue(f.profile.isEmpty)
        f.finishFavorite(0)
        await wait { f.profile.count == 1 }
        XCTAssertEqual(f.profileTickets, f.startedTickets)
        XCTAssertEqual(f.profileModels.count, 1)
        XCTAssertTrue(f.profileModels[0] === f.model)
        XCTAssertEqual(f.profile.map { $0.1 }, ["a"])
        XCTAssertTrue(f.model.isCurrent(f.profileTickets[0]))
        f.finishProfile(0)
        await wait { f.finishedProfile == 1 }
    }
    @MainActor func testOriginalFavoriteReceiptCannotStartAnotherOwnersProfileWrite() async throws {
        let f = Pipeline()
        let mutation = try XCTUnwrap(f.model.setFavorite(f.article, enabled: true))
        f.coordinator.submit(mutation, expectedUserID: "a")
        await wait { f.favorite.count == 1 }
        f.model.changeContext(to: .confirmed(userID: "b"))
        f.finishFavorite(0)
        await wait { f.finishedFavorite == 1 && f.staleFailures == 1 }
        for _ in 0..<30 { await Task.yield() }
        XCTAssertTrue(f.profile.isEmpty)
        XCTAssertTrue(f.model.snapshot.articles.isEmpty)
    }
    @MainActor func testSlowProfileReceiptRetainsBarrierBeforeNewestAbsoluteIntent() async throws {
        let f = Pipeline()
        let add = try XCTUnwrap(f.model.setFavorite(f.article, enabled: true))
        f.coordinator.submit(add, expectedUserID: "a")
        await wait { f.favorite.count == 1 }
        f.finishFavorite(0)
        await wait { f.profile.count == 1 }
        let remove = try XCTUnwrap(f.model.setFavorite(f.article, enabled: false))
        f.coordinator.submit(remove, expectedUserID: "a")
        for _ in 0..<30 { await Task.yield() }
        XCTAssertEqual(f.favorite.count, 1)
        f.finishProfile(0)
        await wait { f.favorite.count == 2 }
        XCTAssertEqual(f.favorite.map { $0.0 }, [true, false])
        f.finishFavorite(1)
        await wait { f.profile.count == 2 }
        XCTAssertEqual(f.profile.map { $0.0 }, [true, false])
        f.finishProfile(1)
        await wait { f.finishedProfile == 2 }
    }
    @MainActor func testAtoGuestToARetainsActiveProfileBarrierAndRejectsOldReceipt() async throws {
        let f = Pipeline()
        f.coordinator.submit(try XCTUnwrap(f.model.setFavorite(f.article, enabled: true)), expectedUserID: "a")
        await wait { f.favorite.count == 1 };f.finishFavorite(0)
        await wait { f.profile.count == 1 }
        f.model.changeContext(to: .guest)
        f.model.changeContext(to: .confirmed(userID: "a"))
        f.coordinator.submit(try XCTUnwrap(f.model.setFavorite(f.article, enabled: false)), expectedUserID: "a")
        for _ in 0..<30 { await Task.yield() }
        XCTAssertEqual(f.favorite.count, 1)
        f.finishProfile(0)
        await wait { f.favorite.count == 2 }
        XCTAssertEqual(f.favorite.map { $0.1 }, ["a", "a"])
        XCTAssertEqual(f.favorite.map { $0.0 }, [true, false])
        f.finishFavorite(1);await wait { f.profile.count == 2 };f.finishProfile(1)
        await wait { f.finishedProfile == 2 }
        XCTAssertTrue(f.model.snapshot.articles.isEmpty)
    }
    @MainActor func testProfileFailureIsPendingUntilExplicitAbsoluteRetry() async throws {
        let f = Pipeline()
        f.coordinator.submit(try XCTUnwrap(f.model.setFavorite(f.article, enabled: true)), expectedUserID: "a")
        await wait { f.favorite.count == 1 };f.finishFavorite(0)
        await wait { f.profile.count == 1 };f.finishProfile(0, fail: true)
        await wait { f.model.snapshot.state == .cloudFailed }
        XCTAssertEqual(f.favorite.count, 1)
        XCTAssertEqual(f.model.snapshot.articles.map(\.id), ["article"])
        f.coordinator.submit(try XCTUnwrap(f.model.retryMutation(articleID: "article")), expectedUserID: "a")
        await wait { f.favorite.count == 2 };f.finishFavorite(1)
        await wait { f.profile.count == 2 };f.finishProfile(1)
        await wait { f.finishedProfile == 2 }
        XCTAssertEqual(f.favorite.map { $0.0 }, [true, true])
    }
    @MainActor private func wait(_ predicate: () -> Bool, file: StaticString = #filePath, line: UInt = #line) async {
        for _ in 0..<1000 { if predicate() { return };await Task.yield() }
        XCTFail("Owned pipeline did not reach expected state", file: file, line: line)
    }
}

@MainActor private final class Pipeline {
    enum Failure: Error { case profile }
    let article = Article(id: "article", name: "article", slug: "article", content: "", intro: "", topicID: "topic",
                          lastPublished: "2026-10-20T12:00:00Z", contentRevision: "r1")
    let model: FavoritesModel
    var favorite: [(Bool, String)] = [], profile: [(Bool, String)] = []
    var startedTickets: [FavoritesModel.DispatchTicket] = [], profileTickets: [FavoritesModel.DispatchTicket] = []
    var profileModels: [FavoritesModel] = []
    var finishedFavorite = 0, finishedProfile = 0, staleFailures = 0
    private var observation: AnyCancellable?
    private var favoriteWaits: [Int: CheckedContinuation<Void, Error>] = [:]
    private var profileWaits: [Int: CheckedContinuation<Void, Error>] = [:]
    lazy var coordinator = FavoritesCloudCoordinator(model: model, drainPendingWrites: { _ in }) { [weak self] ticket, uid in
        guard let self else { throw Failure.profile }
        self.startedTickets.append(ticket)
        do {
        try await FavoritesMutationTransport.perform(model: self.model, ticket: ticket, expectedUserID: uid,
            writeFavorite: { [unowned self] mutation, uid in
                let index = self.favorite.count;self.favorite.append((mutation.enabled, uid))
                try await withCheckedThrowingContinuation { self.favoriteWaits[index] = $0 }
                self.finishedFavorite += 1
            }, setBookmark: { [unowned self] originalTicket, uid, originalModel in
                self.profileTickets.append(originalTicket)
                self.profileModels.append(originalModel)
                let index = self.profile.count;self.profile.append((originalTicket.mutation.enabled, uid))
                do { try await withCheckedThrowingContinuation { self.profileWaits[index] = $0 } }
                catch { self.finishedProfile += 1;throw error }
                self.finishedProfile += 1
            })
        } catch {
            if error is FavoritesMutationTransport.Failure { self.staleFailures += 1 }
            throw error
        }
    }
    init() {
        // Separate memory box avoids capturing a partly initialized fixture.
        let box = Box()
        model = FavoritesModel(storage: .init(read: { box.records[$0] }, write: { box.records[$0] = $1 }))
        observation = model.changes.sink { [weak self] snapshot in
            guard let self, snapshot.generation == self.model.snapshot.generation,
                  snapshot.revision == self.model.snapshot.revision else { return }
            self.coordinator.setOwner(expectedUserID: "a", generation: snapshot.generation)
        }
        model.changeContext(to: .confirmed(userID: "a"))
        coordinator.setOwner(expectedUserID: "a", generation: model.snapshot.generation)
    }
    func finishFavorite(_ index: Int) { favoriteWaits.removeValue(forKey: index)?.resume() }
    func finishProfile(_ index: Int, fail: Bool = false) {
        let continuation = profileWaits.removeValue(forKey: index)
        if fail { continuation?.resume(throwing: Failure.profile) } else { continuation?.resume() }
    }
    private final class Box { var records: [FavoritesNamespace: Data] = [:] }
}
