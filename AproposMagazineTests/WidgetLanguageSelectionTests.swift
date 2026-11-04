import XCTest
@testable import Apropos

final class WidgetLanguageSelectionTests: XCTestCase {
    private func withDefaults(_ check: (UserDefaults) throws -> Void) throws {
        let suite = "AproposWidgetLanguageTests." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        try check(defaults)
    }

    private func article(_ id: String, name: String) -> WidgetArticle {
        WidgetArticle(id: id, name: name, slug: "story", thumbURL: "", intro: "", date: "2026-10-31", topic: "Anmeldelser")
    }

    func testSwitchFiltersTheSameStoredFeedAndDoesNotRewriteIt() throws {
        try withDefaults { defaults in
            let danish = article("0123456789abcdef01234567", name: "Dansk titel")
            let english = article("en_0123456789abcdef01234567", name: "English title")
            let malformed = article("en_invalid", name: "Invalid English identity")
            let original = try JSONEncoder().encode([danish, english, malformed])
            defaults.set(original, forKey: WidgetDataStore.latestArticlesKey)
            defaults.set("en", forKey: WidgetDataStore.interfaceLanguageKey)
            XCTAssertEqual(WidgetDataStore.interfaceLanguageCode(from: defaults), "en")
            XCTAssertEqual(WidgetDataStore.loadLatestArticles(from: defaults), [english])
            defaults.set("da", forKey: WidgetDataStore.interfaceLanguageKey)
            XCTAssertEqual(WidgetDataStore.loadLatestArticles(from: defaults), [danish])
            XCTAssertEqual(defaults.data(forKey: WidgetDataStore.latestArticlesKey), original)
        }
    }

    func testEmptyEnglishDoesNotFallBackToTheLegacyDanishCache() throws {
        try withDefaults { defaults in
            let danish = article("0123456789abcdef01234567", name: "Dansk titel")
            defaults.set(try JSONEncoder().encode([danish]), forKey: WidgetDataStore.latestArticlesKey)
            let legacy: [String: Any] = ["articles": [["id": danish.id, "name": danish.name]]]
            let originalLegacy = try JSONSerialization.data(withJSONObject: legacy)
            defaults.set(originalLegacy, forKey: "cached_articles")
            defaults.set("en", forKey: WidgetDataStore.interfaceLanguageKey)
            XCTAssertTrue(WidgetDataStore.loadLatestArticles(from: defaults).isEmpty)
            defaults.removeObject(forKey: WidgetDataStore.latestArticlesKey)
            XCTAssertTrue(WidgetDataStore.loadLatestArticles(from: defaults).isEmpty)
            defaults.set("da", forKey: WidgetDataStore.interfaceLanguageKey)
            XCTAssertEqual(WidgetDataStore.loadLatestArticles(from: defaults).map(\.id), [danish.id])
            XCTAssertEqual(defaults.data(forKey: "cached_articles"), originalLegacy)
        }
    }

    func testUnsupportedOrMissingPreferenceUsesDanishWithoutLosingTheStoredChoice() throws {
        try withDefaults { defaults in
            XCTAssertEqual(WidgetDataStore.interfaceLanguageCode(from: defaults), "da")
            defaults.set("sv", forKey: WidgetDataStore.interfaceLanguageKey)
            XCTAssertEqual(WidgetDataStore.interfaceLanguageCode(from: defaults), "da")
            XCTAssertEqual(defaults.string(forKey: WidgetDataStore.interfaceLanguageKey), "sv")
            XCTAssertEqual(WidgetLocalization.locale(for: "en").identifier, "en_GB")
            XCTAssertEqual(WidgetLocalization.locale(for: "da").identifier, "da_DK")
            XCTAssertEqual(WidgetArticleFormatting.ctaText(for: article("a", name: "Editorial title"), languageCode: "en"), "Read the article →")
            XCTAssertEqual(WidgetArticleFormatting.ctaText(for: article("a", name: "Editorial title"), languageCode: "da"), "Læs artiklen →")
        }
    }
}
