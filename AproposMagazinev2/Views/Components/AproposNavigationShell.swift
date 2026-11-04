import SwiftUI
import UIKit

/// Shared app chrome only. The caller retains every route, page, player and
/// service. iPad keeps this same split-view identity at every window width.
struct AproposNavigationShell<Pages: View, Accessory: View>: View {
    @Binding private var selection: Tab
    private let hasActiveEpisode: Bool
    private let hasPreparation: Bool
    private let favoritesUnreadCount: Int
    private let onTabReselected: (Tab) -> Void
    private let pages: Pages
    private let accessory: Accessory
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    #if DEBUG && targetEnvironment(simulator)
    @Environment(\.aproposNavigationDetailProbe) private var detailProbe
    #endif
    @State private var columns: NavigationSplitViewVisibility = .all
    @State private var compactColumn: NavigationSplitViewColumn = .detail

    init(selection: Binding<Tab>, hasActiveEpisode: Bool, hasPreparation: Bool,
         favoritesUnreadCount: Int = 0,
         onTabReselected: @escaping (Tab) -> Void,
         @ViewBuilder pages: () -> Pages, @ViewBuilder accessory: () -> Accessory) {
        _selection = selection
        self.hasActiveEpisode = hasActiveEpisode
        self.hasPreparation = hasPreparation
        self.favoritesUnreadCount = favoritesUnreadCount
        self.onTabReselected = onTabReselected
        self.pages = pages()
        self.accessory = accessory()
    }

    private var isPad: Bool { UIDevice.current.userInterfaceIdiom == .pad }

    var body: some View {
        if isPad {
            NavigationSplitView(columnVisibility: $columns, preferredCompactColumn: $compactColumn) {
                sidebar
                    .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 320)
            } detail: {
                playerRegion
            }
            .navigationSplitViewStyle(.balanced)
        } else {
            playerRegion
        }
    }

    // Route taps through the actual SwiftUI selection binding, including a
    // same-value selection. Keep this identical for phone tabs and sidebar.
    private func select(_ tab: Tab) {
        if selection == tab { onTabReselected(tab) }
        else { selection = tab }
    }

    private var tabSelection: Binding<Tab> {
        Binding(get: { selection }, set: select)
    }

    private var sidebar: some View {
        List {
            Image(colorScheme == .dark ? "AproposLogoWhite" : "AproposLogoBlack")
                .resizable().scaledToFit().frame(maxWidth: 156).frame(height: 52)
                .padding(.vertical, 16)
                .accessibilityLabel("Apropos Magazine")
                .listRowBackground(Color.clear)
            ForEach(Tab.allCases) { tab in
                Button {
                    select(tab)
                    compactColumn = .detail
                } label: {
                    HStack(spacing: 8) {
                        Label(LocalizedStringKey(tab.rawValue), systemImage: tab.systemImage)
                        if tab == .favorites && favoritesUnreadCount > 0 {
                            Spacer(minLength: 0)
                            NotificationUnreadDot()
                        }
                    }
                        .font(.body.weight(selection == tab ? .semibold : .regular))
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .listRowBackground(selection == tab ? Color.primary.opacity(0.09) : Color.clear)
                .accessibilityAddTraits(selection == tab ? .isSelected : [])
                .accessibilityValue(tab == .favorites && favoritesUnreadCount > 0 ? Text("Ulæste meddelelser") : Text(""))
                .accessibilityIdentifier("ipad.navigation.\(tab.navigationIdentifier)")
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("Apropos")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("ipad.navigation.sidebar")
    }

    private var playerRegion: some View {
        GeometryReader { container in
            ZStack(alignment: .bottom) {
                TabView(selection: tabSelection) { pages }
                    .toolbar(isPad ? .hidden : .automatic, for: .tabBar)
                    .modifier(PodcastMiniPlayerReservation(isVisible: hasActiveEpisode || hasPreparation))

                accessory.modifier(PodcastMiniPlayerPlacement())
            }
            .environment(\.podcastMiniPlayerBottomOffset, isPad ? 20 : PodcastMiniPlayerLayout.bottomOffset)
            .environment(\.podcastMiniPlayerMaximumWidth, isPad ? 760 : .infinity)
            .environment(\.podcastMiniPlayerTopEdge, hasActiveEpisode
                ? PodcastMiniPlayerLayout.topEdge(containerBottom: container.size.height,
                    for: dynamicTypeSize, bottomOffset: isPad ? 20 : PodcastMiniPlayerLayout.bottomOffset)
                : nil)
        }
        #if DEBUG && targetEnvironment(simulator)
        .onGeometryChange(for: AproposNavigationDetailGeometry.self) {
            .init(frame: $0.frame(in: .global), size: $0.size, safeAreaInsets: $0.safeAreaInsets)
        } action: { detailProbe?($0) }
        #endif
    }
}

#if DEBUG && targetEnvironment(simulator)
/// Read-only native geometry evidence. This callback cannot alter product
/// layout, selection, playback, persistence or service authority.
struct AproposNavigationDetailGeometry: Equatable {
    var frame: CGRect = .zero
    var size: CGSize = .zero
    var safeAreaInsets = EdgeInsets()
}
private struct AproposNavigationDetailProbeKey: EnvironmentKey {
    static let defaultValue: ((AproposNavigationDetailGeometry) -> Void)? = nil
}
extension EnvironmentValues {
    var aproposNavigationDetailProbe: ((AproposNavigationDetailGeometry) -> Void)? {
        get { self[AproposNavigationDetailProbeKey.self] }
        set { self[AproposNavigationDetailProbeKey.self] = newValue }
    }
}
#endif

extension Tab {
    var navigationIdentifier: String {
        switch self {
        case .home: "home"
        case .search: "search"
        case .categories: "categories"
        case .favorites: "favorites"
        }
    }
}
