import SwiftUI

/// Observes the catalog itself: an asynchronous manifest publication must reveal
/// the button even when the article and playback progress have not changed.
/// Dependencies are injected so the same control can run without services.
@MainActor
struct ArticleListenSection<Catalog: ObservableObject>: View {
    @ObservedObject var catalog: Catalog
    let selection: (Catalog) -> PodcastEpisode?
    let title: (PodcastEpisode) -> String
    let play: (PodcastEpisode) -> Void
    var isEnabled: (PodcastEpisode) -> Bool = { _ in true }
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        if let episode = selection(catalog) {
            HStack {
                Spacer(minLength: 0)
                Button {
                    ArticleListenAction.perform(offered: episode,
                        resolve: { selection(catalog) }, isEnabled: { isEnabled(episode) }, play: play)
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "headphones")
                            .font(.caption.weight(.semibold))
                        Text(LocalizedStringKey(title(episode)))
                            .font(.caption.weight(.semibold))
                            .textCase(.uppercase)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .foregroundStyle(.white)
                    .frame(minHeight: 28)
                    .padding(.horizontal, 12)
                    .background(Color(hex: "#262626"), in: RoundedRectangle(cornerRadius: 10))
                    .overlay {
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color.white.opacity(0.18), lineWidth: 0.6)
                    }
                    .shadow(color: .black.opacity(colorScheme == .dark ? 0.3 : 0.15), radius: 6, x: 0, y: 3)
                    // Keep the compact visual pill inside a full-height tap area.
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(!isEnabled(episode))
                .opacity(isEnabled(episode) ? 1 : 0.65)
                .accessibilityHint(LocalizedStringKey(isEnabled(episode) ? "" : "Gå online for at afspille lyden."))
                .accessibilityIdentifier("reader.listen")
                Spacer(minLength: 0)
            }
            .padding(.top, 2)
        }
    }
}

/// The reader and local layout probe share these actual stack children. A
/// visible listen button uses only the parent's 16-point gap before the hero.
/// Without a recording, keep the reader's previous spacer and hero rendering.
@MainActor
struct ArticleListenHeroSection<Catalog: ObservableObject, Hero: View>: View {
    @ObservedObject var catalog: Catalog
    let selection: (Catalog) -> PodcastEpisode?
    let title: (PodcastEpisode) -> String
    let play: (PodcastEpisode) -> Void
    let isEnabled: (PodcastEpisode) -> Bool
    private let hero: Hero

    init(catalog: Catalog, selection: @escaping (Catalog) -> PodcastEpisode?,
         title: @escaping (PodcastEpisode) -> String, play: @escaping (PodcastEpisode) -> Void,
         isEnabled: @escaping (PodcastEpisode) -> Bool = { _ in true },
         @ViewBuilder hero: () -> Hero) {
        self.catalog = catalog
        self.selection = selection
        self.title = title
        self.play = play
        self.isEnabled = isEnabled
        self.hero = hero()
    }

    var body: some View {
        Group {
            ArticleListenSection(catalog: catalog, selection: selection, title: title,
                play: play, isEnabled: isEnabled)
            if selection(catalog) == nil { Spacer() }
            hero
        }
    }
}
