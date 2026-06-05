import Foundation

struct WidgetArticle: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let slug: String
    let thumbURL: String
    let intro: String
    let date: String
}

enum WidgetDataStore {
    static let appGroupID = "group.com.aproposmagazine.app"
    static let latestArticlesKey = "widget_latest_articles"

    static func saveLatestArticles(_ articles: [WidgetArticle]) {
        guard let defaults = UserDefaults(suiteName: appGroupID) else { return }
        let payload = Array(articles.prefix(5))
        guard let data = try? JSONEncoder().encode(payload) else { return }
        defaults.set(data, forKey: latestArticlesKey)
    }

    static func loadLatestArticles() -> [WidgetArticle] {
        guard let defaults = UserDefaults(suiteName: appGroupID),
              let data = defaults.data(forKey: latestArticlesKey),
              let articles = try? JSONDecoder().decode([WidgetArticle].self, from: data) else {
            return []
        }
        return articles
    }
}
