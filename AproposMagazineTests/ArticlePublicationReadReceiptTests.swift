import XCTest
@testable import Apropos

@MainActor
final class ArticlePublicationReadReceiptTests: XCTestCase {
    private func article(_ revision: String = "r2", draft: Bool = false) -> Article {
        Article(id: "publication-read-fixture", name: "Artikel", slug: "article",
            content: "<p>Tekst</p>", intro: "", topicID: "topic", isDraft: draft,
            lastPublished: "2026-10-28T12:00:00Z", contentRevision: revision)
    }

    func testColdPersistedApprovalNeedsAFullSourceReadEvenWhenRevisionIsUnchanged() {
        let value = article(), snapshot = ArticleAvailabilityModel.Snapshot(approvedRevisions: [article().id: "r2"])
        let model = ArticleAvailabilityModel(snapshot: snapshot, schedule: { _ in {} })
        model.trackPublicationIDs([value.id])
        XCTAssertTrue(model.permitsBody(value))
        XCTAssertFalse(model.hasFreshPublicationRead(value))
        model.recordPublications([value], ticket: model.beginRead())
        XCTAssertTrue(model.hasFreshPublicationRead(value))
        let cold = ArticleAvailabilityModel(snapshot: snapshot, schedule: { _ in {} })
        XCTAssertFalse(cold.hasFreshPublicationRead(value), "A new process cannot reconstruct fresh authority from durable approval")
    }

    func testMetadataOnlyServerObservationCannotGrantFullReadAuthority() {
        let model = ArticleAvailabilityModel(schedule: { _ in {} }), value = article()
        _ = model.observe(id: value.id) { _, done in
            done(.success(.init(withdrawn: false, isFromCache: false, revision: value.bodyRevision))); return {}
        }
        XCTAssertTrue(model.permitsBody(value))
        XCTAssertFalse(model.hasFreshPublicationRead(value))
        model.recordPublications([value], ticket: model.beginRead())
        XCTAssertTrue(model.hasFreshPublicationRead(value))
    }

    func testWithdrawalRevokesProofAndAnOlderReadCannotRestoreIt() {
        let model = ArticleAvailabilityModel(schedule: { _ in {} }), value = article()
        model.trackPublicationIDs([value.id])
        model.recordPublications([value], ticket: model.beginRead())
        let old = model.beginRead()
        model.recordWithdrawals([value.id], ticket: model.beginRead())
        XCTAssertFalse(model.hasFreshPublicationRead(value))
        model.recordPublications([value], ticket: old)
        XCTAssertFalse(model.hasFreshPublicationRead(value))
        XCTAssertTrue(model.withdrawnIDs.contains(value.id))
    }

    func testNewObserverRevisionRevokesOldProofUntilTheMatchingFullRead() {
        let model = ArticleAvailabilityModel(schedule: { _ in {} }), old = article()
        model.trackPublicationIDs([old.id])
        model.recordPublications([old], ticket: model.beginRead())
        let next = article("r3")
        _ = model.observe(id: old.id) { _, done in
            done(.success(.init(withdrawn: false, isFromCache: false, revision: next.bodyRevision))); return {}
        }
        XCTAssertFalse(model.hasFreshPublicationRead(old))
        XCTAssertFalse(model.hasFreshPublicationRead(next))
        model.recordPublications([next], ticket: model.beginRead())
        XCTAssertTrue(model.hasFreshPublicationRead(next))
        XCTAssertFalse(model.hasFreshPublicationRead(article("r3", draft: true)))
    }

    func testUntrackedCatalogRowsDoNotCreateAnotherLocalLedger() {
        let model = ArticleAvailabilityModel(schedule: { _ in {} }), value = article()
        model.recordPublications([value], ticket: model.beginRead())
        XCTAssertFalse(model.hasFreshPublicationRead(value))
        XCTAssertNil(model.approvedRevision(for: value.id))
    }

    func testFreshReadBeforeFavoriteLoadCanBeAdmittedWhenThatIDIsLaterTracked() {
        let model = ArticleAvailabilityModel(schedule: { _ in {} }), value = article()
        model.recordPublications([value], ticket: model.beginRead())
        XCTAssertFalse(model.hasFreshPublicationRead(value))
        XCTAssertNil(model.approvedRevision(for: value.id), "Untracked public results do not persist a reading ledger")
        model.trackPublicationIDs([value.id])
        XCTAssertTrue(model.hasFreshPublicationRead(value))
        XCTAssertEqual(model.approvedRevision(for: value.id), value.bodyRevision)
        XCTAssertFalse(model.permitsBody(article("r1")))
    }

    func testUntrackedReadReceiptIsFencedAgainstOlderReadsAndWithdrawalBeforeTracking() {
        for withdraw in [false, true] {
            let model = ArticleAvailabilityModel(schedule: { _ in {} }), value = article()
            let older = model.beginRead(), newer = model.beginRead()
            model.recordPublications([value], ticket: newer)
            model.recordPublications([article("r1")], ticket: older)
            if withdraw { model.recordWithdrawals([value.id], ticket: model.beginRead()) }
            model.trackPublicationIDs([value.id])
            XCTAssertFalse(model.hasFreshPublicationRead(article("r1")))
            XCTAssertEqual(model.hasFreshPublicationRead(value), !withdraw)
            XCTAssertEqual(model.withdrawnIDs.contains(value.id), withdraw)
        }
    }
}
