import XCTest
@testable import Apropos

final class WebflowLiveCatalogLoaderTests: XCTestCase {
    private let collection = String(repeating: "a", count: 24)
    private func item(_ number: Int, archived: Bool = false, draft: Bool = false) -> [String: Any] {
        ["id": String(format: "%024x", number), "isDraft": draft, "isArchived": archived,
         "lastPublished": "2026-10-20T10:00:00Z", "fieldData": ["name": "Test", "slug": "story-\(number)", "content": "Body"]]
    }
    private func response(_ items: [[String: Any]], total: Int, offset: Int = 0, limit: Int = 100,
                          status: Int = 200) throws -> WebflowLiveCatalogLoader.Response {
        .init(data: try JSONSerialization.data(withJSONObject: ["items": items,
            "pagination": ["total": total, "offset": offset, "limit": limit]]), status: status)
    }

    func testLiveURLCannotSelectStagedItemsOrInjectAPath() throws {
        let url = try WebflowLiveCatalogLoader.liveURL(collectionID: collection, offset: 100)
        XCTAssertEqual(url.path, "/v2/collections/\(collection)/items/live")
        XCTAssertFalse(url.absoluteString.contains("live=true"))
        XCTAssertThrowsError(try WebflowLiveCatalogLoader.liveURL(collectionID: "../outside", offset: 0))
    }

    func testRawPageCountContinuesAfterArchivedItemAndNormalizesOnlyLiveDraftFlags() async throws {
        let fixture = LiveCatalogFixture([try response([item(1, archived: true), item(2, draft: true)], total: 3, limit: 2),
                                          try response([item(3)], total: 3, offset: 2, limit: 2)])
        let loader = WebflowLiveCatalogLoader(transport: { try await fixture.perform($0) })
        let result = try await loader.load(collectionID: collection, token: "local-fixture", pageLimit: 2)
        let articles = try result.map { try JSONDecoder().decode(Article.self, from: $0) }
        XCTAssertEqual(articles.map(\.slug), ["story-2", "story-3"])
        XCTAssertTrue(articles.allSatisfy(\.isPubliclyPublished))
        let requests = await fixture.requests
        XCTAssertEqual(requests.map { URLComponents(url: $0.url!, resolvingAgainstBaseURL: false)!.queryItems!
            .first(where: { $0.name == "offset" })!.value }, ["0", "2"])
        XCTAssertEqual(requests.first?.value(forHTTPHeaderField: "Authorization"), "Bearer local-fixture")
    }

    func testShortPageUsesTotalAndDoesNotReturnPartialCatalog() async throws {
        let fixture = LiveCatalogFixture([try response([item(1)], total: 2),
                                          try response([item(2)], total: 2, offset: 1)])
        let rows = try await WebflowLiveCatalogLoader(transport: { try await fixture.perform($0) })
            .load(collectionID: collection, token: "local-fixture")
        XCTAssertEqual(rows.count, 2)
        let count = await fixture.requests.count
        XCTAssertEqual(count, 2)
    }

    func testFailedSecondPageIsFailureRatherThanPartialSuccess() async throws {
        let fixture = LiveCatalogFixture([try response([item(1)], total: 2),
                                          try response([], total: 2, offset: 1, status: 503)])
        do {
            _ = try await WebflowLiveCatalogLoader(transport: { try await fixture.perform($0) })
                .load(collectionID: collection, token: "local-fixture")
            XCTFail("Must not return first page")
        } catch WebflowLiveCatalogLoader.Failure.http(503) {} catch { XCTFail("\(error)") }
    }

    func testChangingTotalDuplicateIDsAndTruncationRejectCatalog() async throws {
        for next in [try response([item(1)], total: 2, offset: 1),
                     try response([item(2)], total: 3, offset: 1),
                     try response([], total: 2, offset: 1)] {
            let fixture = LiveCatalogFixture([try response([item(1)], total: 2), next])
            do {
                _ = try await WebflowLiveCatalogLoader(transport: { try await fixture.perform($0) })
                    .load(collectionID: collection, token: "local-fixture")
                XCTFail("Unstable catalog must fail")
            } catch {}
        }
    }

    func testMissingPaginationAndInvalidPublicationDoNotLookLikeEmptySuccess() async throws {
        for data in [Data("{\"items\":[]}".utf8),
                     try JSONSerialization.data(withJSONObject: ["items": [item(1).merging(["lastPublished": "invalid"]) { _, new in new }],
                        "pagination": ["offset": 0, "limit": 100, "total": 1]])] {
            let loader = WebflowLiveCatalogLoader(transport: { _ in .init(data: data, status: 200) })
            do { _ = try await loader.load(collectionID: collection, token: "local-fixture"); XCTFail("Must fail") }
            catch {}
        }
    }

    func testEmptyAuthoritativeLiveCatalogIsSuccess() async throws {
        let reply = try response([], total: 0)
        let result = try await WebflowLiveCatalogLoader(transport: { _ in reply })
            .load(collectionID: collection, token: "local-fixture")
        XCTAssertTrue(result.isEmpty)
    }

    func testArchivedPublicationSurvivesCopiesFavoritesAndDiskEncoding() throws {
        let archived = try JSONDecoder().decode(Article.self, from: JSONSerialization.data(withJSONObject: item(1, archived: true)))
        XCTAssertFalse(archived.isPubliclyPublished)
        XCTAssertTrue(ArticleFeedSnapshot.merging([archived], retainingDetailsFrom: []).isEmpty)
        let disk = try JSONDecoder().decode(Article.self, from: JSONEncoder().encode(archived.strippingBodyContent()))
        XCTAssertEqual(disk.isArchived, true)
        XCTAssertFalse(disk.isPubliclyPublished)
        let favorite = FavoriteArticleDocumentCodec.decode(FavoriteArticleDocumentCodec.encode(archived), documentID: archived.id)
        XCTAssertEqual(favorite.isArchived, true)
        XCTAssertFalse(favorite.isPubliclyPublished)
    }

    func testWithdrawalMarkerIsNotPublicAndIsNotNormalizedAsLiveData() throws {
        let tombstone: [String: Any] = ["id": String(format: "%024x", 1), "isDraft": true, "isArchived": true,
                                       "fieldData": ["slug": "withdrawn"], "lastPublished": NSNull()]
        let data = try JSONSerialization.data(withJSONObject: tombstone)
        let article = try JSONDecoder().decode(Article.self, from: data)
        XCTAssertFalse(article.isPubliclyPublished)
        XCTAssertThrowsError(try WebflowLiveCatalogLoader.normalizedLiveItem(data))
        XCTAssertTrue(CMSMirrorDocumentPolicy.isWithdrawn(tombstone))
        XCTAssertFalse(FirestoreArticleError.withdrawn.allowsCMSFallback)
        XCTAssertFalse(FirestoreArticleError.decodeFailed("bad data").allowsCMSFallback)
        XCTAssertTrue(FirestoreArticleError.empty.allowsCMSFallback)
    }

    func testMirrorWithdrawalsClearFeedWithoutFallingBackOrDecodingRemovedBodies() throws {
        let tombstone: [String: Any] = ["id": String(format: "%024x", 1), "publicationState": "withdrawn"]
        let decoded = try CMSArticleDocumentCodec.decodeFeed([(id: "withdrawn", data: tombstone)])
        XCTAssertTrue(decoded.articles.isEmpty)
        XCTAssertTrue(decoded.failures.isEmpty)
        XCTAssertThrowsError(try CMSArticleDocumentCodec.decodeArticle(from: tombstone)) { error in
            XCTAssertFalse((error as? FirestoreArticleError)?.allowsCMSFallback ?? true)
        }
    }

    func testMirrorMixedFeedStripsBodiesAndRejectsMalformedDataAsEmptySuccess() throws {
        let result = try CMSArticleDocumentCodec.decodeFeed([
            (id: String(format: "%024x", 1), data: item(1)),
            (id: "withdrawn", data: ["publicationState": "withdrawn"]),
            (id: "broken", data: ["fieldData": ["name": "Missing ID"]]),
            (id: "unsafe-path", data: item(2).merging(["id": "other/document"]) { _, new in new })])
        XCTAssertEqual(result.articles.count, 1)
        XCTAssertTrue(result.articles[0].content?.isEmpty != false)
        XCTAssertEqual(result.failures.count, 2)
        XCTAssertThrowsError(try CMSArticleDocumentCodec.decodeFeed([(id: "broken", data: [:])]))
    }

    func testLegacyMetadataIsRetainedButExplicitWithdrawalAndArchiveAreFiltered() {
        XCTAssertFalse(CMSMirrorDocumentPolicy.isWithdrawn(["fieldData": ["name": "Legacy topic"]]))
        XCTAssertTrue(CMSMirrorDocumentPolicy.isWithdrawn(["isArchived": true, "isDraft": false]))
        XCTAssertTrue(CMSMirrorDocumentPolicy.isWithdrawn(["publicationState": "withdrawn"]))
    }
}

private actor LiveCatalogFixture {
    private var responses: [WebflowLiveCatalogLoader.Response]
    private(set) var requests = [URLRequest]()
    init(_ responses: [WebflowLiveCatalogLoader.Response]) { self.responses = responses }
    func perform(_ request: URLRequest) throws -> WebflowLiveCatalogLoader.Response {
        requests.append(request)
        guard !responses.isEmpty else { throw URLError(.badServerResponse) }
        return responses.removeFirst()
    }
}
