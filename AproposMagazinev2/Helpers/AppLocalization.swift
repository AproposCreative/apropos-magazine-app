import Foundation

/// Localizes Apropos-owned interface copy only. CMS titles, bodies, messages,
/// identifiers and stored preference values must retain their source text.
enum AppLocalization {
    static func locale(for language: ArticleContentLanguage) -> Locale {
        Locale(identifier: language == .english ? "en_GB" : "da_DK")
    }

    static func language(for locale: Locale) -> ArticleContentLanguage {
        locale.language.languageCode?.identifier == "en" ? .english : .danish
    }

    static func string(_ key: String, language: ArticleContentLanguage,
                       bundle: Bundle = .main) -> String {
        guard let path = bundle.path(forResource: language.rawValue, ofType: "lproj"),
              let localized = Bundle(path: path) else { return key }
        return localized.localizedString(forKey: key, value: key, table: "Localizable")
    }

    static func format(_ key: String, language: ArticleContentLanguage,
                       arguments: [CVarArg], bundle: Bundle = .main) -> String {
        String(format: string(key, language: language, bundle: bundle),
               locale: locale(for: language), arguments: arguments)
    }

    static func articleCount(_ count: Int, language: ArticleContentLanguage, bundle: Bundle = .main) -> String {
        format(count == 1 ? "%lld artikel" : "%lld artikler", language: language,
               arguments: [count], bundle: bundle)
    }

    /// A compound taxonomy label can contain more than one CMS-owned category.
    /// Each display key is localized independently; unknown editorial labels are
    /// preserved rather than guessed or written back to the source model.
    static func taxonomy(_ label: String, language: ArticleContentLanguage,
                         bundle: Bundle = .main) -> String {
        for separator in [" | ", " • ", " · "] where label.contains(separator) {
            return label.components(separatedBy: separator).map {
                taxonomy($0, language: language, bundle: bundle)
            }.joined(separator: separator)
        }
        return string(label, language: language, bundle: bundle)
    }

}
