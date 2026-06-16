import SwiftUI
import WidgetKit

struct LatestArticleEntry: TimelineEntry {
    let date: Date
    let articles: [WidgetArticle]
    let isPlaceholder: Bool
}

struct LatestArticleProvider: TimelineProvider {
    func placeholder(in context: Context) -> LatestArticleEntry {
        makeEntry(includePreviewWhenEmpty: true, isPlaceholder: true)
    }

    func getSnapshot(in context: Context, completion: @escaping (LatestArticleEntry) -> Void) {
        completion(currentEntry(fallbackToPreview: context.isPreview))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<LatestArticleEntry>) -> Void) {
        let entry = currentEntry(fallbackToPreview: false)
        let articles = entry.articles.filter { !$0.id.hasPrefix("widget-preview") }
        let missingImages = articles.contains { !WidgetImageStore.hasCachedImage(for: $0.id) }
        let nextUpdate = missingImages
            ? Date().addingTimeInterval(300)
            : Date().addingTimeInterval(1800)

        completion(Timeline(entries: [entry], policy: .after(nextUpdate)))
    }

    private func currentEntry(fallbackToPreview: Bool) -> LatestArticleEntry {
        let articles = WidgetDataStore.loadLatestArticles()
        if !articles.isEmpty {
            return LatestArticleEntry(date: .now, articles: articles, isPlaceholder: false)
        }
        return makeEntry(includePreviewWhenEmpty: fallbackToPreview, isPlaceholder: true)
    }

    private func makeEntry(includePreviewWhenEmpty: Bool, isPlaceholder: Bool) -> LatestArticleEntry {
        let articles = WidgetDataStore.articlesForWidget(includePreviewWhenEmpty: includePreviewWhenEmpty)
        return LatestArticleEntry(
            date: .now,
            articles: articles,
            isPlaceholder: isPlaceholder && WidgetDataStore.loadLatestArticles().isEmpty
        )
    }
}

struct LatestArticleWidget: Widget {
    let kind = "LatestArticleWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: LatestArticleProvider()) { entry in
            LatestArticleWidgetContent(entry: entry)
                .widgetURL(deepLinkURL(for: entry))
                .containerBackground(for: .widget) {
                    LatestArticleWidgetBackground(entry: entry)
                }
        }
        .configurationDisplayName("Seneste artikel")
        .description("Viser den seneste artikel fra Apropos Magazine.")
        .supportedFamilies([.systemSmall, .systemMedium])
        .contentMarginsDisabled()
    }
}

struct AproposTodayWidget: Widget {
    let kind = "AproposTodayWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: LatestArticleProvider()) { entry in
            AproposTodayWidgetContent(entry: entry)
                .containerBackground(for: .widget) {
                    Color(red: 0.97, green: 0.97, blue: 0.98)
                }
        }
        .configurationDisplayName("Apropos i dag")
        .description("Viser dagens artikler fra Apropos Magazine.")
        .supportedFamilies([.systemMedium, .systemLarge])
        .contentMarginsDisabled()
    }
}

// MARK: - Latest article (small / medium)

private struct LatestArticleWidgetContent: View {
    @Environment(\.widgetFamily) private var family
    let entry: LatestArticleEntry

    private var article: WidgetArticle {
        entry.articles.first ?? WidgetArticle.galleryPreview
    }

    private var showsPlaceholder: Bool {
        entry.articles.isEmpty
    }

    var body: some View {
        if showsPlaceholder {
            WidgetPlaceholderContent(title: "Seneste artikel")
        } else {
            WidgetArticleCardView(
                article: article,
                isMedium: family == .systemMedium
            )
        }
    }
}

private struct LatestArticleWidgetBackground: View {
    let entry: LatestArticleEntry

    private var article: WidgetArticle? {
        entry.articles.first
    }

    var body: some View {
        if entry.articles.isEmpty {
            WidgetPlaceholderBackground()
        } else if let article, let uiImage = WidgetImageStore.uiImage(for: article) {
            Image(uiImage: uiImage)
                .resizable()
                .scaledToFill()
                .overlay(Color.black.opacity(0.38))
        } else if let article, let url = remoteImageURL(for: article) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()
                        .overlay(Color.black.opacity(0.38))
                default:
                    WidgetArticleBackgroundFill(article: article)
                }
            }
        } else if let article {
            WidgetArticleBackgroundFill(article: article)
        } else {
            Color(red: 0.14, green: 0.14, blue: 0.16)
        }
    }

    private func remoteImageURL(for article: WidgetArticle) -> URL? {
        let value = article.thumbURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }
        return URL(string: value)
    }
}

// MARK: - Today list (medium / large)

private struct AproposTodayWidgetContent: View {
    @Environment(\.widgetFamily) private var family
    let entry: LatestArticleEntry

    private var articleLimit: Int {
        family == .systemLarge ? 5 : 3
    }

    private var showsPlaceholder: Bool {
        entry.articles.isEmpty
    }

    var body: some View {
        if showsPlaceholder {
            WidgetPlaceholderContent(title: "Apropos i dag")
        } else {
            VStack(alignment: .leading, spacing: family == .systemLarge ? 14 : 10) {
                Text("Apropos i dag")
                    .font(.system(size: family == .systemLarge ? 17 : 15, weight: .bold))
                    .foregroundStyle(Color(red: 0.1, green: 0.1, blue: 0.12))

                ForEach(entry.articles.prefix(articleLimit)) { article in
                    Link(destination: articleDeepLink(for: article)) {
                        WidgetTodayArticleRow(
                            article: article,
                            thumbnailSize: family == .systemLarge ? 68 : 56
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(family == .systemLarge ? 18 : 16)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private func articleDeepLink(for article: WidgetArticle) -> URL {
        URL(string: "aproposmagazine://article/\(article.id)")!
    }
}

// MARK: - Shared widget building blocks

struct WidgetArticleBackgroundFill: View {
    let article: WidgetArticle

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.22, green: 0.22, blue: 0.24), Color.black],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            if let uiImage = WidgetImageStore.uiImage(for: article) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
                    .overlay(Color.black.opacity(0.35))
            } else if let url = remoteImageURL {
                AsyncImage(url: url) { phase in
                    if case .success(let image) = phase {
                        image
                            .resizable()
                            .scaledToFill()
                            .overlay(Color.black.opacity(0.35))
                    }
                }
            }
        }
    }

    private var remoteImageURL: URL? {
        let value = article.thumbURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }
        return URL(string: value)
    }
}

struct WidgetPlaceholderBackground: View {
    var body: some View {
        Color(red: 0.93, green: 0.93, blue: 0.95)
    }
}

struct WidgetPlaceholderContent: View {
    let title: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(Color(red: 0.1, green: 0.1, blue: 0.12))

            if WidgetDataStore.isAppGroupAvailable {
                Text("Åbn appen for at hente artikler")
                    .font(.system(size: 13))
                    .foregroundStyle(Color(red: 0.35, green: 0.35, blue: 0.38))
            } else {
                Text("App Group mangler — tjek signing")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.red.opacity(0.85))
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

private func deepLinkURL(for entry: LatestArticleEntry) -> URL {
    if entry.articles.isEmpty {
        return URL(string: "aproposmagazine://home")!
    }
    let article = entry.articles.first ?? WidgetArticle.galleryPreview
    return URL(string: "aproposmagazine://article/\(article.id)")!
}

// MARK: - Previews

private let previewArticles: [WidgetArticle] = [
    WidgetArticle.galleryPreview,
    WidgetArticle(
        id: "preview-2",
        name: "En anden artikel fra Apropos",
        slug: "preview-2",
        thumbURL: "",
        intro: "",
        date: "",
        stjerne: 3,
        topic: "Musik"
    ),
]

#Preview(as: .systemSmall) {
    LatestArticleWidget()
} timeline: {
    LatestArticleEntry(date: .now, articles: [WidgetArticle.galleryPreview], isPlaceholder: false)
}

#Preview(as: .systemMedium) {
    LatestArticleWidget()
} timeline: {
    LatestArticleEntry(date: .now, articles: [WidgetArticle.galleryPreview], isPlaceholder: false)
}

#Preview(as: .systemMedium) {
    AproposTodayWidget()
} timeline: {
    LatestArticleEntry(date: .now, articles: previewArticles, isPlaceholder: false)
}
