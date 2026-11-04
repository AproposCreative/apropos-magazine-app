import FirebaseCore
import XCTest
@testable import Apropos

@MainActor
final class CategoryMembershipTests: XCTestCase {
    private func model(_ articles: [Article], topics: [Topic] = [
        Topic(id: "film", name: "Film"), Topic(id: "culture", name: "Kultur")
    ]) -> ArticleViewModel {
        let identity = CanonicalSessionState()
        _ = identity.adopt(nil)
        let model = ArticleViewModel(startup: ReaderSDKStartupState(), identity: identity,
            actualUserID: { nil }, readEffects: .init())
        model.topics = topics
        model.articles = articles
        return model
    }

    private func article(_ id: String, primary: String? = nil, secondary: [String]? = nil) -> Article {
        var fields: [String: Any] = ["name": id, "slug": id]
        if let primary { fields["topic"] = primary }
        if let secondary { fields["topics"] = secondary }
        let data = try! JSONSerialization.data(withJSONObject: ["id": id, "fieldData": fields])
        return try! JSONDecoder().decode(Article.self, from: data)
    }

    func testPrimaryMembershipRemainsAvailable() {
        let vm = model([article("primary", primary: "culture"), article("unrelated", primary: "film")])
        XCTAssertEqual(vm.articles(for: "Kultur").map(\.id), ["primary"])
        XCTAssertNil(FirebaseApp.app())
    }

    func testSecondaryMembershipIsAvailableDespiteAnotherPrimaryTopic() {
        let vm = model([article("secondary", primary: "film", secondary: ["culture"])])
        XCTAssertEqual(vm.articles.count, 1)
        XCTAssertEqual(vm.articles(for: "Kultur").map(\.id), ["secondary"])
        XCTAssertEqual(vm.articles(for: "Film").map(\.id), ["secondary"])
        XCTAssertNil(FirebaseApp.app())
    }

    func testSecondaryOnlyArticleDoesNotNeedAPrimaryTopic() {
        let vm = model([article("secondary-only", secondary: ["culture"])])
        XCTAssertEqual(vm.articles(for: "Kultur").map(\.id), ["secondary-only"])
    }

    func testRepeatedMembershipAndSameNamedTopicsDoNotDuplicateArticles() {
        let vm = model([article("both", primary: "culture", secondary: ["culture", "other-culture", "culture"]),
                        article("alias", secondary: ["other-culture"])], topics: [
            Topic(id: "culture", name: "Kultur"), Topic(id: "other-culture", name: "Kultur")
        ])
        XCTAssertEqual(vm.articles(for: "Kultur").map(\.id), ["both", "alias"])
    }

    func testUnknownAndMissingReferencesDoNotBecomeACategory() {
        let vm = model([article("unknown", primary: "missing", secondary: ["also-missing"]), article("none")],
                       topics: [Topic(id: "culture", name: "Kultur"), Topic(id: "general", name: "Generelt")])
        XCTAssertTrue(vm.articles(for: "Kultur").isEmpty)
        XCTAssertTrue(vm.articles(for: "Generelt").isEmpty)
        XCTAssertTrue(vm.articles(for: "").isEmpty)
    }

    func testMetadataRenameAndFeedRemovalAreReflectedWithoutRetainedMatches() {
        let vm = model([article("secondary", primary: "film", secondary: ["culture"])])
        XCTAssertEqual(vm.articles(for: "Kultur").map(\.id), ["secondary"])
        vm.topics = [Topic(id: "culture", name: "Samfund")]
        XCTAssertTrue(vm.articles(for: "Kultur").isEmpty)
        XCTAssertEqual(vm.articles(for: "Samfund").map(\.id), ["secondary"])
        vm.articles = []
        XCTAssertTrue(vm.articles(for: "Samfund").isEmpty)
    }
}
