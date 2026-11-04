import Foundation

/// Reader identity for the deliberately separate Danish/English CMS mirrors.
/// Danish IDs stay unchanged; English IDs never alias the Danish source item.
enum ArticleContentLanguage: String, Codable, CaseIterable, Sendable {
    case danish = "da"
    case english = "en"

    static let danishCMSLocaleID = "67dbf17ba540975b5b21c225"
    static let englishCMSLocaleID = "690ca0f6b0d13d8788354156"

    var cmsLocaleID: String {
        self == .danish ? Self.danishCMSLocaleID : Self.englishCMSLocaleID
    }

    var mirrorCollection: String { self == .danish ? "articles" : "articles_en" }

    var displayName: String { self == .danish ? "Dansk" : "English" }

    init?(preference: Language) {
        switch preference {
        case .danish: self = .danish
        case .english: self = .english
        case .swedish, .norwegian: return nil
        }
    }

    var preference: Language { self == .danish ? .danish : .english }

    func articleID(sourceID: String) -> String? {
        guard Self.isCMSArticleID(sourceID) else { return nil }
        return self == .danish ? sourceID : "en_" + sourceID
    }

    static func isCMSArticleID(_ value: String) -> Bool {
        value.utf8.count == 24 && value.utf8.allSatisfy {
            (48...57).contains($0) || (97...102).contains($0)
        }
    }

    static func isEnglishArticleID(_ value: String) -> Bool {
        value.hasPrefix("en_") && isCMSArticleID(String(value.dropFirst(3)))
    }

    static func validated(articleID: String, languageCode: String?,
                          sourceArticleID: String?, cmsLocaleId: String?) -> Self? {
        let language: Self
        if let languageCode {
            guard let declared = Self(rawValue: languageCode) else { return nil }
            language = declared
        } else {
            language = .danish
        }
        guard language.validates(articleID: articleID, sourceArticleID: sourceArticleID,
                                 cmsLocaleId: cmsLocaleId) else { return nil }
        return language
    }

    func validates(articleID: String, sourceArticleID: String?, cmsLocaleId: String?) -> Bool {
        switch self {
        case .danish:
            // Legacy and synthetic Danish IDs retain their established identity.
            // The new English namespace cannot be admitted as a legacy Danish row.
            guard !Self.isEnglishArticleID(articleID),
                  cmsLocaleId == nil || cmsLocaleId == Self.danishCMSLocaleID else { return false }
            return sourceArticleID.map { Self.isCMSArticleID($0) && $0 == articleID } ?? true
        case .english:
            guard let sourceArticleID, Self.isCMSArticleID(sourceArticleID),
                  cmsLocaleId == Self.englishCMSLocaleID else { return false }
            return articleID == "en_" + sourceArticleID
        }
    }
}
