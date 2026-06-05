import WidgetKit
import SwiftUI

struct LatestArticleEntry: TimelineEntry {
    let date: Date
    let articles: [WidgetArticle]
}

struct LatestArticleProvider: TimelineProvider {
    func placeholder(in context: Context) -> LatestArticleEntry {
        LatestArticleEntry(date: .now, articles: [])
    }

    func getSnapshot(in context: Context, completion: @escaping (LatestArticleEntry) -> Void) {
        completion(LatestArticleEntry(date: .now, articles: WidgetDataStore.loadLatestArticles()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<LatestArticleEntry>) -> Void) {
        let articles = WidgetDataStore.loadLatestArticles()
        let entry = LatestArticleEntry(date: .now, articles: articles)
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 30, to: .now) ?? .now.addingTimeInterval(1800)
        completion(Timeline(entries: [entry], policy: .after(nextUpdate)))
    }
}

struct LatestArticleWidget: Widget {
    let kind = "LatestArticleWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: LatestArticleProvider()) { entry in
            LatestArticleWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Seneste artikel")
        .description("Viser den seneste artikel fra Apropos Magazine.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct LatestArticleWidgetView: View {
    let entry: LatestArticleEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        if let article = entry.articles.first {
            Link(destination: articleDeepLink(for: article)) {
                content(for: article)
            }
        } else {
            placeholderContent
        }
    }

    @ViewBuilder
    private func content(for article: WidgetArticle) -> some View {
        switch family {
        case .systemMedium:
            HStack(spacing: 12) {
                cover(for: article)
                    .frame(width: 110, height: 110)
                VStack(alignment: .leading, spacing: 6) {
                    Text("Apropos Magazine")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(article.name)
                        .font(.headline)
                        .lineLimit(3)
                    Text(article.intro)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Spacer(minLength: 0)
            }
        default:
            ZStack(alignment: .bottomLeading) {
                cover(for: article)
                LinearGradient(colors: [.clear, .black.opacity(0.75)], startPoint: .center, endPoint: .bottom)
                Text(article.name)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white)
                    .lineLimit(3)
                    .padding(10)
            }
        }
    }

    @ViewBuilder
    private func cover(for article: WidgetArticle) -> some View {
        if let url = URL(string: article.thumbURL), !article.thumbURL.isEmpty {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().scaledToFill()
                default:
                    Color.gray.opacity(0.25)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 12))
        } else {
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.gray.opacity(0.25))
        }
    }

    private var placeholderContent: some View {
        VStack {
            Text("Apropos Magazine")
                .font(.headline)
            Text("Ingen artikler endnu")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func articleDeepLink(for article: WidgetArticle) -> URL {
        URL(string: "aproposmagazine://article/\(article.id)")!
    }
}

struct AproposTodayWidget: Widget {
    let kind = "AproposTodayWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: LatestArticleProvider()) { entry in
            AproposTodayWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Apropos i dag")
        .description("Viser de seneste artikler.")
        .supportedFamilies([.systemMedium])
    }
}

struct AproposTodayWidgetView: View {
    let entry: LatestArticleEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Apropos i dag")
                .font(.headline)

            ForEach(entry.articles.prefix(3)) { article in
                Link(destination: URL(string: "aproposmagazine://article/\(article.id)")!) {
                    HStack(spacing: 10) {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.gray.opacity(0.2))
                            .frame(width: 42, height: 42)
                            .overlay {
                                if let url = URL(string: article.thumbURL), !article.thumbURL.isEmpty {
                                    AsyncImage(url: url) { phase in
                                        if case .success(let image) = phase {
                                            image.resizable().scaledToFill()
                                        }
                                    }
                                    .clipShape(RoundedRectangle(cornerRadius: 6))
                                }
                            }
                        Text(article.name)
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(2)
                            .foregroundStyle(.primary)
                        Spacer(minLength: 0)
                    }
                }
            }
        }
    }
}
