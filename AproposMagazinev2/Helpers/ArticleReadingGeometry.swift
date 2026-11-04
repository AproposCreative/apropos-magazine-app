import Foundation

/// Coordinates are relative to the prose body, not the entire page or related cards.
struct ArticleReadingGeometry: Equatable {
    var top: Double
    var bottom: Double
    var bodyHeight: Double

    var fraction: Double? {
        guard top.isFinite, bottom.isFinite, bodyHeight.isFinite,
              bottom > top, bodyHeight > 0 else { return nil }
        let viewportHeight = bottom - top
        guard viewportHeight.isFinite else { return nil }
        if bodyHeight <= viewportHeight {
            return bottom >= bodyHeight ? 1 : 0
        }
        return min(max(top / (bodyHeight - viewportHeight), 0), 1)
    }
}
