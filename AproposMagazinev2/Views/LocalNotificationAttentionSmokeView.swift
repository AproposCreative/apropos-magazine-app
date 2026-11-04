#if DEBUG && targetEnvironment(simulator)
import Combine
import FirebaseCore
import SwiftUI
import UIKit

private struct LocalNotificationAttentionRoute: Hashable {
    let articleID: String
}

@MainActor
private final class LocalNotificationAttentionFixture: ObservableObject {
    private final class Memory {
        var bytes: Data?
        var delivered: [NotificationInboxItem] = []
        var badgeValues: [Int] = []
        var opened: [String] = []
        var deliveredReads = 0
        var didOpen: ((NotificationInboxItem.Target) -> Bool)?
    }

    @Published private(set) var model: NotificationInboxModel
    @Published var language: ArticleContentLanguage
    @Published var selection: Tab = .home
    @Published var path: [LocalNotificationAttentionRoute] = []
    @Published private(set) var coldReloads = 0
    private let memory: Memory
    private let effects: NotificationInboxModel.Effects

    init() {
        let memory = Memory()
        self.memory = memory
        let effects = NotificationInboxModel.Effects(load: { memory.bytes }, save: { memory.bytes = $0 },
            delivered: { done in memory.deliveredReads += 1; done(memory.delivered) },
            removeDelivered: { ids in
                memory.delivered.removeAll { ids.contains($0.id) || ids.contains($0.inboxIdentity) }
            }, clearBadge: { done in done(true) },
            open: { target in
                memory.opened.append(target.identifier)
                return memory.didOpen?(target) ?? false
            }, setBadge: { count, done in memory.badgeValues.append(count); done(true) })
        self.effects = effects
        model = NotificationInboxModel(effects: effects)
        language = ProcessInfo.processInfo.arguments.contains("-AproposNotificationAttentionEnglishSmoke") ? .english : .danish
        memory.didOpen = { [weak self] target in
            guard let self else { return false }
            self.path.append(.init(articleID: target.identifier))
            return true
        }
    }

    static func articleID(language: ArticleContentLanguage, second: Bool = false) -> String {
        let id = second ? "89abcdef0123456789abcdef" : "0123456789abcdef01234567"
        return language == .english ? "en_" + id : id
    }

    func receive(second: Bool = false, otherLanguage: Bool = false) {
        let targetLanguage: ArticleContentLanguage = otherLanguage ? (language == .danish ? .english : .danish) : language
        let id = Self.articleID(language: targetLanguage, second: second)
        guard let item = NotificationInboxItem.make(id: "local-attention-" + id,
            title: targetLanguage == .danish ? "En ny dansk artikel" : "A new English article",
            body: targetLanguage == .danish ? "Åbn artiklen." : "Open the article.",
            date: Date(timeIntervalSince1970: second ? 1_800_000_100 : 1_800_000_000),
            userInfo: ["type": "new_article", "article_id": id, "article_slug": "local-attention-article"]) else { return }
        memory.delivered.removeAll { $0.inboxIdentity == item.inboxIdentity }
        memory.delivered.append(item)
        // Same actual inbox admission as a delivered push, never a badge setter.
        model.receive(item)
    }

    func changeLanguage() { language = language == .danish ? .english : .danish }
    func coldReload() { model = NotificationInboxModel(effects: effects); coldReloads += 1 }

    func report() -> String {
        let unread = NotificationTabBadge.unreadCount(in: model, language: language)
        let value: [String: Any] = [
            "selectedLanguage": language.rawValue, "selectedTab": selection.rawValue,
            "visibleUnreadCount": unread, "allUnreadCount": model.unreadCount,
            "requestedNativeBadge": unread > 0 ? "empty-string" : "nil",
            "nativeBadgePixelsAreSeparatelyTested": true,
            "modelID": String(describing: ObjectIdentifier(model)),
            "items": model.items.map { ["id": $0.id, "isRead": $0.isRead,
                "language": $0.articlePublicationLanguage?.rawValue ?? "unclassified"] as [String: Any] },
            "openedIDs": memory.opened, "path": path.map(\.articleID),
            "coldReloads": coldReloads, "deliveredReads": memory.deliveredReads,
            "localBadgeSpyValues": memory.badgeValues, "OSBadgeWasSet": false,
            "firebaseStarted": FirebaseApp.allApps != nil,
            "normalNotificationRuntimeUsed": false, "normalPlayerStarted": false,
            "actualShell": true, "actualInboxAndMinSidePages": true,
            "systemAccessibility": UIApplication.shared.preferredContentSizeCategory.isAccessibilityCategory
        ]
        guard let bytes = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]),
              let text = String(data: bytes, encoding: .utf8) else { return "{}" }
        return text
    }
}

/// One actual shell and the production inbox, backed solely by local effects.
/// Destinations are typed local receipts, not the reader, account or player.
@MainActor
struct LocalNotificationAttentionSmokeView: View {
    @StateObject private var fixture = LocalNotificationAttentionFixture()
    var body: some View {
        LocalNotificationAttentionContent(fixture: fixture, model: fixture.model)
            .environment(\.locale, AppLocalization.locale(for: fixture.language))
    }
}

@MainActor
private struct LocalNotificationAttentionContent: View {
    @ObservedObject var fixture: LocalNotificationAttentionFixture
    @ObservedObject var model: NotificationInboxModel
    private var unreadCount: Int { NotificationTabBadge.unreadCount(in: model, language: fixture.language) }

    var body: some View {
        AproposNavigationShell(selection: $fixture.selection, hasActiveEpisode: false, hasPreparation: false,
            favoritesUnreadCount: unreadCount, onTabReselected: { tab in
                if tab == .favorites { fixture.path.removeAll() }
            }) {
            Text("Lokal Hjem").tabItem { Label("Hjem", systemImage: "house.fill") }.tag(Tab.home)
            Text("Lokale artikler").tabItem { Label("Artikler", systemImage: "doc.text") }.tag(Tab.search)
            Text("Lokale kategorier").tabItem { Label("Kategorier", systemImage: "square.grid.2x2.fill") }.tag(Tab.categories)
            NavigationStack(path: $fixture.path) {
                MinSidePages(model: model, onSettings: {}) {
                    List { Text("Lokalt gemt indhold").accessibilityIdentifier("attention.saved") }
                }
                .toolbar(.hidden, for: .navigationBar)
                .navigationDestination(for: LocalNotificationAttentionRoute.self) { route in
                    VStack(spacing: 16) {
                        Text(route.articleID).accessibilityIdentifier("attention.article")
                        Button("Tilbage") { fixture.path.removeAll() }
                            .frame(minHeight: 44).accessibilityIdentifier("attention.article.back")
                    }.padding(16)
                }
            }
            .tabItem { NotificationFavoritesTabLabel(unreadCount: unreadCount) }
            .modifier(NotificationTabBadge(unreadCount: unreadCount))
            .tag(Tab.favorites)
        } accessory: { EmptyView() }
        .accentColor(.primary)
        .safeAreaInset(edge: .top) {
            VStack(spacing: 4) {
                HStack {
                    Button("Modtag") { fixture.receive() }.accessibilityIdentifier("attention.receive")
                    Button("Ny besked") { fixture.receive(second: true) }.accessibilityIdentifier("attention.receive.second")
                    Button("Andet sprog") { fixture.receive(otherLanguage: true) }.accessibilityIdentifier("attention.receive.other")
                }
                HStack {
                    Button("DA / EN", action: fixture.changeLanguage).accessibilityIdentifier("attention.language")
                    Button("Genåbn", action: fixture.coldReload).accessibilityIdentifier("attention.cold")
                    Button("Hjem") { fixture.selection = .home }.accessibilityIdentifier("attention.home")
                }
            }
            .font(.caption).dynamicTypeSize(.large).buttonStyle(.bordered)
            .padding(6)
        }
        .overlay(alignment: .topLeading) {
            Text(fixture.report()).font(.system(size: 1)).lineLimit(1).frame(height: 1)
                .accessibilityIdentifier("attention.report").allowsHitTesting(false)
        }
    }
}
#endif
