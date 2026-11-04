import SwiftUI
import SDWebImageSwiftUI
import Shimmer

struct FavoritesView: View {
    @EnvironmentObject var viewModel: ArticleViewModel
    @ObservedObject private var favoritesModel = FavoritesRuntime.model
    @ObservedObject private var canonical = AuthService.shared.state
    @Environment(\.navigationCoordinator) private var navigationCoordinator

    typealias SortOption = FavoriteArticlesLogic.SortOption
    @AppStorage(FavoriteArticlesLogic.sortPreferenceKey) private var selectedSortRaw = SortOption.recentlySaved.rawValue
    private var selectedSort: SortOption { FavoriteArticlesLogic.sortPreference(rawValue: selectedSortRaw) }
    private var sortBinding: Binding<SortOption> {
        Binding(get: { selectedSort }, set: { selectedSortRaw = $0.rawValue })
    }
    @State private var selectedCategory: String = "Alle"
    @State private var showSettings: Bool = false

    // Computed properties for filtering and sorting
    private var enrichedFavorites: [Article] {
        viewModel.favorites.filter(viewModel.isVisibleArticle).map { favorite in
            (viewModel.articles.first(where: { $0.id == favorite.id }) ?? favorite)
                .withFavoriteSavedAt(favorite.favoriteSavedAt)
        }
    }

    private var availableCategories: [String] {
        let cats: [String] = enrichedFavorites
            .compactMap { article in
                viewModel.topics.first(where: { $0.id == article.topicID })?.name
            }
            .filter { !$0.isEmpty }
        return Array(Set(cats)).sorted()
    }

    private var sortedFavorites: [Article] {
        var favs = enrichedFavorites

        // Filter by category if not "Alle"
        if selectedCategory != "Alle" {
            favs = favs.filter { article in
                let topicName: String = viewModel.topics.first(where: { $0.id == article.topicID })?.name ?? ""
                return topicName == selectedCategory
            }
        }

        favs = FavoriteArticlesLogic.sorted(favs, by: selectedSort)

        return favs
    }

    var shimmerPlaceholder: some View {
        VStack(spacing: 0) {
            ForEach(0..<6, id: \.self) { _ in
                HStack(alignment: .top, spacing: 16) {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.gray.opacity(0.2))
                        .frame(width: 80, height: 80)

                    VStack(alignment: .leading, spacing: 6) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.gray.opacity(0.2))
                            .frame(width: 200, height: 16)

                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.gray.opacity(0.2))
                            .frame(width: 100, height: 12)

                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.gray.opacity(0.2))
                            .frame(width: 150, height: 14)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.vertical, 12)
                .padding(.horizontal, 16)
            }
        }
    }


    var body: some View {
        MinSidePages(model: NotificationInboxRuntime.model, onSettings: { showSettings = true }) {
            if canonical.snapshot.context == .guest || viewModel.accountSaveGate.request?.isModal == false {
                SavedArticleAccountEntry(gate: viewModel.accountSaveGate, inline: true)
            } else if canonical.snapshot.context == .unresolved {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                favoritesList
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $showSettings) {
            SettingsView()
                .environmentObject(viewModel)
        }
    }

    private var favoritesList: some View {
        List {
            Section {
                controls
            }
            .listRowInsets(EdgeInsets())
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)

            Section {
                FavoritesNotice(model: favoritesModel, deferPendingFeedback: true) { generation in
                    viewModel.retryFavorites(generation: generation)
                }
            }
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)

            if viewModel.isLoading {
                Section {
                    shimmerPlaceholder
                }
                .listRowInsets(EdgeInsets())
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
            } else if sortedFavorites.isEmpty {
                Section {
                    emptyState
                }
                .listRowInsets(EdgeInsets())
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
            } else {
                Section {
                    ForEach(sortedFavorites) { article in
                        Button {
                            navigationCoordinator.navigateToArticle(article, in: .favorites)
                        } label: {
                            FavoriteArticleRow(article: article)
                                .padding(.vertical, 4)
                        }
                        .buttonStyle(.plain)
                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                    }
                    .onDelete(perform: removeFavorites)
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .toolbar(.hidden, for: .navigationBar)
        .refreshable {
            await viewModel.refreshArticles()
        }
        .deferBriefFavoritesFeedback(model: favoritesModel)
    }

    private func removeFavorites(at offsets: IndexSet) {
        for index in offsets {
            let article = sortedFavorites[index]
            if viewModel.isFavorite(article) {
                viewModel.toggleFavorite(for: article)
            }
        }
    }

    private var controls: some View {
        FavoritesControls(selectedSort: sortBinding, selectedCategory: $selectedCategory,
            availableCategories: availableCategories, articleCount: sortedFavorites.count,
            onSearch: { navigationCoordinator.navigateToTab(.search) })
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "bookmark.slash")
                .font(.system(size: 48))
                .foregroundColor(.secondary)

            Text(LocalizedStringKey(favoritesModel.context == .unresolved ? "Afventer din konto" : "Ingen gemte artikler"))
                .font(.title2)
                .fontWeight(.medium)
                .foregroundColor(.primary)

            Text(LocalizedStringKey(favoritesModel.context == .unresolved ? "Dine gemte valg vises, når den aktive læser er afklaret." : "Gem artikler ved at trykke på plus-knappen"))
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.clear)
        .padding(.top, 100)
    }
}

/// The actual favorites controls, shared with the service-free native fixture.
/// Its bindings and action remain owned by FavoritesView.
struct FavoritesControls: View {
    @Environment(\.locale) private var locale
    @Binding var selectedSort: FavoritesView.SortOption
    @Binding var selectedCategory: String
    let availableCategories: [String]
    let articleCount: Int
    let onSearch: () -> Void
    #if DEBUG && targetEnvironment(simulator)
    var onFrame: ((String, CGRect) -> Void)? = nil
    #endif

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        FavoritesControlsLayout(accessibility: dynamicTypeSize.isAccessibilitySize) {
            sortMenu.layoutValue(key: FavoritesControlsPartKey.self, value: .sort)
            if !availableCategories.isEmpty {
                categoryMenu.layoutValue(key: FavoritesControlsPartKey.self, value: .category)
            }
            searchButton.layoutValue(key: FavoritesControlsPartKey.self, value: .search)
            articleCountLabel.layoutValue(key: FavoritesControlsPartKey.self, value: .count)

            // Pure labels own the ideal widths. No hidden Menu, action or
            // geometry observer participates in choosing the arrangement.
            sizingProxy {
                menuLabel(title: selectedSort.titleKey, icon: "arrow.up.arrow.down", name: "sort", measured: false)
                    .frame(minWidth: 134)
            }.layoutValue(key: FavoritesControlsPartKey.self, value: .sortSizing)
            if !availableCategories.isEmpty {
                sizingProxy {
                    menuLabel(title: selectedCategory, icon: "tag", name: "category", measured: false)
                        .frame(minWidth: 86)
                }.layoutValue(key: FavoritesControlsPartKey.self, value: .categorySizing)
            }
            sizingProxy { searchLabel }
                .layoutValue(key: FavoritesControlsPartKey.self, value: .searchSizing)
            sizingProxy { countContents }
                .layoutValue(key: FavoritesControlsPartKey.self, value: .countSizing)
        }
        .modifier(FavoritesControlsCandidateObservation(name: "single"))
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
        .modifier(FrameProbe(name: "container", onFrame: probe))
    }

    private var sortMenu: some View {
        Menu {
            ForEach(FavoritesView.SortOption.allCases) { option in
                Button(action: { selectedSort = option }) {
                    HStack {
                        Text(LocalizedStringKey(option.titleKey))
                        if selectedSort == option {
                            Spacer()
                            Image(systemName: "checkmark")
                        }
                    }
                }
                .accessibilityIdentifier("favorites.controls.sort.option." + option.rawValue)
            }
        } label: {
            menuLabel(title: selectedSort.titleKey, icon: "arrow.up.arrow.down", name: "sort", measured: true)
        }
        .accessibilityLabel("Sortering")
        .accessibilityValue(LocalizedStringKey(selectedSort.titleKey))
        .accessibilityIdentifier("favorites.controls.sort")
        .modifier(FrameProbe(name: "sort", onFrame: probe))
    }

    private var categoryMenu: some View {
        Menu {
            Button("Alle") { selectedCategory = "Alle" }
                .accessibilityIdentifier("favorites.controls.category.option.Alle")
            Divider()
            ForEach(availableCategories, id: \.self) { category in
                Button { selectedCategory = category } label: { LocalizedArticleTaxonomy(category) }
                    .accessibilityIdentifier("favorites.controls.category.option." + category)
            }
        } label: {
            menuLabel(title: selectedCategory, icon: "tag", name: "category", measured: true)
        }
        .accessibilityLabel("Emne")
        .accessibilityValue(LocalizedStringKey(selectedCategory))
        .accessibilityIdentifier("favorites.controls.category")
        .modifier(FrameProbe(name: "category", onFrame: probe))
    }

    private func menuLabel(title: String, icon: String, name: String, measured enabled: Bool) -> some View {
        measured(name + ".pill", enabled: enabled) {
            HStack(spacing: 8) {
                Image(systemName: icon).font(.caption).fixedSize()
                measured(name + ".text", enabled: enabled) {
                    Text(LocalizedStringKey(title)).font(.subheadline)
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
                        .minimumScaleFactor(dynamicTypeSize.isAccessibilitySize ? 1 : 0.75)
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.leading)
                }
                Image(systemName: "chevron.down").font(.caption2).fixedSize()
            }
            .foregroundColor(.primary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            // The layout allocates the 134/86pt minimum slots. Keeping this
            // label shrinkable lets an even narrower window wrap its text.
            .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
            .background(Color.gray.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .frame(minHeight: 44)
        .contentShape(Rectangle())
    }

    private var searchLabel: some View {
        Image(systemName: "magnifyingglass")
            .foregroundColor(.primary)
            .padding(8)
            .background(Color.gray.opacity(0.1))
            .clipShape(Circle())
            .frame(minWidth: 44, minHeight: 44)
            .contentShape(Rectangle())
    }
    private var searchButton: some View {
        Button(action: onSearch) { searchLabel }
            .accessibilityLabel("Søg i artikler")
            .accessibilityIdentifier("favorites.controls.search")
            .modifier(FrameProbe(name: "search", onFrame: probe))
    }

    private var countContents: some View {
        ZStack(alignment: .trailing) {
            Text("999 artikler").hidden().accessibilityHidden(true)
            Text(AppLocalization.articleCount(articleCount, language: AppLocalization.language(for: locale)))
        }
        .font(.caption).monospacedDigit()
        .foregroundColor(.secondary)
        .lineLimit(1)
        .fixedSize(horizontal: true, vertical: false)
    }
    private var articleCountLabel: some View {
        countContents.modifier(FrameProbe(name: "count", onFrame: probe))
    }
    private func sizingProxy<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content().fixedSize(horizontal: true, vertical: true)
            .hidden().accessibilityHidden(true).allowsHitTesting(false)
    }

    private var probe: ((String, CGRect) -> Void)? {
        #if DEBUG && targetEnvironment(simulator)
        onFrame
        #else
        nil
        #endif
    }
    private struct FrameProbe: ViewModifier {
        let name: String
        let onFrame: ((String, CGRect) -> Void)?
        #if DEBUG && targetEnvironment(simulator)
        @Environment(\.favoritesControlsCandidateName) private var candidateName
        @Environment(\.favoritesControlsCandidateFrameProbe) private var candidateFrameProbe
        #endif
        @ViewBuilder func body(content: Content) -> some View {
            #if DEBUG && targetEnvironment(simulator)
            content.onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: {
                onFrame?(name, $0)
                candidateFrameProbe?(candidateName, name, $0)
            }
            #else
            content
            #endif
        }
    }
    @ViewBuilder private func measured<Content: View>(_ name: String, enabled: Bool = true,
                                                       @ViewBuilder content: () -> Content) -> some View {
        if enabled { content().modifier(FrameProbe(name: name, onFrame: probe)) }
        else { content() }
    }
}

private enum FavoritesControlsPart: Hashable {
    case sort, category, search, count, sortSizing, categorySizing, searchSizing, countSizing
}
private struct FavoritesControlsPartKey: LayoutValueKey {
    static let defaultValue = FavoritesControlsPart.sortSizing
}

/// Each real control is placed exactly once. Only its pure label proxy is
/// queried for ideal width; real Menus receive a finite width for height/placement.
private struct FavoritesControlsLayout: Layout {
    let accessibility: Bool
    private let horizontalGap: CGFloat = 8
    private let verticalGap: CGFloat = 12
    private struct Plan {
        let size: CGSize
        let frames: [FavoritesControlsPart: CGRect]
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrangement(width: usableWidth(proposal.width), subviews: subviews).size
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let plan = arrangement(width: usableWidth(bounds.width), subviews: subviews)
        for view in subviews {
            if let frame = plan.frames[view[FavoritesControlsPartKey.self]] {
                view.place(at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
                           anchor: .topLeading, proposal: ProposedViewSize(width: frame.width, height: frame.height))
            } else {
                view.place(at: bounds.origin, anchor: .topLeading, proposal: .zero)
            }
        }
    }
    private func usableWidth(_ proposed: CGFloat?) -> CGFloat {
        guard let proposed, proposed.isFinite else { return 370 }
        return max(0, proposed)
    }
    private func arrangement(width: CGFloat, subviews: Subviews) -> Plan {
        guard width > 0 else { return Plan(size: .zero, frames: [:]) }
        func view(_ part: FavoritesControlsPart) -> LayoutSubview? {
            subviews.first { $0[FavoritesControlsPartKey.self] == part }
        }
        func ideal(_ proxy: FavoritesControlsPart, minimum: CGFloat) -> CGFloat {
            let measured = view(proxy)?.sizeThatFits(.unspecified).width ?? minimum
            return ceil(max(minimum, measured.isFinite ? measured : minimum))
        }
        func height(_ part: FavoritesControlsPart, _ width: CGFloat) -> CGFloat {
            let measured = view(part)?.sizeThatFits(ProposedViewSize(width: width, height: nil)).height ?? 0
            return ceil(max(0, measured.isFinite ? measured : 44))
        }
        let hasCategory = view(.category) != nil
        let sortWidth = ideal(.sortSizing, minimum: 134)
        let categoryWidth = hasCategory ? ideal(.categorySizing, minimum: 86) : 0
        let searchWidth = ideal(.searchSizing, minimum: 44)
        let countWidth = ideal(.countSizing, minimum: 0)
        var frames: [FavoritesControlsPart: CGRect] = [:]
        let minimumRow = 134 + (hasCategory ? 86 : 0) + searchWidth + countWidth + horizontalGap * (hasCategory ? 3 : 2)
        if !accessibility && minimumRow <= width {
            // Reserve search/count once. A different selected label may only
            // compress its pill, never choose another normal-text row.
            let pillSpace = width-searchWidth-countWidth-horizontalGap * (hasCategory ? 3 : 2)
            let actualSort = hasCategory ? min(max(134, pillSpace-categoryWidth), pillSpace-86) : pillSpace
            let actualCategory = hasCategory ? pillSpace-actualSort : 0
            let sortHeight = height(.sort, actualSort), categoryHeight = hasCategory ? height(.category, actualCategory) : 0
            let searchHeight = height(.search, searchWidth), countHeight = height(.count, countWidth)
            let rowHeight = max(sortHeight, categoryHeight, searchHeight, countHeight)
            frames[.sort] = CGRect(x: 0, y: (rowHeight-sortHeight)/2, width: actualSort, height: sortHeight)
            if hasCategory {
                frames[.category] = CGRect(x: actualSort+horizontalGap, y: (rowHeight-categoryHeight)/2,
                                           width: actualCategory, height: categoryHeight)
            }
            frames[.search] = CGRect(x: width-countWidth-horizontalGap-searchWidth, y: (rowHeight-searchHeight)/2,
                                     width: searchWidth, height: searchHeight)
            frames[.count] = CGRect(x: width-countWidth, y: (rowHeight-countHeight)/2, width: countWidth, height: countHeight)
            return Plan(size: CGSize(width: width, height: rowHeight), frames: frames)
        }

        var y: CGFloat = 0
        if !accessibility && hasCategory && width >= 134 + horizontalGap + 86 {
            let available = width-horizontalGap
            let proportional = available * sortWidth / (sortWidth+categoryWidth)
            let first = min(available-86, max(134, ceil(proportional)))
            let second = available-first
            let firstHeight = height(.sort, first), secondHeight = height(.category, second)
            frames[.sort] = CGRect(x: 0, y: 0, width: first, height: firstHeight)
            frames[.category] = CGRect(x: first+horizontalGap, y: 0, width: second, height: secondHeight)
            y = max(firstHeight, secondHeight)+verticalGap
        } else {
            let sortHeight = height(.sort, width)
            frames[.sort] = CGRect(x: 0, y: y, width: width, height: sortHeight)
            y += sortHeight+verticalGap
            if hasCategory {
                let categoryHeight = height(.category, width)
                frames[.category] = CGRect(x: 0, y: y, width: width, height: categoryHeight)
                y += categoryHeight+verticalGap
            }
        }
        if searchWidth+horizontalGap+countWidth <= width {
            let searchHeight = height(.search, searchWidth), countHeight = height(.count, countWidth)
            let rowHeight = max(searchHeight, countHeight)
            frames[.search] = CGRect(x: width-countWidth-horizontalGap-searchWidth, y: y+(rowHeight-searchHeight)/2,
                                     width: searchWidth, height: searchHeight)
            frames[.count] = CGRect(x: width-countWidth, y: y+(rowHeight-countHeight)/2, width: countWidth, height: countHeight)
            y += rowHeight
        } else {
            let search = min(width, searchWidth), count = min(width, countWidth)
            let searchHeight = height(.search, search), countHeight = height(.count, count)
            frames[.search] = CGRect(x: width-search, y: y, width: search, height: searchHeight)
            y += searchHeight+verticalGap
            frames[.count] = CGRect(x: width-count, y: y, width: count, height: countHeight)
            y += countHeight
        }
        return Plan(size: CGSize(width: width, height: y), frames: frames)
    }
}


private struct FavoritesControlsCandidateObservation: ViewModifier {
    let name: String
    #if DEBUG && targetEnvironment(simulator)
    @Environment(\.favoritesControlsCandidateProbe) private var probe
    #endif
    @ViewBuilder func body(content: Content) -> some View {
        #if DEBUG && targetEnvironment(simulator)
        content.environment(\.favoritesControlsCandidateName, name)
            .onAppear { probe?(name, true) }.onDisappear { probe?(name, false) }
        #else
        content
        #endif
    }
}
#if DEBUG && targetEnvironment(simulator)
private struct FavoritesControlsCandidateProbeKey: EnvironmentKey {
    static let defaultValue: ((String, Bool) -> Void)? = nil
}
private struct FavoritesControlsCandidateNameKey: EnvironmentKey {
    static let defaultValue = ""
}
private struct FavoritesControlsCandidateFrameProbeKey: EnvironmentKey {
    static let defaultValue: ((String, String, CGRect) -> Void)? = nil
}
extension EnvironmentValues {
    fileprivate var favoritesControlsCandidateName: String {
        get { self[FavoritesControlsCandidateNameKey.self] }
        set { self[FavoritesControlsCandidateNameKey.self] = newValue }
    }
    var favoritesControlsCandidateFrameProbe: ((String, String, CGRect) -> Void)? {
        get { self[FavoritesControlsCandidateFrameProbeKey.self] }
        set { self[FavoritesControlsCandidateFrameProbeKey.self] = newValue }
    }
    var favoritesControlsCandidateProbe: ((String, Bool) -> Void)? {
        get { self[FavoritesControlsCandidateProbeKey.self] }
        set { self[FavoritesControlsCandidateProbeKey.self] = newValue }
    }
}
#endif

// MARK: - Favorite Article Row Component
struct FavoriteArticleRow: View {
    var article: Article
    @EnvironmentObject var viewModel: ArticleViewModel
    @Environment(\.colorScheme) private var colorScheme
    #if DEBUG && targetEnvironment(simulator)
    var fixtureImageCache: OfflineArticleImageCache? = nil
    var onImageEvent: ((PreparedArticleImage.Event) -> Void)? = nil
    var onFrame: ((String, CGRect) -> Void)? = nil
    #endif

    var body: some View {
        // Text owns the height; asynchronous image preparation cannot resize it.
        LeadingArticleArtwork(width: 80, spacing: 16, cornerRadius: 8) { _ in
            preparedImage
        } content: {
            measured("content") {
                VStack(alignment: .leading, spacing: 6) {
                    measured("title") {
                        Text(article.name ?? "")
                            .font(.headline)
                            .foregroundColor(.primary)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                    }
                    if let rating = article.stjerne, rating > 0 {
                        measured("rating") {
                            HStack(spacing: 3) {
                                ForEach(0..<6, id: \.self) { index in
                                    Image(systemName: "star.fill")
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundStyle(index < min(rating, 6)
                                            ? (colorScheme == .dark ? Color.white : Color.black.opacity(0.92))
                                            : (colorScheme == .dark ? Color.white.opacity(0.24) : Color.black.opacity(0.14)))
                                }
                            }
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel("\(min(rating, 6)) ud af 6 stjerner")
                            .accessibilityIdentifier("article.favorite.rating." + article.id)
                        }
                    }
                    if let topicName = viewModel.topics.first(where: { $0.id == article.topicID })?.name,
                       !topicName.isEmpty {
                        measured("category") {
                            LocalizedArticleTaxonomy(topicName)
                                .font(.caption)
                                .textCase(.uppercase)
                                .foregroundColor(.secondary)
                                .tracking(0.5)
                        }
                    }
                    if let intro = article.intro, !intro.isEmpty {
                        measured("intro") {
                            Text(intro)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
#if DEBUG && targetEnvironment(simulator)
        .observingArtworkFrame { onFrame?("image", $0) }
#endif
        .background(Color.clear)
    }

    @ViewBuilder private var preparedImage: some View {
        #if DEBUG && targetEnvironment(simulator)
        PreparedArticleImage(articleID: article.id, revision: article.bodyRevision,
            remoteURL: article.listThumbnailURL, style: .favorite,
            cache: fixtureImageCache, event: onImageEvent)
        #else
        PreparedArticleImage(articleID: article.id, revision: article.bodyRevision,
            remoteURL: article.listThumbnailURL, style: .favorite)
        #endif
    }

    @ViewBuilder private func measured<Content: View>(_ name: String, @ViewBuilder content: () -> Content) -> some View {
        #if DEBUG && targetEnvironment(simulator)
        content().onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { onFrame?(name, $0) }
        #else
        content()
        #endif
    }
}

struct FavoritesView_Previews: PreviewProvider {
    static var previews: some View {
        let vm = ArticleViewModel()
        return FavoritesView()
            .environmentObject(vm)
    }
}

// VisualEffectBlur for iOS 15+ (replicates UIKit UIBlurEffect)
struct VisualEffectBlur: UIViewRepresentable {
    var blurStyle: UIBlurEffect.Style
    func makeUIView(context: Context) -> UIVisualEffectView {
        let view = UIVisualEffectView(effect: UIBlurEffect(style: blurStyle))
        return view
    }
    func updateUIView(_ uiView: UIVisualEffectView, context: Context) {
        uiView.effect = UIBlurEffect(style: blurStyle)
    }
}

