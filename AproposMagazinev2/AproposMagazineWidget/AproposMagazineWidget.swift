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

        // Refresh sooner right after install/first sync so the widget "comes to
        // life" quickly, then settle into a calm 30-minute cadence.
        let nextUpdate: Date
        if articles.isEmpty {
            nextUpdate = Date().addingTimeInterval(60)
        } else if missingImages {
            nextUpdate = Date().addingTimeInterval(120)
        } else {
            nextUpdate = Date().addingTimeInterval(1800)
        }

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
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
        .contentMarginsDisabled()
    }
}

struct AproposTodayWidget: Widget {
    let kind = "AproposTodayWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: LatestArticleProvider()) { entry in
            AproposTodayWidgetContent(entry: entry)
                .widgetURL(deepLinkURL(for: entry))
                .containerBackground(for: .widget) {
                    AproposTodayWidgetBackground(entry: entry)
                }
        }
        .configurationDisplayName("Apropos i dag")
        .description("Viser dagens artikler fra Apropos Magazine.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
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
        } else if let article {
            WidgetArticleBackgroundFill(article: article)
        } else {
            PremiumWidgetBackdrop()
        }
    }
}

// MARK: - Today list (medium / large)

private struct AproposTodayWidgetContent: View {
    @Environment(\.widgetFamily) private var family
    let entry: LatestArticleEntry

    private var articleLimit: Int {
        if family == .systemSmall { return 1 }
        return family == .systemLarge ? 5 : 3
    }

    private var showsPlaceholder: Bool {
        entry.articles.isEmpty
    }

    var body: some View {
        if showsPlaceholder {
            WidgetPlaceholderContent(title: "Apropos i dag")
        } else if family == .systemSmall {
            WidgetArticleCardView(
                article: entry.articles.first ?? WidgetArticle.galleryPreview,
                isMedium: false
            )
        } else {
            VStack(alignment: .leading, spacing: family == .systemLarge ? 14 : 10) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("APROPOS")
                            .font(.system(size: 9, weight: .semibold))
                            .tracking(0.8)
                            .foregroundStyle(.white.opacity(0.72))

                        Text("Apropos i dag")
                            .font(.system(size: family == .systemLarge ? 18 : 16, weight: .bold))
                            .foregroundStyle(.white)
                    }

                    Spacer(minLength: 8)

                    Text("\(min(entry.articles.count, articleLimit)) nye")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.86))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.white.opacity(0.14), in: Capsule())
                }

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
        widgetArticleDeepLink(for: article)
    }
}

// MARK: - Shared widget building blocks

struct WidgetArticleBackgroundFill: View {
    let article: WidgetArticle

    var body: some View {
        ZStack {
            PremiumWidgetBackdrop()

            if let uiImage = WidgetImageStore.uiImage(for: article) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
                    .overlay(WidgetImageOverlay())
            }
        }
    }
}

struct WidgetPlaceholderBackground: View {
    var body: some View {
        PremiumWidgetBackdrop()
    }
}

struct WidgetPlaceholderContent: View {
    let title: String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("APROPOS")
                .font(.system(size: 9, weight: .semibold))
                .tracking(0.8)
                .foregroundStyle(.white.opacity(0.72))

            Spacer(minLength: 8)

            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .minimumScaleFactor(0.82)

                if WidgetDataStore.isAppGroupAvailable {
                    Text("Åbn appen for at hente artikler")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white.opacity(0.82))
                } else {
                    Text("App Group mangler - tjek signing")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color(red: 1, green: 0.72, blue: 0.72))
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

private struct AproposTodayWidgetBackground: View {
    @Environment(\.widgetFamily) private var family
    let entry: LatestArticleEntry

    private var article: WidgetArticle? {
        entry.articles.first
    }

    var body: some View {
        // The small size shows a single hero card, so it keeps the photo background.
        // Medium/large show a multi-article list, which is far more readable on a
        // calm dark backdrop than layered on top of a full-bleed photo.
        if family == .systemSmall, let article, let uiImage = WidgetImageStore.uiImage(for: article) {
            Image(uiImage: uiImage)
                .resizable()
                .scaledToFill()
                .overlay(WidgetImageOverlay())
        } else {
            PremiumWidgetBackdrop()
        }
    }
}

private struct WidgetImageOverlay: View {
    var body: some View {
        ZStack {
            Color.black.opacity(0.32)
            LinearGradient(
                colors: [
                    Color.black.opacity(0.16),
                    Color.black.opacity(0.42),
                    Color.black.opacity(0.78)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }
}

private struct PremiumWidgetBackdrop: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.09, green: 0.09, blue: 0.10),
                    Color(red: 0.20, green: 0.19, blue: 0.18),
                    Color(red: 0.03, green: 0.03, blue: 0.04)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            VStack(spacing: 0) {
                Rectangle()
                    .fill(Color.white.opacity(0.08))
                    .frame(height: 1)
                Spacer()
                Rectangle()
                    .fill(Color.white.opacity(0.05))
                    .frame(height: 1)
            }
            .padding(.vertical, 22)

            HStack {
                Spacer()
                Text("A")
                    .font(.system(size: 118, weight: .black, design: .serif))
                    .foregroundStyle(Color.white.opacity(0.055))
                    .offset(x: 18, y: -8)
            }
        }
    }
}

private func deepLinkURL(for entry: LatestArticleEntry) -> URL {
    guard let article = entry.articles.first else {
        return URL(string: "aproposmagazine://home") ?? URL(string: "https://aproposmagazine.com")!
    }
    return widgetArticleDeepLink(for: article)
}

private func widgetArticleDeepLink(for article: WidgetArticle) -> URL {
    let identifier = article.slug.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        ? article.id
        : article.slug
    let encoded = identifier.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? article.id
    return URL(string: "aproposmagazine://article/\(encoded)")
        ?? URL(string: "https://aproposmagazine.com/article/\(encoded)")
        ?? URL(string: "https://aproposmagazine.com")!
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

#Preview(as: .systemLarge) {
    LatestArticleWidget()
} timeline: {
    LatestArticleEntry(date: .now, articles: WidgetArticle.galleryPreviewArticles, isPlaceholder: false)
}

#Preview(as: .systemSmall) {
    AproposTodayWidget()
} timeline: {
    LatestArticleEntry(date: .now, articles: previewArticles, isPlaceholder: false)
}

#Preview(as: .systemMedium) {
    AproposTodayWidget()
} timeline: {
    LatestArticleEntry(date: .now, articles: previewArticles, isPlaceholder: false)
}

#Preview(as: .systemLarge) {
    AproposTodayWidget()
} timeline: {
    LatestArticleEntry(date: .now, articles: previewArticles, isPlaceholder: false)
}
