import SwiftUI

/// Shared by actual Settings and the service-free language flow.
struct ContentLanguageSection: View {
    @ObservedObject var preferences: PreferencesManager

    var body: some View {
        Section {
            Picker("Appens sprog", selection: Binding(
                get: { preferences.articleLanguage },
                set: { preferences.updateArticleLanguage($0) }
            )) {
                Text("Dansk").tag(ArticleContentLanguage.danish)
                Text("English").tag(ArticleContentLanguage.english)
            }
            .accessibilityIdentifier("settings.articleLanguage")
        } header: {
            Text("Sprog")
        } footer: {
            Text("Vælg appens sprog. Hele brugerfladen og artiklerne følger dit valg. Kun publicerede artikler på det valgte sprog vises.")
        }
    }
}
