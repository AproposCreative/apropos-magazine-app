import XCTest
@testable import Apropos

@MainActor
final class FavoritesProfileMirrorTests: XCTestCase {
    private enum ProviderFailure: Error, Equatable { case missingProfile }
    private final class Memory { var data: [FavoritesNamespace: Data] = [:] }
    private func article(_ id: String = "article") -> Article {
        Article(id: id, name: "Titel", slug: id, content: "", intro: "", topicID: "topic", contentRevision: "r1")
    }
    private func ticket(enabled: Bool = true, articleID: String = "article") async throws -> (FavoritesModel, FavoritesModel.DispatchTicket) {
        let memory = Memory()
        let model = FavoritesModel(storage: .init(read: { memory.data[$0] }, write: { memory.data[$0] = $1 }))
        model.changeContext(to: .confirmed(userID: "owner-a"))
        let recovery = try XCTUnwrap(model.recoveryTicket())
        XCTAssertTrue(model.beginRecovery(recovery))
        let recovered = await model.finishRecovery(recovery, success: true); XCTAssertTrue(recovered)
        if !enabled { _ = model.setFavorite(article(articleID), enabled: true) }
        let mutation = try XCTUnwrap(model.setFavorite(article(articleID), enabled: enabled))
        let value = await model.beginDispatch(mutation)
        return (model, try XCTUnwrap(value))
    }
    private var ownerA: FavoritesProfileMirror.Identity { .init(actualUID: "owner-a", canonicalUID: "owner-a") }

    func testColdMirrorUsesOriginalAbsolutePayloadForAddAndRemoveWithoutLocalProfile() async throws {
        for enabled in [true, false] {
            let (model, original) = try await ticket(enabled: enabled)
            var writes: [(String, String, Bool)] = []
            try await FavoritesProfileMirror.perform(model: model, ticket: original, expectedUserID: "owner-a", effects: .init(
                identity: { self.ownerA }, updateExisting: { writes.append(($0, $1, $2)) }))
            XCTAssertEqual(writes.count, 1); XCTAssertEqual(writes.first?.0, "owner-a")
            XCTAssertEqual(writes.first?.1, original.mutation.articleID); XCTAssertEqual(writes.first?.2, enabled)
            // Only the combined transport may record its full ACK afterward.
            XCTAssertTrue(model.isCurrent(original)); XCTAssertEqual(model.snapshot.pendingArticleIDs, ["article"])
        }
    }
    func testActualOrCanonicalIdentityMismatchBlocksProvider() async throws {
        for identity in [FavoritesProfileMirror.Identity(actualUID: nil, canonicalUID: "owner-a"),
                         .init(actualUID: "owner-a", canonicalUID: nil),
                         .init(actualUID: "owner-b", canonicalUID: "owner-a"),
                         .init(actualUID: "owner-a", canonicalUID: "owner-b")] {
            let (model, original) = try await ticket(); var writes = 0
            do {
                try await FavoritesProfileMirror.perform(model: model, ticket: original, expectedUserID: "owner-a", effects: .init(
                    identity: { identity }, updateExisting: { _, _, _ in writes += 1 }))
                XCTFail("A mismatching identity cannot write a profile")
            } catch { XCTAssertEqual(error as? FavoritesProfileMirror.Failure, .stale) }
            XCTAssertEqual(writes, 0)
        }
    }
    func testIdentityGetterCannotReenterAnotherOwnerThenReturnOldMatchingUIDs() async throws {
        let (model, original) = try await ticket(); var writes = 0
        do {
            try await FavoritesProfileMirror.perform(model: model, ticket: original, expectedUserID: "owner-a", effects: .init(
                identity: { model.changeContext(to: .confirmed(userID: "owner-b")); return self.ownerA },
                updateExisting: { _, _, _ in writes += 1 }))
            XCTFail("Reentrant identity reads must revoke the original ticket")
        } catch { XCTAssertEqual(error as? FavoritesProfileMirror.Failure, .stale) }
        XCTAssertEqual(writes, 0)
    }
    func testSameUIDAfterGuestDoesNotReviveOriginalTicket() async throws {
        let (model, original) = try await ticket(); var writes = 0
        model.changeContext(to: .guest); model.changeContext(to: .confirmed(userID: "owner-a"))
        do {
            try await FavoritesProfileMirror.perform(model: model, ticket: original, expectedUserID: "owner-a", effects: .init(
                identity: { self.ownerA }, updateExisting: { _, _, _ in writes += 1 }))
            XCTFail("A fresh owner epoch cannot adopt an old ticket")
        } catch { XCTAssertEqual(error as? FavoritesProfileMirror.Failure, .stale) }
        XCTAssertEqual(writes, 0)
    }
    func testIdentityGetterReplacingIntentCannotStartOldProfileWrite() async throws {
        let (model, original) = try await ticket(); var writes = 0
        do {
            try await FavoritesProfileMirror.perform(model: model, ticket: original, expectedUserID: "owner-a", effects: .init(
                identity: { _ = model.setFavorite(self.article(), enabled: false); return self.ownerA },
                updateExisting: { _, _, _ in writes += 1 }))
            XCTFail("A newer opposite choice must supersede the old profile payload")
        } catch { XCTAssertEqual(error as? FavoritesProfileMirror.Failure, .stale) }
        XCTAssertEqual(writes, 0); XCTAssertTrue(model.snapshot.articles.isEmpty)
    }
    func testTicketFromAnotherModelCannotAcquireProfileAuthority() async throws {
        let (_, old) = try await ticket(); let (replacement, _) = try await ticket(); var writes = 0
        do {
            try await FavoritesProfileMirror.perform(model: replacement, ticket: old, expectedUserID: "owner-a", effects: .init(
                identity: { self.ownerA }, updateExisting: { _, _, _ in writes += 1 }))
            XCTFail("An unrelated runtime model cannot adopt an old ticket")
        } catch { XCTAssertEqual(error as? FavoritesProfileMirror.Failure, .stale) }
        XCTAssertEqual(writes, 0)
    }
    func testUnsafeDocumentIDsAndForeignExpectedOwnerAreRejectedBeforeEffects() async throws {
        for id in ["article/child", ".", "..", "__reserved__"] {
            let (model, original) = try await ticket(articleID: id); var effects = 0
            do {
                try await FavoritesProfileMirror.perform(model: model, ticket: original, expectedUserID: "owner-a", effects: .init(
                    identity: { effects += 1; return self.ownerA }, updateExisting: { _, _, _ in effects += 1 }))
                XCTFail("Unsafe document paths cannot reach the adapter")
            } catch { XCTAssertEqual(error as? FavoritesProfileMirror.Failure, .invalidRequest) }
            XCTAssertEqual(effects, 0)
        }
        let (model, original) = try await ticket(); var effects = 0
        do {
            try await FavoritesProfileMirror.perform(model: model, ticket: original, expectedUserID: "owner-b", effects: .init(
                identity: { effects += 1; return self.ownerA }, updateExisting: { _, _, _ in effects += 1 }))
            XCTFail("An expected UID cannot relabel another owner's ticket")
        } catch { XCTAssertEqual(error as? FavoritesProfileMirror.Failure, .invalidRequest) }
        XCTAssertEqual(effects, 0)
    }
    func testHeldProviderCannotCompleteForReplacementOwner() async throws {
        let (model, original) = try await ticket()
        let started = expectation(description: "original profile provider started")
        var completion: CheckedContinuation<Void, Error>?
        var writes = 0
        let task = Task { @MainActor in
            try await FavoritesProfileMirror.perform(model: model, ticket: original, expectedUserID: "owner-a", effects: .init(
                identity: { self.ownerA }, updateExisting: { _, _, _ in
                    writes += 1
                    try await withCheckedThrowingContinuation { completion = $0; started.fulfill() }
                }))
        }
        await fulfillment(of: [started], timeout: 2)
        model.changeContext(to: .guest); model.changeContext(to: .confirmed(userID: "owner-a"))
        completion?.resume()
        do { try await task.value; XCTFail("Late provider return cannot grant ACK to a new owner epoch") }
        catch { XCTAssertEqual(error as? FavoritesProfileMirror.Failure, .stale) }
        XCTAssertEqual(writes, 1); XCTAssertEqual(model.snapshot.pendingArticleIDs, ["article"])
    }
    func testPostAwaitIdentityReadCannotReenterAndGrantOldACK() async throws {
        let (model, original) = try await ticket(); var reads = 0; var writes = 0
        do {
            try await FavoritesProfileMirror.perform(model: model, ticket: original, expectedUserID: "owner-a", effects: .init(
                identity: {
                    reads += 1
                    if reads == 2 { _ = model.setFavorite(self.article(), enabled: false) }
                    return self.ownerA
                }, updateExisting: { _, _, _ in writes += 1 }))
            XCTFail("The original intent must remain current after provider completion")
        } catch { XCTAssertEqual(error as? FavoritesProfileMirror.Failure, .stale) }
        XCTAssertEqual(reads, 2); XCTAssertEqual(writes, 1); XCTAssertTrue(model.snapshot.articles.isEmpty)
    }
    func testMissingExistingProfileErrorPropagatesWithoutSyntheticACKOrNewIntent() async throws {
        let (model, original) = try await ticket(); var writes = 0
        do {
            try await FavoritesProfileMirror.perform(model: model, ticket: original, expectedUserID: "owner-a", effects: .init(
                identity: { self.ownerA }, updateExisting: { _, _, _ in writes += 1; throw ProviderFailure.missingProfile }))
            XCTFail("A missing existing server profile cannot become success")
        } catch { XCTAssertEqual(error as? ProviderFailure, .missingProfile) }
        XCTAssertEqual(writes, 1); XCTAssertTrue(model.isCurrent(original))
        XCTAssertEqual(model.pendingMutations.map(\.id), [original.mutation.id])
    }
}
