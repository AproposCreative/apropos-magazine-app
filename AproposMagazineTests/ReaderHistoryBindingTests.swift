import XCTest
@testable import Apropos

@MainActor
final class ReaderHistoryBindingTests: XCTestCase {
    func testUnresolvedReaderCannotOpenOrCreateAnyHistoryOrAnalyticsEffect() {
        let f = ReaderBindingFixture(context: .unresolved)
        XCTAssertNil(f.open("article-A"))
        XCTAssertTrue(f.opens.isEmpty)
        XCTAssertTrue(f.writes.isEmpty)
    }

    func testActualOpenMarksOriginalArticleAndRequiresFreshDocumentMeasurementForProgress() throws {
        let f = ReaderBindingFixture()
        let session = try XCTUnwrap(f.open("article-A"))
        let doc = try XCTUnwrap(f.binding.beginDocument(session, documentID: UUID().uuidString))
        let callback = f.binding.progressHandler(for: doc)
        XCTAssertEqual(f.model.snapshot.readArticleIDs, ["article-A"])
        XCTAssertEqual(f.opens, ["article-A"])
        callback(0.8)
        XCTAssertNil(f.model.snapshot.progress["article-A"])
        f.binding.markDocumentReady(doc)
        callback(0.81)
        XCTAssertEqual(f.model.snapshot.progress["article-A"], 0.8)
        XCTAssertEqual(f.progressEffects.map(\.article), ["article-A"])
        XCTAssertEqual(f.progressEffects.map(\.value), [0.8])
    }

    func testInvalidAndDuplicateMeasurementsNeverReachHistoryOrAnalytics() throws {
        let f = ReaderBindingFixture()
        let doc = try f.document("article-A")
        for value in [Double.nan, .infinity, -.infinity, -0.001, 1.001, 1e300] {
            XCTAssertFalse(f.binding.record(value, document: doc))
        }
        XCTAssertTrue(f.binding.record(0.51, document: doc))
        XCTAssertFalse(f.binding.record(0.52, document: doc))
        XCTAssertEqual(f.model.snapshot.progress["article-A"], 0.5)
        XCTAssertEqual(f.progressEffects.count, 1)
        XCTAssertTrue(f.binding.record(1, document: doc))
        XCTAssertEqual(f.model.snapshot.progress["article-A"], 1)
    }

    func testReplacingHTMLDocumentRejectsCapturedOldCallbackWithoutLendingNewDocument() throws {
        let f = ReaderBindingFixture()
        let session = try XCTUnwrap(f.open("article-A"))
        let old = try XCTUnwrap(f.binding.beginDocument(session, documentID: UUID().uuidString))
        f.binding.markDocumentReady(old)
        let oldCallback = f.binding.progressHandler(for: old)
        let current = try XCTUnwrap(f.binding.beginDocument(session, documentID: UUID().uuidString))
        f.binding.markDocumentReady(old)
        oldCallback(0.95)
        XCTAssertFalse(f.binding.record(0.6, document: current), "An old height cannot ready a new document")
        f.binding.markDocumentReady(current)
        oldCallback(0.95)
        XCTAssertTrue(f.binding.record(0.6, document: current))
        XCTAssertEqual(f.model.snapshot.progress["article-A"], 0.6)
        XCTAssertEqual(f.progressEffects.map(\.value), [0.6])
    }

    func testCapturedArticleCallbackCannotWriteAnotherArticleOrUseItsAnalyticsClosure() throws {
        let f = ReaderBindingFixture()
        let old = try f.document("article-A")
        let callback = f.binding.progressHandler(for: old)
        let current = try f.document("article-B")
        callback(0.99)
        XCTAssertNil(f.model.snapshot.progress["article-A"])
        XCTAssertNil(f.model.snapshot.progress["article-B"])
        f.binding.record(0.45, document: current)
        XCTAssertEqual(f.progressEffects.map(\.article), ["article-B"])
        XCTAssertEqual(f.model.snapshot.progress["article-B"], 0.45)
    }

    func testAtoGuestToAWithSameArticleDoesNotReviveOldMotionOrDocument() throws {
        let f = ReaderBindingFixture(context: .confirmed(userID: "reader-A"))
        let old = try f.document("article")
        let callback = f.binding.progressHandler(for: old)
        f.model.changeContext(to: .guest)
        _ = try f.document("article")
        callback(0.99)
        XCTAssertNil(f.model.snapshot.progress["article"])
        f.model.changeContext(to: .confirmed(userID: "reader-A"))
        let fresh = try f.document("article")
        callback(0.99)
        XCTAssertNil(f.model.snapshot.progress["article"])
        f.binding.record(0.4, document: fresh)
        XCTAssertEqual(f.model.snapshot.progress["article"], 0.4)
        XCTAssertEqual(f.progressEffects.map(\.value), [0.4])
    }

    func testContextChangeImmediatelyRejectsCallbacksBeforeSwiftUIRebinds() throws {
        let f = ReaderBindingFixture()
        let session = try XCTUnwrap(f.open("article"))
        let doc = try XCTUnwrap(f.binding.beginDocument(session, documentID: UUID().uuidString))
        f.binding.markDocumentReady(doc)
        let old = f.binding.progressHandler(for: doc)
        f.model.changeContext(to: .confirmed(userID: "reader-B"))
        old(0.95)
        XCTAssertFalse(f.binding.isCurrent(session))
        XCTAssertNil(f.binding.beginDocument(session, documentID: UUID().uuidString))
        XCTAssertTrue(f.model.snapshot.readArticleIDs.isEmpty)
        XCTAssertTrue(f.progressEffects.isEmpty)
    }

    func testStorageAccountEpochAlsoInvalidatesSameOwnerDocument() throws {
        let f = ReaderBindingFixture(context: .confirmed(userID: "reader-A"))
        let old = try f.document("article")
        let callback = f.binding.progressHandler(for: old)
        f.model.storageIdentityChanged()
        _ = try f.document("article")
        callback(0.95)
        XCTAssertNil(f.model.snapshot.progress["article"])
        XCTAssertTrue(f.progressEffects.isEmpty)
    }

    func testDismantledDocumentAndDisappearedSessionCannotAddAnotherEdit() throws {
        let f = ReaderBindingFixture()
        let session = try XCTUnwrap(f.open("article"))
        let doc = try XCTUnwrap(f.binding.beginDocument(session, documentID: UUID().uuidString))
        f.binding.markDocumentReady(doc)
        let callback = f.binding.progressHandler(for: doc)
        f.binding.endDocument(doc)
        callback(0.8)
        XCTAssertTrue(f.progressEffects.isEmpty)
        let another = try XCTUnwrap(f.binding.beginDocument(session, documentID: UUID().uuidString))
        f.binding.markDocumentReady(another)
        f.binding.endSession(session)
        XCTAssertFalse(f.binding.record(0.8, document: another))
        XCTAssertNil(f.model.snapshot.progress["article"])
    }

    func testOldDismantleCannotCloseNewDocumentOrNewArticleSession() throws {
        let f = ReaderBindingFixture()
        let oldSession = try XCTUnwrap(f.open("old"))
        let oldDoc = try XCTUnwrap(f.binding.beginDocument(oldSession, documentID: UUID().uuidString))
        let fresh = try f.document("new")
        f.binding.endDocument(oldDoc)
        f.binding.endSession(oldSession)
        XCTAssertTrue(f.binding.record(0.7, document: fresh))
        XCTAssertEqual(f.model.snapshot.progress["new"], 0.7)
    }

    func testReentrantContextChangeDuringMarkReadSuppressesOldOpenAnalytics() {
        let f = ReaderBindingFixture()
        f.onMark = { f.model.changeContext(to: .confirmed(userID: "reader-B")) }
        XCTAssertNil(f.open("old"))
        XCTAssertTrue(f.opens.isEmpty)
        XCTAssertTrue(f.model.snapshot.readArticleIDs.isEmpty)
        XCTAssertTrue(f.progressEffects.isEmpty)
    }

    func testReentrantContextChangeDuringSchedulerCannotExportOldProgressAnalytics() throws {
        let f = ReaderBindingFixture()
        let doc = try f.document("old")
        f.onSchedule = { f.model.changeContext(to: .confirmed(userID: "reader-B")) }
        XCTAssertFalse(f.binding.record(0.9, document: doc))
        f.fireAll()
        XCTAssertTrue(f.progressEffects.isEmpty)
        XCTAssertNil(f.model.snapshot.progress["old"])
    }

    func testReentrantOpenCannotReplaceOriginalActivationMidCallback() {
        let f = ReaderBindingFixture()
        f.onOpen = { XCTAssertNil(f.open("nested")) }
        let session = f.open("original")
        XCTAssertNotNil(session)
        XCTAssertEqual(f.opens, ["original"])
        XCTAssertEqual(f.model.snapshot.readArticleIDs, ["original"])
    }

    func testAcceptedDebounceCanFinishAfterCloseButCannotAcquireAnotherOwner() throws {
        let f = ReaderBindingFixture()
        let session = try XCTUnwrap(f.open("article"))
        let doc = try XCTUnwrap(f.binding.beginDocument(session, documentID: UUID().uuidString))
        f.binding.markDocumentReady(doc)
        f.binding.record(0.45, document: doc)
        f.binding.endSession(session)
        f.fireAll()
        let bytes = try XCTUnwrap(f.records[.guest])
        let record = try ReadingHistoryRecordCodec.decode(bytes, namespace: .guest)
        XCTAssertEqual(record.entries.first?.progress, 0.45)
        XCTAssertFalse(f.binding.record(0.9, document: doc))
        f.model.changeContext(to: .confirmed(userID: "reader-B"))
        f.fireAll()
        XCTAssertNil(f.model.snapshot.progress["article"])
    }

    func testReadFailureLeavesReadingAvailableWithVisibleIssueButDoesNotOverwriteRecord() throws {
        let f = ReaderBindingFixture(context: .unresolved)
        f.failRead = true
        f.model.changeContext(to: .guest)
        let doc = try f.document("article")
        f.binding.record(0.8, document: doc)
        f.fireAll()
        XCTAssertNotNil(f.model.snapshot.issueMessage)
        XCTAssertTrue(f.model.snapshot.canRetry)
        XCTAssertTrue(f.writes.isEmpty)
        XCTAssertEqual(f.opens, ["article"])
    }

    func testMalformedDocumentIdentifierCannotBecomeReady() throws {
        let f = ReaderBindingFixture()
        let session = try XCTUnwrap(f.open("article"))
        for id in ["", "article", String(repeating: "x", count: 500)] {
            XCTAssertNil(f.binding.beginDocument(session, documentID: id))
        }
        XCTAssertTrue(f.progressEffects.isEmpty)
    }
}

@MainActor
private final class ReaderBindingFixture {
    enum Failure: Error { case read }
    struct ProgressEffect { let article: String; let value: Double }
    var records: [ReadingHistoryNamespace: Data] = [:]
    var writes: [ReadingHistoryNamespace] = []
    var scheduled: [@MainActor () -> Void] = []
    var opens: [String] = []
    var progressEffects: [ProgressEffect] = []
    var failRead = false
    var onMark: (@MainActor () -> Void)?
    var onOpen: (@MainActor () -> Void)?
    var onSchedule: (@MainActor () -> Void)?

    lazy var model = ReadingHistoryModel(storage: .init(read: { [unowned self] namespace in
        if self.failRead { throw Failure.read }
        return self.records[namespace]
    }, write: { [unowned self] namespace, data in
        self.records[namespace] = data
        self.writes.append(namespace)
    }), schedule: { [unowned self] _, action in
        self.scheduled.append(action)
        let hook = self.onSchedule
        self.onSchedule = nil
        hook?()
        return {} // Deliberately permit delivery after cancellation.
    })
    lazy var binding = ReaderHistoryBinding(model: model, markRead: { [unowned self] ticket in
        self.model.markRead(ticket)
        let hook = self.onMark
        self.onMark = nil
        hook?()
    })

    init(context: ReadingHistoryContext = .guest) { model.changeContext(to: context) }

    func open(_ article: String) -> ReaderHistoryBinding.Session? {
        binding.beginArticle(articleID: article, onOpen: { [unowned self] in
            self.opens.append(article)
            self.onOpen?()
        }, onProgress: { [unowned self] value in
            self.progressEffects.append(.init(article: article, value: value))
        })
    }

    func document(_ article: String) throws -> ReaderHistoryBinding.Document {
        let session = try XCTUnwrap(open(article))
        let doc = try XCTUnwrap(binding.beginDocument(session, documentID: UUID().uuidString))
        binding.markDocumentReady(doc)
        return doc
    }

    func fireAll() {
        let callbacks = scheduled
        scheduled = []
        callbacks.forEach { $0() }
    }
}
