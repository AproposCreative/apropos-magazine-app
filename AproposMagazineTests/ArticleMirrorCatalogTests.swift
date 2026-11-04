import XCTest
@testable import Apropos

@MainActor
final class ArticleMirrorCatalogTests: XCTestCase {
    private let id = "6ae1f9da0e01d3d2ff34859f"
    private enum ReadFailure: Error { case unavailable }

    @MainActor private final class HeldReads {
        var requested: [ArticleContentLanguage] = []
        var pending: [CheckedContinuation<ArticleMirrorCatalog.Source, Error>] = []
        func read(_ language: ArticleContentLanguage) async throws -> ArticleMirrorCatalog.Source {
            requested.append(language)
            return try await withCheckedThrowingContinuation { pending.append($0) }
        }
    }

    private func waitForRead(_ count: Int, _ held: HeldReads) async throws {
        for _ in 0..<1_000 {
            if held.requested.count >= count && !held.pending.isEmpty { return }
            await Task.yield()
        }
        XCTFail("Expected an actual held mirror read")
        throw ReadFailure.unavailable
    }

    private func source(_ language: ArticleContentLanguage, empty: Bool = false,
                        cache: Bool = false, pending: Bool = false) -> ArticleMirrorCatalog.Source {
        let readerID = language == .danish ? id : "en_" + id
        var data: [String: Any] = ["id": readerID]
        if language == .english {
            data["contentLanguage"] = "en"; data["sourceArticleID"] = id
            data["cmsLocaleId"] = ArticleContentLanguage.englishCMSLocaleID
        }
        return .init(language: language, documents: empty ? [] : [(readerID, data)],
                     isFromCache: cache, hasPendingWrites: pending)
    }

    func testEnglishConfigurationRequiresActualBooleanTrueAndCollectionsAreSeparate() {
        XCTAssertFalse(ArticleMirrorCatalog.englishEnabled(in: [:]))
        let disabledValues: [Any] = [false, "true", "YES", 1, 0, NSNumber(value: 1), NSNull()]
        for value in disabledValues {
            XCTAssertFalse(ArticleMirrorCatalog.englishEnabled(in: ["ReaderEnglishArticlesEnabled": value]))
        }
        XCTAssertTrue(ArticleMirrorCatalog.englishEnabled(in: ["ReaderEnglishArticlesEnabled": true]))
        XCTAssertTrue(ArticleMirrorCatalog.englishEnabled(in: ["ReaderEnglishArticlesEnabled": NSNumber(value: true)]))
        XCTAssertEqual(ArticleContentLanguage.danish.mirrorCollection, "articles")
        XCTAssertEqual(ArticleContentLanguage.english.mirrorCollection, "articles_en")
    }

    func testDisabledEnglishPerformsOnlyDanishReadAndKeepsFreshness() async throws {
        var calls: [ArticleContentLanguage] = []
        let expected = source(.danish, cache: true, pending: true)
        let values = try await ArticleMirrorCatalog.load(englishEnabled: false, stillCurrent: { true }) { language in
            calls.append(language); return expected
        }
        XCTAssertEqual(calls, [.danish])
        XCTAssertEqual(values.map(\.language), [.danish])
        XCTAssertTrue(try XCTUnwrap(values.first).isFromCache)
        XCTAssertTrue(try XCTUnwrap(values.first).hasPendingWrites)
    }

    func testAssemblyCannotCommitUntilBothHeldSourcesAreKnownAndValidated() async throws {
        let held = HeldReads()
        var committed: [ArticleMirrorCatalog.Source] = []
        let task = Task {
            let values = try await ArticleMirrorCatalog.load(englishEnabled: true, stillCurrent: { true }, read: held.read)
            committed = values
        }
        try await waitForRead(1, held)
        XCTAssertEqual(held.requested, [.danish]); XCTAssertTrue(committed.isEmpty)
        held.pending.removeFirst().resume(returning: source(.danish, cache: true))
        try await waitForRead(2, held)
        XCTAssertEqual(held.requested, [.danish, .english]); XCTAssertTrue(committed.isEmpty)
        held.pending.removeFirst().resume(returning: source(.english, pending: true))
        try await task.value
        XCTAssertEqual(committed.map(\.language), [.danish, .english])
        XCTAssertEqual(committed.map(\.isFromCache), [true, false])
        XCTAssertEqual(committed.map(\.hasPendingWrites), [false, true])
    }

    func testReplacedPermissionWhileDanishIsHeldCannotReadEnglishOrCommit() async throws {
        let held = HeldReads()
        var current = true, committed = false
        let task = Task {
            _ = try await ArticleMirrorCatalog.load(englishEnabled: true, stillCurrent: { current }, read: held.read)
            committed = true
        }
        try await waitForRead(1, held)
        current = false
        held.pending.removeFirst().resume(returning: source(.danish))
        do { try await task.value; XCTFail("Replaced permission must be cancelled") }
        catch is CancellationError { } catch { XCTFail("Unexpected error: \(error)") }
        XCTAssertEqual(held.requested, [.danish]); XCTAssertFalse(committed)
        var calls = 0
        do {
            _ = try await ArticleMirrorCatalog.load(englishEnabled: true, stillCurrent: { false }) { _ in
                calls += 1; return self.source(.danish)
            }
            XCTFail("Closed initial permission must fail")
        } catch is CancellationError { } catch { XCTFail("Unexpected error: \(error)") }
        XCTAssertEqual(calls, 0)
    }

    func testTaskCancellationWhileReadIsHeldCannotStartSecondRead() async throws {
        let held = HeldReads()
        let task = Task { _ = try await ArticleMirrorCatalog.load(englishEnabled: true, stillCurrent: { true }, read: held.read) }
        try await waitForRead(1, held); task.cancel()
        held.pending.removeFirst().resume(returning: source(.danish))
        do { _ = try await task.value; XCTFail("Cancelled task must not return sources") }
        catch is CancellationError { } catch { XCTFail("Unexpected error: \(error)") }
        XCTAssertEqual(held.requested, [.danish])
    }

    func testKnownEmptyEnglishDiffersFromFailureAndFailureCannotCommitPartialDanish() async throws {
        let values = try await ArticleMirrorCatalog.load(englishEnabled: true, stillCurrent: { true }) { language in
            self.source(language, empty: language == .english)
        }
        XCTAssertEqual(values.map(\.language), [.danish, .english])
        XCTAssertFalse(values[0].documents.isEmpty); XCTAssertTrue(values[1].documents.isEmpty)
        var calls: [ArticleContentLanguage] = [], committed = false
        do {
            _ = try await ArticleMirrorCatalog.load(englishEnabled: true, stillCurrent: { true }) { language in
                calls.append(language)
                if language == .english { throw ReadFailure.unavailable }
                return self.source(language)
            }
            committed = true
        } catch ReadFailure.unavailable { } catch { XCTFail("Unexpected error: \(error)") }
        XCTAssertEqual(calls, [.danish, .english]); XCTAssertFalse(committed)
    }

    func testWrongSourceAndMisplacedWithdrawnIdentityAreRejectedBeforeCommit() async throws {
        let misplaced = ArticleMirrorCatalog.Source(language: .english,
            documents: [(id, ["id": id, "publicationState": "withdrawn", "isDraft": true])],
            isFromCache: false, hasPendingWrites: false)
        XCTAssertThrowsError(try ArticleMirrorCatalog.validate(misplaced))
        var committed = false, calls: [ArticleContentLanguage] = []
        do {
            _ = try await ArticleMirrorCatalog.load(englishEnabled: true, stillCurrent: { true }) { language in
                calls.append(language); return self.source(.english)
            }
            committed = true
        } catch ArticleMirrorCatalog.Failure.invalidSource { } catch { XCTFail("Unexpected error: \(error)") }
        XCTAssertEqual(calls, [.danish]); XCTAssertFalse(committed)
        let duplicated = ArticleMirrorCatalog.Source(language: .danish,
            documents: [(id, ["id": id]), (id, ["id": id])], isFromCache: false, hasPendingWrites: false)
        XCTAssertThrowsError(try ArticleMirrorCatalog.validate(duplicated))
    }

    func testLegacyOptionalNullsAndEnglishTombstoneHaveDistinctSafeIdentity() throws {
        let legacy: [String: Any] = ["id": id, "cmsLocaleId": NSNull(), "sourceArticleID": NSNull(),
                                    "publicationState": "withdrawn"]
        XCTAssertNoThrow(try ArticleMirrorCatalog.validate(.init(language: .danish,
            documents: [(id, legacy)], isFromCache: false, hasPendingWrites: false)))
        var bad = legacy; bad["contentLanguage"] = NSNull()
        XCTAssertThrowsError(try ArticleMirrorCatalog.validate(.init(language: .danish,
            documents: [(id, bad)], isFromCache: false, hasPendingWrites: false)))
        let englishID = "en_" + id
        var tombstone: [String: Any] = ["id": englishID, "sourceArticleID": id,
            "cmsLocaleId": ArticleContentLanguage.englishCMSLocaleID, "contentLanguage": "en",
            "publicationState": "withdrawn", "fieldData": ["slug": "old-story"]]
        XCTAssertNoThrow(try ArticleMirrorCatalog.validate(.init(language: .english,
            documents: [(englishID, tombstone)], isFromCache: false, hasPendingWrites: false)))
        tombstone["sourceArticleID"] = String(repeating: "f", count: 24)
        XCTAssertThrowsError(try ArticleMirrorCatalog.validate(.init(language: .english,
            documents: [(englishID, tombstone)], isFromCache: false, hasPendingWrites: false)))
    }

    func testOnlyLegacyDanishWithdrawalMayOmitPayloadID() throws {
        let withdrawals: [[String: Any]] = [["publicationState": "withdrawn"], ["isDraft": true], ["isArchived": true]]
        for withdrawn in withdrawals {
            XCTAssertNoThrow(try ArticleMirrorCatalog.validate(.init(language: .danish,
                documents: [(id, withdrawn)], isFromCache: false, hasPendingWrites: false)))
            XCTAssertThrowsError(try ArticleMirrorCatalog.validate(.init(language: .english,
                documents: [("en_" + id, withdrawn)], isFromCache: false, hasPendingWrites: false)))
            var mismatch = withdrawn; mismatch["id"] = "other-story"
            XCTAssertThrowsError(try ArticleMirrorCatalog.validate(.init(language: .danish,
                documents: [(id, mismatch)], isFromCache: false, hasPendingWrites: false)))
            var unknownLocale = withdrawn; unknownLocale["cmsLocaleId"] = ArticleContentLanguage.englishCMSLocaleID
            XCTAssertThrowsError(try ArticleMirrorCatalog.validate(.init(language: .danish,
                documents: [(id, unknownLocale)], isFromCache: false, hasPendingWrites: false)))
        }
        XCTAssertThrowsError(try ArticleMirrorCatalog.validate(.init(language: .danish,
            documents: [(id, [:])], isFromCache: false, hasPendingWrites: false)))
    }
}
