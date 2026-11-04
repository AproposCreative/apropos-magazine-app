import XCTest
@testable import Apropos

final class AppLocalizationTests: XCTestCase {
    func testExplicitLanguageChangesOwnInterfaceCopyWithoutUsingDeviceLanguage() {
        XCTAssertEqual(AppLocalization.string("Min side", language: .danish), "Min side")
        XCTAssertEqual(AppLocalization.string("Min side", language: .english), "My page")
        XCTAssertEqual(AppLocalization.string("Min side", language: .danish), "Min side")
        XCTAssertEqual(AppLocalization.string("Gem og fortsæt", language: .english), "Save and continue")
        XCTAssertEqual(AppLocalization.string("Dine interesser kunne ikke gemmes. Prøv igen.", language: .english),
                       "Your interests could not be saved. Try again.")
    }

    func testArticleCountUsesSingularOnlyForOneInBothLanguages() {
        XCTAssertEqual(AppLocalization.articleCount(0, language: .english), "0 articles")
        XCTAssertEqual(AppLocalization.articleCount(1, language: .english), "1 article")
        XCTAssertEqual(AppLocalization.articleCount(2, language: .english), "2 articles")
        XCTAssertEqual(AppLocalization.articleCount(0, language: .danish), "0 artikler")
        XCTAssertEqual(AppLocalization.articleCount(1, language: .danish), "1 artikel")
        XCTAssertEqual(AppLocalization.articleCount(2, language: .danish), "2 artikler")
    }

    func testFormatterKeepsValuesAndArgumentOrdering() {
        XCTAssertEqual(AppLocalization.format("Henter %lld %%", language: .danish, arguments: [42]), "Henter 42 %")
        XCTAssertEqual(AppLocalization.format("Henter %lld %%", language: .english, arguments: [42]), "Downloading 42 %")
        XCTAssertEqual(AppLocalization.string("GEMT", language: .english), "SAVED")
        XCTAssertEqual(AppLocalization.format("%lld af %lld artikler", language: .english, arguments: [3, 12]),
                       "3 of 12 articles")
        XCTAssertEqual(AppLocalization.format("%lld af %lld artikler", language: .danish, arguments: [3, 12]),
                       "3 af 12 artikler")
        let name = "Ada % & Å"
        XCTAssertEqual(AppLocalization.format("Skrevet af %@", language: .english, arguments: [name]),
                       "Written by " + name)
        XCTAssertEqual(AppLocalization.format("%lld ud af 6 stjerner", language: .english, arguments: [5]),
                       "5 out of 6 stars")
    }

    func testTaxonomyLocalizesEachLabelAndPreservesUnknownEditorialLabels() {
        XCTAssertEqual(AppLocalization.taxonomy("ANMELDELSER | TV-SERIER", language: .english),
                       "REVIEWS | TV SERIES")
        XCTAssertEqual(AppLocalization.taxonomy("Film • Koncerter", language: .english), "Film • Concerts")
        XCTAssertEqual(AppLocalization.taxonomy("Kultur & Mening", language: .english), "Culture & Opinion")
        XCTAssertEqual(AppLocalization.taxonomy("A New Editorial Topic 100%", language: .english),
                       "A New Editorial Topic 100%")
        XCTAssertEqual(AppLocalization.taxonomy("Anmeldelser | TV-serier", language: .danish),
                       "Anmeldelser | TV-serier")
    }

    func testUnknownContentIsNotTranslatedOrFormatted() {
        let headline = "Apropos — en fortælling med %lld og {title}"
        XCTAssertEqual(AppLocalization.string(headline, language: .english), headline)
        XCTAssertEqual(AppLocalization.string("person@example.invalid", language: .english),
                       "person@example.invalid")
        XCTAssertEqual(AppLocalization.string("En modtaget besked, som ikke er UI-copy.", language: .english),
                       "En modtaget besked, som ikke er UI-copy.")
    }

    func testLocalesMatchTheTwoSupportedInterfaceAndContentChoices() {
        XCTAssertEqual(AppLocalization.locale(for: .english).identifier, "en_GB")
        XCTAssertEqual(AppLocalization.locale(for: .danish).identifier, "da_DK")
        XCTAssertEqual(AppLocalization.language(for: Locale(identifier: "en_US")), .english)
        XCTAssertEqual(AppLocalization.language(for: Locale(identifier: "da_DK")), .danish)
        XCTAssertEqual(AppLocalization.language(for: Locale(identifier: "fr_FR")), .danish)
    }

    func testBothPackagedLanguagesHaveExactKeyAndFormatArgumentParity() throws {
        let danish = try table("da")
        let english = try table("en")
        XCTAssertGreaterThan(danish.count, 700)
        XCTAssertEqual(Set(danish.keys), Set(english.keys))
        for key in danish.keys {
            XCTAssertFalse(try XCTUnwrap(english[key]).isEmpty, key)
            XCTAssertEqual(try formatArguments(in: XCTUnwrap(danish[key])),
                           try formatArguments(in: XCTUnwrap(english[key])), key)
        }
    }

    func testDownloadProgressReleaseEntryUsesBothPackagedLanguageTables() throws {
        let url = try XCTUnwrap(Bundle.main.url(forResource: "whatsnew", withExtension: "json", subdirectory: "Resources/WhatsNew")
            ?? Bundle.main.url(forResource: "whatsnew", withExtension: "json", subdirectory: "WhatsNew")
            ?? Bundle.main.url(forResource: "whatsnew", withExtension: "json"))
        let entries = try JSONDecoder().decode([WhatsNewEntry].self, from: Data(contentsOf: url))
        let danish = try table("da"), english = try table("en")
        for version in ["1.140.0", "1.141.0"] {
            let entry = try XCTUnwrap(entries.first { $0.version == version })
            let keys = [entry.title] + (entry.subtitle.map { [$0] } ?? [])
                + entry.items.flatMap { [$0.title, $0.description] }
            XCTAssertFalse(keys.isEmpty)
            for key in keys {
                XCTAssertEqual(try XCTUnwrap(danish[key], key), key)
                let translation = try XCTUnwrap(english[key], key)
                XCTAssertFalse(translation.isEmpty)
                XCTAssertNotEqual(translation, key, "The Danish release prose must not fall through unchanged in English")
                XCTAssertEqual(AppLocalization.string(key, language: .english), translation)
            }
        }
    }

    private func table(_ language: String) throws -> [String: String] {
        let path = try XCTUnwrap(Bundle.main.path(forResource: language, ofType: "lproj"))
        XCTAssertTrue(path.hasSuffix("/" + language + ".lproj"))
        let localized = try XCTUnwrap(Bundle(path: path))
        let url = try XCTUnwrap(localized.url(forResource: "Localizable", withExtension: "strings"))
        let data = try Data(contentsOf: url)
        return try XCTUnwrap(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: String])
    }

    private func formatArguments(in value: String) throws -> [String] {
        let expression = try NSRegularExpression(pattern: #"%(?:[0-9]+\$)?(?:ll|l)?[@difgu]"#)
        return expression.matches(in: value, range: NSRange(value.startIndex..., in: value)).compactMap {
            Range($0.range, in: value).map { String(value[$0]) }
        }.sorted()
    }
}
