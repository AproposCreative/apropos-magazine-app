import FirebaseCore
import XCTest
@testable import Apropos

@MainActor
final class FavoritesPublishedMetadataTests: XCTestCase {
    @MainActor private final class Memory {
        var data: [FavoritesNamespace: Data] = [:]
        var writes = 0
        var onWrite: (() -> Void)?
        var storage: FavoritesModel.Storage {
            .init(read: { namespace in self.data[namespace] }, write: { namespace, bytes in
                self.writes += 1
                self.onWrite?()
                self.data[namespace] = bytes
            })
        }
        func seed(_ articles: [Article], uid: String = "A") throws {
            let namespace = try XCTUnwrap(FavoritesContext.confirmed(userID: uid).namespace)
            data[namespace] = try FavoritesRecordCodec.encode(FavoritesRecord(articles: articles), namespace: namespace)
        }
        func record(_ uid: String = "A") throws -> FavoritesRecord {
            let namespace = try XCTUnwrap(FavoritesContext.confirmed(userID: uid).namespace)
            return try FavoritesRecordCodec.decode(XCTUnwrap(data[namespace]), namespace: namespace)
        }
    }
    private func article(_ revision: String? = "cms-sha256-v1:new", id: String = "article", name: String = "Ny artikel", isDraft: Bool = false) -> Article {
        Article(id: id, name: name, slug: id, content: "<p>Aktuel tekst</p>", intro: "Intro",
                topicID: "topic", isDraft: isDraft, createdOn: "2026-10-20T10:00:00Z",
                lastPublished: "2026-10-20T11:00:00Z", lastUpdated: "2026-10-21T10:00:00Z",
                contentRevision: revision)
    }
    private func model(_ memory: Memory, sanitize: @escaping @MainActor (Article) -> Article? = { $0 }) -> FavoritesModel {
        let model = FavoritesModel(storage: memory.storage, sanitize: sanitize)
        model.changeContext(to: .confirmed(userID: "A"))
        return model
    }
    private func recover(_ model: FavoritesModel) async throws {
        let ticket = try XCTUnwrap(model.recoveryTicket())
        XCTAssertTrue(model.beginRecovery(ticket))
        let recovered = await model.finishRecovery(ticket, success: true)
        XCTAssertTrue(recovered)
    }

    func testLegacyPersistedBookmarkAdoptsFreshRevisionAndColdModelRetainsItWithoutBodyOrIntent() throws {
        let memory = Memory(), old = article(nil, name: "Gammel titel"), new = article()
        try memory.seed([old])
        let first = model(memory), original = try XCTUnwrap(first.membershipTicket(articleID: old.id))
        XCTAssertEqual(original.contentRevision, "updated:2026-10-21T10:00:00Z")
        let accepted = try XCTUnwrap(first.adoptPublishedMetadata(new, ticket: original,
            stillCurrent: { true }, permitsPublication: { $0.bodyRevision == new.bodyRevision }))
        XCTAssertTrue(first.isCurrent(accepted)); XCTAssertFalse(first.isCurrent(original))
        XCTAssertEqual(accepted.contentRevision, new.bodyRevision)
        XCTAssertEqual(first.snapshot.articles.map(\.id), [old.id])
        let stored = try memory.record()
        XCTAssertTrue(stored.pending.isEmpty); XCTAssertFalse(stored.requiresRecovery)
        XCTAssertEqual(stored.base.first?.contentRevision, new.bodyRevision)
        XCTAssertEqual(stored.base.first?.name, new.name)
        XCTAssertEqual(stored.base.first?.article.content, "", "Metadata adoption never stores a body in the private journal")
        let writes = memory.writes
        XCTAssertNil(first.adoptPublishedMetadata(article("later"), ticket: original,
            stillCurrent: { true }, permitsPublication: { _ in true }))
        XCTAssertEqual(memory.writes, writes, "A late result cannot reuse the pre-adoption membership")
        let cold = model(memory), coldMember = try XCTUnwrap(cold.membershipTicket(articleID: old.id))
        XCTAssertEqual(coldMember.contentRevision, new.bodyRevision)
        XCTAssertFalse(cold.isCurrent(accepted), "A recreated model cannot endorse the original access ticket")
        XCTAssertNil(FirebaseApp.allApps)
    }

    func testNoOpFreshMetadataKeepsOriginalMembershipAndDoesNotWrite() throws {
        let memory = Memory(); try memory.seed([article()])
        let model = model(memory), member = try XCTUnwrap(model.membershipTicket(articleID: "article"))
        let accepted = try XCTUnwrap(model.adoptPublishedMetadata(article(), ticket: member,
            stillCurrent: { true }, permitsPublication: { _ in true }))
        XCTAssertTrue(member.identifiesSameMembership(as: accepted)); XCTAssertEqual(memory.writes, 0)
    }

    func testOldReadAfterRemovalReadditionOrAccountRoundTripCannotAdopt() throws {
        for change in 0..<2 {
            let memory = Memory(); try memory.seed([article("old")])
            let model = model(memory), original = try XCTUnwrap(model.membershipTicket(articleID: "article"))
            if change == 0 {
                _ = model.setFavorite(article("old"), enabled: false)
                _ = model.setFavorite(article("old"), enabled: true)
            } else {
                model.changeContext(to: .confirmed(userID: "B"))
                model.changeContext(to: .confirmed(userID: "A"))
            }
            let before = memory.data, writes = memory.writes
            XCTAssertNil(model.adoptPublishedMetadata(article(), ticket: original,
                stillCurrent: { true }, permitsPublication: { _ in true }))
            XCTAssertEqual(memory.data, before); XCTAssertEqual(memory.writes, writes)
        }
    }

    func testRejectedSourceWrongArticleAndWithdrawnPublicationNeverWrite() throws {
        for rejected in 0..<4 {
            let memory = Memory(); try memory.seed([article("old")])
            let model = model(memory), member = try XCTUnwrap(model.membershipTicket(articleID: "article"))
            let proposed = rejected == 2 ? article(id: "other") : article(isDraft: rejected == 3)
            let before = memory.data
            XCTAssertNil(model.adoptPublishedMetadata(proposed, ticket: member,
                stillCurrent: { rejected != 0 },
                permitsPublication: { _ in rejected != 1 }))
            XCTAssertEqual(memory.data, before); XCTAssertEqual(memory.writes, 0)
            XCTAssertTrue(model.isCurrent(member))
        }
    }

    func testSanitizerCannotSubstituteUnapprovedRevision() throws {
        let memory = Memory(); try memory.seed([article("old")])
        var replace = false
        let model = model(memory, sanitize: { replace ? self.article("other-revision") : $0 })
        let member = try XCTUnwrap(model.membershipTicket(articleID: "article")); replace = true
        let before = memory.data
        XCTAssertNil(model.adoptPublishedMetadata(article(), ticket: member,
            stillCurrent: { true }, permitsPublication: { _ in true }))
        XCTAssertEqual(memory.data, before); XCTAssertEqual(memory.writes, 0)
    }

    func testReentrantReadOrPublicationGuardCannotWriteIntoReplacementOwner() throws {
        for publication in [false, true] {
            let memory = Memory(); try memory.seed([article("old")])
            let model = model(memory), member = try XCTUnwrap(model.membershipTicket(articleID: "article"))
            let before = memory.data
            let changeOwner = { model.changeContext(to: .confirmed(userID: "B")); return true }
            XCTAssertNil(model.adoptPublishedMetadata(article(), ticket: member,
                stillCurrent: { publication ? true : changeOwner() },
                permitsPublication: { _ in publication ? changeOwner() : true }))
            XCTAssertEqual(model.context, .confirmed(userID: "B"))
            XCTAssertEqual(memory.data, before); XCTAssertEqual(memory.writes, 0)
        }
    }

    func testReentrantSameMemberMetadataOperationWinsOverOlderCanonicalAttempt() throws {
        let memory = Memory(), old = article("old")
        try memory.seed([old])
        let model = model(memory), member = try XCTUnwrap(model.membershipTicket(articleID: old.id))
        var entered = false
        XCTAssertNil(model.adoptPublishedMetadata(article(), ticket: member, stillCurrent: {
            if !entered {
                entered = true
                XCTAssertTrue(model.updateMetadata(self.article("old", name: "Nyere lokal metadata"), ticket: member))
            }
            return true
        }, permitsPublication: { _ in true }))
        XCTAssertEqual(memory.writes, 1)
        XCTAssertEqual(model.snapshot.articles.first?.name, "Nyere lokal metadata")
        XCTAssertEqual(model.snapshot.articles.first?.bodyRevision, "old")
        XCTAssertTrue(model.isCurrent(member), "Operation ownership is stronger than stable same-revision membership")
    }

    func testWritePublicationReentryReturnsNoTicketForReplacementOwnerAndKeepsOriginalPartition() throws {
        let memory = Memory(); try memory.seed([article("old")])
        let model = model(memory), member = try XCTUnwrap(model.membershipTicket(articleID: "article"))
        memory.onWrite = { model.changeContext(to: .confirmed(userID: "B")) }
        XCTAssertNil(model.adoptPublishedMetadata(article(), ticket: member,
            stillCurrent: { true }, permitsPublication: { _ in true }))
        XCTAssertEqual(model.context, .confirmed(userID: "B")); XCTAssertTrue(model.snapshot.articles.isEmpty)
        XCTAssertEqual(try memory.record().base.first?.contentRevision, article().bodyRevision)
        let b = try XCTUnwrap(FavoritesContext.confirmed(userID: "B").namespace)
        XCTAssertNil(memory.data[b], "An already-authorized historical A write never crosses into B")
    }

    func testPendingAddRemoveAndUnknownAcknowledgementRemainByteIdentical() async throws {
        for phase in 0..<4 {
            let memory = Memory()
            if phase == 1 { try memory.seed([article("old")]) }
            let model = model(memory); try await recover(model)
            let beforeMutation = model.membershipTicket(articleID: "article")
            let mutation = try XCTUnwrap(model.setFavorite(article("old"), enabled: phase != 1))
            var original = model.membershipTicket(articleID: "article") ?? beforeMutation
            if phase >= 2 {
                let started = await model.beginDispatch(mutation)
                let dispatch = try XCTUnwrap(started)
                if phase == 3 { _ = await model.finishDispatch(dispatch, result: .acknowledged) }
                original = model.membershipTicket(articleID: "article")
            }
            let before = memory.data, writes = memory.writes
            if let original {
                XCTAssertNil(model.adoptPublishedMetadata(article(), ticket: original,
                    stillCurrent: { true }, permitsPublication: { _ in true }))
            } else {
                XCTAssertEqual(phase, 1, "Only the pending remove lacks visible membership")
            }
            XCTAssertEqual(memory.data, before); XCTAssertEqual(memory.writes, writes)
            XCTAssertEqual(model.pendingMutations.first, mutation)
        }
    }

    func testCanonicalMetadataCanBeAdoptedAfterOriginalAcknowledgementAndMembershipProofRetire() async throws {
        let memory = Memory(), old = article("old"), new = article()
        let model = model(memory); try await recover(model)
        let mutation = try XCTUnwrap(model.setFavorite(old, enabled: true))
        let original = try XCTUnwrap(model.membershipTicket(articleID: old.id))
        XCTAssertNil(model.adoptPublishedMetadata(new, ticket: original,
            stillCurrent: { true }, permitsPublication: { _ in true }))
        let started = await model.beginDispatch(mutation)
        let dispatch = try XCTUnwrap(started)
        _ = await model.finishDispatch(dispatch, result: .acknowledged)
        let observation = try XCTUnwrap(model.observationTicket())
        XCTAssertTrue(model.applyRemote(.init(articles: [old], isFromCache: false, hasPendingWrites: false), ticket: observation))
        XCTAssertTrue(model.pendingMutations.isEmpty)
        let ready = try XCTUnwrap(model.membershipTicket(articleID: old.id))
        let accepted = try XCTUnwrap(model.adoptPublishedMetadata(new, ticket: ready,
            stillCurrent: { true }, permitsPublication: { $0.bodyRevision == new.bodyRevision }))
        XCTAssertEqual(accepted.contentRevision, new.bodyRevision)
        XCTAssertTrue(try memory.record().pending.isEmpty)
    }
}
