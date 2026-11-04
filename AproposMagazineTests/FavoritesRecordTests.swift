import XCTest
@testable import Apropos

final class FavoritesRecordTests: XCTestCase {
    private func article(_ id: String = "article", name: String = "Titel", revision: String? = "r1") -> Article {
        Article(id: id, name: name, slug: id, content: "<p>PRIVATE BODY</p>", trailer: "<iframe>EMBED</iframe>",
                intro: "INTRO HTML", topicID: "topic", lastPublished: "2026-10-20T10:00:00Z", contentRevision: revision)
    }
    func testNamespacesAreSeparatedStableAndDoNotContainRawUserIdentifiers() throws {
        let a = try XCTUnwrap(FavoritesContext.confirmed(userID: "private-person-A").namespace)
        let b = try XCTUnwrap(FavoritesContext.confirmed(userID: "private-person-B").namespace)
        XCTAssertEqual(a, FavoritesContext.confirmed(userID: "private-person-A").namespace)
        XCTAssertNotEqual(a, b); XCTAssertNotEqual(a, .guest)
        XCTAssertFalse(a.storageKey.contains("private-person")); XCTAssertTrue(a.recordBinding.hasPrefix("account_"))
        XCTAssertNil(FavoritesContext.unresolved.namespace)
        for invalid in ["", " \n", "bad\u{0}uid", String(repeating: "a", count: 513)] {
            XCTAssertEqual(FavoritesContext.confirmed(userID: invalid), .unresolved)
        }
        XCTAssertEqual(FavoritesContext.confirmed(userID: nil), .guest)
    }
    func testActualArticleRoundTripRetainsLightMetadataWithoutBodyEmbedsOrAuthorBiography() throws {
        var original = article()
        original.author = Author(id: "writer", name: "Navn", bio: "PRIVATE BIO", imageURL: nil, position: "", photoURL: "")
        let data = try FavoritesRecordCodec.encode(.init(articles: [original]), namespace: .guest)
        let text = String(decoding: data, as: UTF8.self)
        for privateValue in ["PRIVATE BODY", "INTRO HTML", "PRIVATE BIO", "EMBED", "trailer", "\"author\":", "content\""] {
            XCTAssertFalse(text.contains(privateValue))
        }
        let decoded = try XCTUnwrap(FavoritesRecordCodec.decode(data, namespace: .guest).articles.first)
        XCTAssertEqual(decoded.name, "Titel"); XCTAssertEqual(decoded.bodyRevision, "r1")
        XCTAssertEqual(decoded.content, ""); XCTAssertEqual(decoded.intro, ""); XCTAssertNil(decoded.trailer); XCTAssertNil(decoded.author)
    }
    func testForeignNamespaceUnsupportedSchemaAndUnknownBodyFieldAreRejected() throws {
        let account = try XCTUnwrap(FavoritesContext.confirmed(userID: "A").namespace)
        let data = try FavoritesRecordCodec.encode(.init(articles: [article()]), namespace: .guest)
        XCTAssertThrowsError(try FavoritesRecordCodec.decode(data, namespace: account))
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        object["schemaVersion"] = 99
        XCTAssertThrowsError(try FavoritesRecordCodec.decode(JSONSerialization.data(withJSONObject: object), namespace: .guest)) { error in
            XCTAssertEqual(error as? FavoritesRecordCodec.Failure, .unsupportedVersion)
        }
        object["schemaVersion"] = 2
        var rows = try XCTUnwrap(object["base"] as? [[String: Any]])
        rows[0]["content"] = "INJECTED HTML"; object["base"] = rows
        XCTAssertThrowsError(try FavoritesRecordCodec.decode(JSONSerialization.data(withJSONObject: object), namespace: .guest))
    }
    func testDuplicateEmptyControlIdentifiersAndNonWebImageURLsAreRejected() throws {
        XCTAssertThrowsError(try FavoritesRecordCodec.encode(.init(articles: [article(), article()]), namespace: .guest))
        for id in ["", " article", "article\n", String(repeating: "x", count: 513)] {
            XCTAssertThrowsError(try FavoritesRecordCodec.lightweight(article(id)))
        }
        let unsafe = Article(id: "a", name: "A", slug: "a", content: "", intro: "", topicID: "", thumbURL: URL(string: "file:///private/path"))
        XCTAssertThrowsError(try FavoritesRecordCodec.lightweight(unsafe))
    }
    func testEntryAndEscapedByteLimitsRejectWithoutSilentlyPruningExplicitChoices() throws {
        let entries = (0..<FavoritesRecordCodec.maximumEntries).map { article("a-\($0)") }
        let data = try FavoritesRecordCodec.encode(.init(articles: entries), namespace: .guest)
        XCTAssertEqual(try FavoritesRecordCodec.decode(data, namespace: .guest).articles.count, 200)
        XCTAssertThrowsError(try FavoritesRecordCodec.encode(.init(articles: entries + [article("extra")]), namespace: .guest))
        let large = (0..<200).map { article("escaped-\($0)", name: String(repeating: "\"", count: 2048)) }
        XCTAssertThrowsError(try FavoritesRecordCodec.encode(.init(articles: large), namespace: .guest)) { error in
            XCTAssertEqual(error as? FavoritesRecordCodec.Failure, .limitExceeded)
        }
        XCTAssertThrowsError(try FavoritesRecordCodec.decode(Data(repeating: 0x20, count: FavoritesRecordCodec.maximumRecordBytes + 1), namespace: .guest))
    }
    func testMembershipMetadataPreservesActualBodyRevisionFallback() throws {
        let fallback = article(revision: nil)
        XCTAssertEqual(try FavoritesRecordCodec.lightweight(fallback).bodyRevision, fallback.bodyRevision)
        XCTAssertEqual(fallback.bodyRevision, "2026-10-20T10:00:00Z")
    }
    func testPendingTombstoneRoundTripRetainsStableIntentAttemptAndImmutablePayload() throws {
        let namespace = try XCTUnwrap(FavoritesContext.confirmed(userID: "A").namespace)
        let payload = FavoritesRecord.Metadata(article(name: "Original"))
        let display = FavoritesRecord.Metadata(article(name: "Enriched"))
        let pending = FavoritesRecord.Pending(intentID: UUID(), payload: payload, article: display,
                                              enabled: false, phase: .started, attemptID: UUID())
        let record = FavoritesRecord(base: [payload], pending: [pending], requiresRecovery: true)
        let decoded = try FavoritesRecordCodec.decode(FavoritesRecordCodec.encode(record, namespace: namespace), namespace: namespace)
        XCTAssertEqual(decoded, record); XCTAssertTrue(decoded.articles.isEmpty)
        XCTAssertEqual(decoded.pending.first?.payload.name, "Original")
        XCTAssertEqual(decoded.pending.first?.article.name, "Enriched")
    }
    func testStrictPhasesRejectInventedAttemptsDuplicateIntentsAndGuestCloudAuthority() throws {
        let namespace = try XCTUnwrap(FavoritesContext.confirmed(userID: "A").namespace)
        let payload = FavoritesRecord.Metadata(article())
        for phase in [FavoritesRecord.Phase.started, .acknowledged, .failed] {
            let invalid = FavoritesRecord(base: [], pending: [.init(intentID: UUID(), payload: payload, enabled: true, phase: phase)])
            XCTAssertThrowsError(try FavoritesRecordCodec.encode(invalid, namespace: namespace))
        }
        let pending = FavoritesRecord.Pending(intentID: UUID(), payload: payload, enabled: true)
        XCTAssertThrowsError(try FavoritesRecordCodec.encode(.init(base: [], pending: [pending]), namespace: .guest))
        XCTAssertThrowsError(try FavoritesRecordCodec.encode(.init(base: [], pending: [pending, pending]), namespace: namespace))
        let falseProof = FavoritesRecord.Pending(intentID: UUID(), payload: payload, enabled: true, phase: .started, attemptID: UUID())
        XCTAssertThrowsError(try FavoritesRecordCodec.encode(.init(base: [], pending: [falseProof]), namespace: namespace))
    }
    func testKnownOwnerV1MigrationCreatesOnlyBaseAndNeverSynthesizesCloudIntentOrProof() throws {
        let namespace = try XCTUnwrap(FavoritesContext.confirmed(userID: "A").namespace)
        let v2 = try FavoritesRecordCodec.encode(.init(articles: [article()]), namespace: namespace)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: v2) as? [String: Any])
        let v1 = try JSONSerialization.data(withJSONObject: ["schemaVersion": 1, "namespace": namespace.recordBinding, "entries": object["base"]!])
        XCTAssertThrowsError(try FavoritesRecordCodec.decode(v1, namespace: namespace))
        let migrated = try FavoritesRecordCodec.migrateLegacyV1(v1, namespace: namespace)
        XCTAssertEqual(migrated.articles.map(\.id), ["article"]); XCTAssertTrue(migrated.pending.isEmpty)
        XCTAssertTrue(migrated.requiresRecovery)
        XCTAssertThrowsError(try FavoritesRecordCodec.migrateLegacyV1(v1, namespace: .guest))
    }
    func testUnknownNestedFieldsAndPersistedServerProofAreRejected() throws {
        let namespace = try XCTUnwrap(FavoritesContext.confirmed(userID: "A").namespace)
        let pending = FavoritesRecord.Pending(intentID: UUID(), payload: .init(article()), enabled: true)
        let data = try FavoritesRecordCodec.encode(.init(base: [], pending: [pending]), namespace: namespace)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        var rows = try XCTUnwrap(object["pending"] as? [[String: Any]])
        rows[0]["serverMatched"] = true; object["pending"] = rows
        XCTAssertThrowsError(try FavoritesRecordCodec.decode(JSONSerialization.data(withJSONObject: object), namespace: namespace))
    }
    func testPendingCountAndScalarMemoryBoundsAreEnforcedWithoutPruning() throws {
        let namespace = try XCTUnwrap(FavoritesContext.confirmed(userID: "A").namespace)
        let rows = (0..<256).map { FavoritesRecord.Pending(intentID: UUID(), payload: .init(article("a-\($0)")), enabled: false) }
        try FavoritesRecordCodec.validateStructure(.init(base: [], pending: rows))
        XCTAssertThrowsError(try FavoritesRecordCodec.validateStructure(.init(base: [], pending: rows + [.init(intentID: UUID(), payload: .init(article("extra")), enabled: false)])))
        let large = (0..<200).map { FavoritesRecord.Metadata(article("large-\($0)", name: String(repeating: "x", count: 2048))) }
        XCTAssertThrowsError(try FavoritesRecordCodec.validateStructure(.init(base: large, pending: large.prefix(20).map { .init(intentID: UUID(), payload: $0, enabled: false) })))
        _ = namespace
    }

}
