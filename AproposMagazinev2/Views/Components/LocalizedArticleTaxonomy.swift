import SwiftUI

/// Only taxonomy/section labels go through this view. Article headlines, body,
/// author names and stored notification messages remain editorial source data.
struct LocalizedArticleTaxonomy: View {
    let names: [String]
    var separator = " | "
    var uppercase = false
    @Environment(\.locale) private var locale

    init(_ name: String, uppercase: Bool = false) {
        self.names = [name]
        self.uppercase = uppercase
    }

    init(_ names: [String], separator: String = " | ", uppercase: Bool = false) {
        self.names = names
        self.separator = separator
        self.uppercase = uppercase
    }

    var body: some View {
        let language = AppLocalization.language(for: locale)
        let text = names.map {
            AppLocalization.taxonomy($0, language: language)
        }.joined(separator: separator)
        Text(verbatim: uppercase ? text.uppercased(with: locale) : text)
    }
}
