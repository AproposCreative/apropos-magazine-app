import Foundation

/// The widget reads only the language selected by the app's existing feed sync.
/// It neither changes that preference nor reads account or authentication data.
enum WidgetLocalization {
    static var languageCode: String { WidgetDataStore.interfaceLanguageCode }

    static func locale(for code: String) -> Locale {
        Locale(identifier: code == "en" ? "en_GB" : "da_DK")
    }

    static func string(_ key: String, languageCode: String, bundle: Bundle = .main) -> String {
        let code = languageCode == "en" ? "en" : "da"
        guard let path = bundle.path(forResource: code, ofType: "lproj"),
              let localized = Bundle(path: path) else { return key }
        // Shared formatter tests and app-side rendering use the app table;
        // the extension bundles its own smaller Widget table.
        let table = localized.url(forResource: "Widget", withExtension: "strings") != nil ? "Widget" : "Localizable"
        return localized.localizedString(forKey: key, value: key, table: table)
    }

    static func taxonomy(_ label: String, languageCode: String) -> String {
        for separator in [" | ", " • ", " · "] where label.contains(separator) {
            return label.components(separatedBy: separator).map {
                taxonomy($0, languageCode: languageCode)
            }.joined(separator: separator)
        }
        return string(label, languageCode: languageCode)
    }
}
