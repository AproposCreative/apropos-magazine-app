import SwiftUI

/// Presentation only: the caller observes its existing inbox and language.
/// A present empty native badge requests a dot; nil removes it completely.
struct NotificationTabBadge: ViewModifier {
    let unreadCount: Int

    func body(content: Content) -> some View {
        content.badge(unreadCount > 0 ? "" : nil as String?)
    }

    @MainActor static func unreadCount(in model: NotificationInboxModel,
                                      language: ArticleContentLanguage) -> Int {
        model.visibleItems(language: language).filter { !$0.isRead }.count
    }
}

struct NotificationFavoritesTabLabel: View {
    let unreadCount: Int
    var body: some View {
        Label("Min side", systemImage: "person.crop.circle")
            .accessibilityValue(unreadCount > 0 ? Text("Ulæste meddelelser") : Text(""))
            .accessibilityIdentifier("notifications.navigation.favorites")
    }
}

/// The existing sidebar has a custom label, so it uses the same discreet color
/// without adding a control or accessibility focus stop.
struct NotificationUnreadDot: View {
    var body: some View {
        Circle().fill(Color.red).frame(width: 6, height: 6)
            .accessibilityHidden(true)
            .allowsHitTesting(false)
    }
}
