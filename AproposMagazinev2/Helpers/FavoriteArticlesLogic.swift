import CoreFoundation
import Foundation

enum FavoriteArticlesLogic {
    static func isFavorite(articleId: String, in favorites: [Article]) -> Bool {
        guard !articleId.isEmpty else { return false }
        return favorites.contains(where: { $0.id == articleId })
    }

    static func toggledFavorites(for article: Article, current favorites: [Article]) -> [Article] {
        guard let name = article.name, !name.isEmpty, !article.id.isEmpty else {
            return favorites
        }

        if isFavorite(articleId: article.id, in: favorites) {
            return favorites.filter { $0.id != article.id }
        }

        var updated = favorites
        updated.append(article)
        return updated
    }

    enum SortOption: String, CaseIterable, Identifiable {
        case recentlySaved = "Senest gemt"
        case titleAZ = "Titel A-Å"
        case titleZA = "Titel Å-A"
        case ratingHigh = "Bedst bedømt"
        case ratingLow = "Lavest bedømt"
        // Keep stored/raw identities while making the visible meaning explicit.
        case newest = "Nyeste først"
        case oldest = "Ældste først"
        var id: String { rawValue }
        var titleKey: String {
            switch self {
            case .newest: return "Nyeste udgivelser"
            case .oldest: return "Ældste udgivelser"
            default: return rawValue
            }
        }
    }
    static let sortPreferenceKey = "favorites.sortOption.v1"
    static func sortPreference(rawValue: String?) -> SortOption {
        rawValue.flatMap(SortOption.init(rawValue:)) ?? .recentlySaved
    }
    static func validSavedAt(_ value: TimeInterval) -> Bool {
        value.isFinite && value >= 0 && value <= 253_402_300_799
    }
    static func decodedSavedAt(_ raw: Any?) -> TimeInterval? {
        guard let number = raw as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(),
              validSavedAt(number.doubleValue) else { return nil }
        return number.doubleValue
    }
    static func sorted(_ articles: [Article], by option: SortOption) -> [Article] {
        articles.sorted { lhs, rhs in
            switch option {
            case .recentlySaved:
                let left = lhs.favoriteSavedAt.flatMap { validSavedAt($0) ? $0 : nil }
                let right = rhs.favoriteSavedAt.flatMap { validSavedAt($0) ? $0 : nil }
                if let left, let right, left != right { return left > right }
                if (left != nil) != (right != nil) { return left != nil }
                // Unknown historical save times remain unknown, with a stable
                // tie-breaker. IDs are never interpreted as dates.
            case .titleAZ, .titleZA:
                let order = (lhs.name ?? "").localizedCaseInsensitiveCompare(rhs.name ?? "")
                if order != .orderedSame { return option == .titleAZ ? order == .orderedAscending : order == .orderedDescending }
            case .ratingHigh, .ratingLow:
                if lhs.rating != rhs.rating { return option == .ratingHigh ? lhs.rating > rhs.rating : lhs.rating < rhs.rating }
            case .newest, .oldest:
                if lhs.feedSortDate != rhs.feedSortDate { return option == .newest ? lhs.feedSortDate > rhs.feedSortDate : lhs.feedSortDate < rhs.feedSortDate }
            }
            return lhs.id < rhs.id
        }
    }

}
