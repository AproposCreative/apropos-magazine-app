import SDWebImageSwiftUI
import SwiftUI

/// Production dependencies live at this boundary; the feed below is shared
/// with the memory-only native fixture.
struct HomeView: View {
    @EnvironmentObject private var viewModel: ArticleViewModel
    @Environment(\.navigationCoordinator) private var navigationCoordinator
    var articleHeroNamespace: Namespace.ID? = nil

    var body: some View {
        HomeFeedContent(model: viewModel.homeFeedModel,
            progressStore: PodcastProgressRuntime.store,
            presentation: PodcastPlayerPresentationRuntime.model,
            favoriteIDs: Set(viewModel.favorites.map(\.id)),
            isLoading: viewModel.isLoading, errorMessage: viewModel.fetchError?.localizedDescription,
            actions: actions, articleHeroNamespace: articleHeroNamespace)
    }

    private var actions: HomeFeedActions {
        HomeFeedActions(openArticle: { article, authority, reason in
            guard let accepted = viewModel.acceptedHomeArticle(id: article.id, authority: authority) else { return }
            if let reason { RecommendationService.shared.trackRecommendationTap(article: accepted, reason: reason) }
            navigationCoordinator.navigateToArticle(accepted, in: .home)
        }, toggleFavorite: { article, authority in
            guard let accepted = viewModel.acceptedHomeArticle(id: article.id, authority: authority) else { return }
            HapticManager.shared.lightImpact()
            viewModel.toggleFavorite(for: accepted)
        }, play: { pair, authority, progress in
            @MainActor func acceptedPair() -> PodcastArticlePair? {
                if let progress {
                    return viewModel.acceptedHomeResumePair(articleID: pair.article.id, episodeID: pair.episode.id,
                        authority: authority, progressContext: progress.context, progressGeneration: progress.generation)
                }
                return viewModel.acceptedHomePair(articleID: pair.article.id, episodeID: pair.episode.id, authority: authority)
            }
            guard let accepted = acceptedPair() else { return }
            _ = PodcastPlayerManager.shared.play(episode: accepted.episode, articleId: accepted.article.id,
                routeIsCurrent: { acceptedPair() != nil })
        }, refresh: {
            await viewModel.refreshArticles()
        }, firstAppearance: {
            viewModel.prepareHomeIfNeeded()
            viewModel.fetchPersonalizedRecommendationsIfNeeded()
            Task { await PodcastRepository.shared.refreshManifest() }
        }, snapshotAccepted: { snapshot in
            viewModel.homeSnapshotWasShown(snapshot)
        })
    }
}

private func heroSwipeSlideOpacity(for phase: ScrollTransitionPhase, reduceMotion: Bool) -> Double {
    guard !reduceMotion, !phase.isIdentity else { return 1 }
    return Double(1 - min(abs(phase.value), 1) * 0.72)
}

private func heroSwipeSlideScale(for phase: ScrollTransitionPhase, reduceMotion: Bool) -> CGFloat {
    guard !reduceMotion, !phase.isIdentity else { return 1 }
    return 1 - min(abs(phase.value), 1) * 0.015
}

struct HeroSwipeBar: View {
    let articles: [Article]
    let metadataByID: [String: HomeArticleMetadata]
    let favoriteIDs: Set<String>
    @Binding var selectedHeroID: String?
    let heroHeight: CGFloat
    let heroTransitionNamespace: Namespace.ID?
    let onOpen: (Article) -> Void
    let onFavorite: (Article) -> Void
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.homeReduceMotionOverride) private var homeReduceMotionOverride
    private var reduceMotion: Bool { systemReduceMotion || homeReduceMotionOverride }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .bottom) {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 0) {
                        ForEach(articles) { article in
                            HeroCardView(article: article, metadata: metadataByID[article.id],
                                isFavorite: favoriteIDs.contains(article.id), width: geometry.size.width,
                                height: heroHeight, heroTransitionNamespace: heroTransitionNamespace,
                                onOpen: { onOpen(article) }, onFavorite: { onFavorite(article) })
                                .id(article.id)
                                .scrollTransition(.interactive, axis: .horizontal) { [reduceMotion] content, phase in
                                    content.opacity(heroSwipeSlideOpacity(for: phase, reduceMotion: reduceMotion))
                                        .scaleEffect(heroSwipeSlideScale(for: phase, reduceMotion: reduceMotion))
                                }
                        }
                    }
                    .scrollTargetLayout()
                }
                .scrollTargetBehavior(.paging)
                .scrollPosition(id: $selectedHeroID)
                .scrollClipDisabled()
                .accessibilityIdentifier("home.hero.carousel")
            }
            .overlayPreferenceValue(HomeHeroActionBoundsKey.self) { anchors in
                GeometryReader { overlay in
                    pageIndicators
                        .padding(.bottom, indicatorBottomInset(in: overlay, anchors: anchors))
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                }
                .allowsHitTesting(false)
            }
        }
        .frame(height: heroHeight)
    }

    private var pageIndicators: some View {
        HStack(spacing: 8) {
            ForEach(articles) { article in
                let selected = article.id == selectedHeroID
                Image(selected ? "CapsuleDot" : "Dot")
                    .resizable().aspectRatio(contentMode: .fit)
                    .frame(width: selected ? 25 : 8, height: 8)
                    .background(selected ? Color.clear : (colorScheme == .dark ? .black : .white.opacity(0.8)))
                    .clipShape(RoundedRectangle(cornerRadius: selected ? 0 : 4))
                    .homeHeroMeasured("indicator." + article.id)
                    .padding(.top, 10)
            }
        }
        .animation(AppMotion.heroCarouselSpring(reduceMotion: reduceMotion), value: selectedHeroID)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Fremhævede artikler")
        .accessibilityValue("\((articles.firstIndex { $0.id == selectedHeroID } ?? 0) + 1) af \(articles.count)")
        .accessibilityIdentifier("home.hero.position")
    }

    private func indicatorBottomInset(in geometry: GeometryProxy, anchors: [String: Anchor<CGRect>]) -> CGFloat {
        guard let id = selectedHeroID ?? articles.first?.id, let anchor = anchors[id] else { return 90 }
        let actionFrame = geometry[anchor]
        guard actionFrame.minY.isFinite else { return 90 }
        // Keep the original 90 pt position when it fits. Larger system text moves
        // only the dots enough to leave 8 pt above the actual selected-card CTA.
        return max(90, geometry.size.height - actionFrame.minY + 8)
    }
}

private struct HomeHeroActionBoundsKey: PreferenceKey {
    static var defaultValue: [String: Anchor<CGRect>] { [:] }
    static func reduce(value: inout [String: Anchor<CGRect>], nextValue: () -> [String: Anchor<CGRect>]) {
        value.merge(nextValue()) { _, latest in latest }
    }
}

struct HeroCardView: View {
    let article: Article
    let metadata: HomeArticleMetadata?
    let isFavorite: Bool
    let width: CGFloat
    let height: CGFloat
    let heroTransitionNamespace: Namespace.ID?
    let onOpen: () -> Void
    let onFavorite: () -> Void
    @State private var imageFailed = false
    @State private var imageLoaded = false
    @State private var heroImageIndex = 0
    @Environment(\.homeImagePolicy) private var imagePolicy
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.homeReduceMotionOverride) private var homeReduceMotionOverride
    private var reduceMotion: Bool { systemReduceMotion || homeReduceMotionOverride }

    private var heroImageURL: URL? {
        let candidates = metadata?.heroImageCandidates ?? []
        return candidates.indices.contains(heroImageIndex) ? candidates[heroImageIndex] : nil
    }

    private var heroBottomGradient: LinearGradient {
        if colorScheme == .dark {
            return LinearGradient(colors: [.clear, .black.opacity(0.3), .black],
                startPoint: .top, endPoint: .bottom)
        }
        return LinearGradient(stops: [.init(color: .clear, location: 0),
            .init(color: .clear, location: 0.42),
            .init(color: .white.opacity(0.12), location: 0.62),
            .init(color: .white.opacity(0.38), location: 0.78),
            .init(color: .white.opacity(0.72), location: 0.9),
            .init(color: .white, location: 1)],
            startPoint: .top, endPoint: .bottom)
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            ZStack {
                ArticleImagePlaceholder(mode: imagePolicy.allowsRemoteImages ? (imageFailed ? .offline : (imageLoaded ? .idle : .loading)) : .idle, cornerRadius: 0)
                if imagePolicy.allowsRemoteImages, !imageFailed, let url = heroImageURL {
                    WebImage(url: url, options: [.retryFailed, .continueInBackground, .scaleDownLargeImages])
                        .resizable()
                        .onSuccess { _, _, _ in imageLoaded = true }
                        .onFailure { _ in
                            let next = heroImageIndex + 1
                            if (metadata?.heroImageCandidates ?? []).indices.contains(next) { heroImageIndex = next }
                            else { imageFailed = true }
                        }
                        .aspectRatio(contentMode: .fill)
                        .visualEffect { [reduceMotion] content, proxy in
                            let stretch = max(0, -proxy.frame(in: .named("homeScroll")).minY)
                            return content.scaleEffect(reduceMotion ? 1 : 1 + min(stretch / max(height, 1), 1) * 0.08)
                                .offset(y: reduceMotion ? 0 : stretch * 0.22)
                        }
                }
            }
            .frame(width: width, height: height).clipped()
            .heroTransitionSource(id: article.id, namespace: heroTransitionNamespace)
            .contentShape(Rectangle()).onTapGesture(perform: onOpen)
            .accessibilityHidden(true)
            heroBottomGradient.allowsHitTesting(false)

            VStack(alignment: .leading, spacing: 12) {
                Spacer()

                VStack(alignment: .center, spacing: 30) {
                    LocalizedArticleTaxonomy(metadata?.heroTag ?? "Generelt")
                        .font(.system(size: 15, weight: .semibold)).foregroundStyle(.white)
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .homeHeroMeasured(article.id + ".section")
                        .accessibilityIdentifier("home.hero.tag.\(article.id)")
                    Button(action: onOpen) {
                        Text(article.name ?? "Titel")
                            .font(.system(size: 34, weight: .bold)).foregroundStyle(.white)
                            .shadow(radius: 4).multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                            .homeHeroMeasured(article.id + ".title.text")
                            .padding(.top, -18)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("home.hero.title.\(article.id)")
                    if let rating = article.stjerne, rating > 0 {
                        HStack(spacing: 6) {
                            ForEach(1...6, id: \.self) { index in
                                Image(systemName: "star.fill").font(.system(size: 18, weight: .semibold))
                                    .foregroundStyle(index <= rating ? (colorScheme == .dark ? Color.white : .black.opacity(0.92)) : (colorScheme == .dark ? .white.opacity(0.24) : .black.opacity(0.14)))
                            }
                        }
                        .padding(.horizontal, 40)
                        .accessibilityLabel("\(rating) af 6 stjerner")
                    }
                    HomeHeroTags(articleID: article.id, authorName: metadata?.authorName,
                        categories: metadata?.categories ?? ["Generelt"])
                    .padding(.top, -15)
                    HStack {
                        Spacer()
                        HStack(spacing: 16) {
                            Button("Læs nu", action: onOpen)
                                .font(.headline).padding(.horizontal, 40).padding(.vertical, 14)
                                .background(RoundedRectangle(cornerRadius: 12).fill(.white)
                                    .shadow(color: .black.opacity(0.2), radius: 8, x: 0, y: 4))
                                .foregroundStyle(.black)
                                .accessibilityIdentifier("home.hero.read.\(article.id)")
                                .homeHeroMeasured(article.id + ".read")
                            Button(action: onFavorite) {
                                Image(systemName: isFavorite ? "checkmark" : "plus")
                                    .font(.title2).frame(width: 24, height: 24).padding(12)
                                    .background(Circle().fill(.white.opacity(0.9))).foregroundStyle(.black)
                            }
                            .accessibilityLabel(Text(LocalizedStringKey(isFavorite ? "Fjern fra gemte artikler" : "Gem artikel")))
                            .accessibilityIdentifier("home.hero.favorite.\(article.id)")
                            .homeHeroMeasured(article.id + ".favorite")
                        }
                        .buttonStyle(.plain)
                        .anchorPreference(key: HomeHeroActionBoundsKey.self, value: .bounds) { [article.id: $0] }
                        Spacer()
                    }
                    .padding(.top, 15)
                }
                .padding(.horizontal, 8).padding(.bottom, 20)
            }
            .foregroundStyle(colorScheme == .dark ? Color.white : .black)
            .frame(width: max(0, width - 32), height: height)
        }
        .frame(width: width, height: height).clipped()
        .homeHeroMeasured(article.id + ".card")
        .shadow(color: colorScheme == .dark ? .black.opacity(0.25) : .clear,
            radius: colorScheme == .dark ? 10 : 0)
        .onChange(of: metadata?.heroImageCandidates) { _, _ in
            heroImageIndex = 0; imageFailed = false; imageLoaded = false
        }
    }
}


/// Actual author/category capsules inside Home's hero. Whole labels wrap onto
/// centered rows while preserving the existing typography, color and capsule tokens.
struct HomeHeroTags: View {
    let articleID: String
    let authorName: String?
    let categories: [String]
    @Environment(\.colorScheme) private var colorScheme
    #if DEBUG && targetEnvironment(simulator)
    @Environment(\.homeHeroGeometryProbe) private var geometryProbe
    #endif

    var body: some View {
        ArticleTagFlowLayout(spacing: 8, lineSpacing: 8, alignment: .center) {
            if let authorName {
                Text(authorName).font(.caption.weight(.semibold)).textCase(.uppercase)
                    .lineLimit(nil).multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .foregroundStyle(colorScheme == .dark ? Color.white : .black)
                    .homeHeroMeasured(articleID + ".author.text")
                    .padding(.vertical, 4).padding(.horizontal, 10)
                    .background(Capsule().fill(colorScheme == .dark ? Color(hex: "#262626") : .white))
                    .homeHeroMeasured(articleID + ".author.pill")
                    .accessibilityLabel(authorName)
                    .accessibilityIdentifier("home.hero.author.\(articleID)")
            }
            ForEach(Array(categories.prefix(2).enumerated()), id: \.offset) { index, category in
                LocalizedArticleTaxonomy(category, uppercase: true).font(.caption.weight(.semibold))
                    .lineLimit(nil).multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .foregroundStyle(colorScheme == .dark ? Color.white : .black)
                    .homeHeroMeasured(articleID + ".category.\(index).text")
                    .padding(.vertical, 4).padding(.horizontal, 6)
                    .background(Capsule().fill(colorScheme == .dark ? Color(hex: "#262626") : .white))
                    .homeHeroMeasured(articleID + ".category.\(index).pill")
                    .accessibilityIdentifier("home.hero.category.\(articleID).\(index)")
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .homeHeroMeasured(articleID + ".tags")
        .overlay(alignment: .topLeading) {
            #if DEBUG && targetEnvironment(simulator)
            if geometryProbe != nil {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(referenceWords, id: \.key) { word in
                        Text(word.text).font(.caption.weight(.semibold))
                            .fixedSize()
                            .homeHeroMeasured(articleID + ".reference." + word.key)
                    }
                }
                .fixedSize().hidden().accessibilityHidden(true).allowsHitTesting(false)
            }
            #endif
        }
    }

    #if DEBUG && targetEnvironment(simulator)
    private var referenceWords: [(key: String, text: String)] {
        var labels: [(String, String)] = []
        if let authorName { labels.append(("author", authorName)) }
        labels += categories.prefix(2).enumerated().map { ("category.\($0.offset)", $0.element) }
        return labels.flatMap { key, text in
            text.uppercased().split(whereSeparator: { $0.isWhitespace }).enumerated().map {
                (key: key + ".\($0.offset)", text: String($0.element))
            }
        }
    }
    #endif
}

#if DEBUG && targetEnvironment(simulator)
private struct HomeHeroGeometryProbeKey: EnvironmentKey {
    static let defaultValue: ((String, CGRect) -> Void)? = nil
}
extension EnvironmentValues {
    var homeHeroGeometryProbe: ((String, CGRect) -> Void)? {
        get { self[HomeHeroGeometryProbeKey.self] }
        set { self[HomeHeroGeometryProbeKey.self] = newValue }
    }
}
#endif

private struct HomeHeroFrameProbe: ViewModifier {
    let key: String
    #if DEBUG && targetEnvironment(simulator)
    @Environment(\.homeHeroGeometryProbe) private var probe
    #endif
    @ViewBuilder func body(content: Content) -> some View {
        #if DEBUG && targetEnvironment(simulator)
        content.onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { probe?(key, $0) }
        #else
        content
        #endif
    }
}
private extension View {
    func homeHeroMeasured(_ key: String) -> some View { modifier(HomeHeroFrameProbe(key: key)) }
}

// MARK: - Simple Category View
struct SimpleCategoryView: View {
    let title: String
    let articles: [Article]
    @EnvironmentObject var viewModel: ArticleViewModel
    @Environment(\.colorScheme) var colorScheme
    @State private var scrollOffset: CGFloat = 0
    @State private var showNavTitle = false
    
    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                GeometryReader { geo in
                    Color.clear
                        .preference(key: ScrollOffsetKey.self, value: geo.frame(in: .named("scroll")).minY)
                }
                .frame(height: 0)

                // Den store overskrift – vises kun i toppen
                if !showNavTitle {
                    Text(LocalizedStringKey(title))
                        .font(.largeTitle.bold())
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 16)
                        .padding(.top, 16)
                        .padding(.bottom, 12)
                        .transition(.opacity)
                }

                // Artikelliste
                LazyVStack(spacing: 0) {
                    ForEach(articles) { article in
                        NavigationLink(value: article) {
                            ArticleRowCompact(article: article)
                        }
                        .buttonStyle(PlainButtonStyle())
                        
                        if article.id != articles.last?.id {
                            Divider()
                                .padding(.leading, 16)
                        }
                    }
                }
                .padding(.top, showNavTitle ? 12 : 0)
                
                Spacer(minLength: 80)
            }
        }
        .coordinateSpace(name: "scroll")
        .onPreferenceChange(ScrollOffsetKey.self) { value in
            scrollOffset = value
            withAnimation(.easeInOut(duration: 0.2)) {
                showNavTitle = scrollOffset <= -30
            }
        }
        .navigationTitle(LocalizedStringKey(showNavTitle ? title : ""))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text(LocalizedStringKey(showNavTitle ? title : ""))
                    .font(.headline)
                    .opacity(showNavTitle ? 1 : 0)
            }
        }
        .onAppear {
            showNavTitle = false
        }
    }
}

#Preview {
    NavigationView {
        HomeView()
            .environmentObject(ArticleViewModel())
    }
}

struct ReviewRowView: View {
    let index: Int
    let article: Article

    var body: some View {
        NavigationLink(value: article) {
            
            HStack(alignment: .top, spacing: 12) {
                Text("\(index)")
                    .font(.subheadline.bold())
                    .foregroundColor(Color("SerialNumberColor"))
                    .frame(width: 24, height: 24)
                    .background(Color("SerialNumberColorBOX"))
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .padding(.top ,0)
                    .padding(.leading ,5)
                Text(article.name ?? "Uden titel")
                    .font(.system(size: 18, weight: .bold, design: .default))
                    .foregroundColor(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer()
            }
            .padding(.bottom , 15)
            .padding(.leading , 15)
            .padding(.trailing , 10)
            .padding(.top, 3)
            .background(Color("AppGray"))
            .cornerRadius(10)
        }
        .buttonStyle(PlainButtonStyle()) // Prevents default blue arrow/highlight
    }
}

struct ArticleStaticCell: View {
    let article: Article
    var hasRoundedImage: Bool = true
    @EnvironmentObject var viewModel: ArticleViewModel
    @State private var imageLoaded = false
    @State private var imageFailed = false

    // Get categories for this article
    private var articleCategories: [String] {
        var categories: [String] = []
        
        // Add main topic category
        if let topicID = article.topicID,
           let topic = viewModel.topics.first(where: { $0.id == topicID }) {
            categories.append(topic.name)
        }
        
        // Add multi-topic categories if available
        if let topicsIDs = article.topicsIDs {
            for topicID in topicsIDs {
                if let topic = viewModel.topics.first(where: { $0.id == topicID }),
                   !categories.contains(topic.name) {
                    categories.append(topic.name)
                }
            }
        }
        
        return categories.isEmpty ? ["Generelt"] : categories
    }

    private var placeholderMode: ArticleImagePlaceholderMode {
        if imageFailed { return .offline }
        if imageLoaded { return .idle }
        return .loading
    }

    var body: some View {
        NavigationLink(value: article) {
            // Prevents default blue arrow/highlight
            VStack(spacing: 0) {
                HStack(alignment: .top, spacing: 16) {
                    // Thumbnail
                    var mutableArticle = article
                    ZStack {
                        ArticleImagePlaceholder(mode: placeholderMode, cornerRadius: hasRoundedImage ? 8 : 0)

                        if !imageFailed {
                            AsyncImage(url: URL(string: mutableArticle.thumbnailURL)) { phase in
                                switch phase {
                                case .success(let image):
                                    image
                                        .resizable()
                                        .scaledToFill()
                                        .onAppear {
                                            imageLoaded = true
                                        }
                                case .failure:
                                    Color.clear
                                        .onAppear {
                                            imageFailed = true
                                            imageLoaded = false
                                        }
                                default:
                                    Color.clear
                                }
                            }
                        }
                    }
                    .frame(width: 100, height: 100)
                    .clipped()
                    .cornerRadius(hasRoundedImage ? 8 : 0)
                    .onChange(of: article.id) { _, _ in
                        imageLoaded = false
                        imageFailed = false
                    }
                    
                    // Title & Category
                    VStack(alignment: .leading, spacing: 6) {
                        Text(article.name ?? "Title")
                            .font(.headline)
                            .foregroundColor(.primary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                        
                        Spacer()
                        
                        LocalizedArticleTaxonomy(articleCategories)
                            .font(.subheadline)
                            .foregroundColor(.primary)
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        
                    }
                    .frame(height: 100)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    
                    // Chevron
                    Image(systemName: "chevron.right")
                        .foregroundColor(.gray)
                        .frame(height: 100)
                        .alignmentGuide(.top) { _ in 0 }
                }
                .padding(.vertical, 12)
                
                Divider()
                    .background(Color.white)
            }
            .padding(.horizontal, 16)
        }
        .buttonStyle(PlainButtonStyle())
    }
}












extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        let scanner = Scanner(string: hex)
        
        if hex.hasPrefix("#") {
            _ = scanner.scanString("#")
        }
        
        var rgb: UInt64 = 0
        scanner.scanHexInt64(&rgb)
        
        let r = Double((rgb >> 16) & 0xFF) / 255
        let g = Double((rgb >> 8) & 0xFF) / 255
        let b = Double(rgb & 0xFF) / 255
        
        self.init(red: r, green: g, blue: b)
    }
}
//MArk":- meeeeee
extension View {
    func onFirstAppear(_ perform: @escaping () -> Void) -> some View {
        modifier(OnFirstAppearModifier(perform: perform))
    }
}
private struct OnFirstAppearModifier: ViewModifier {
    @State private var hasAppeared = false
    let perform: () -> Void

    func body(content: Content) -> some View {
        content
            .onAppear {
                if !hasAppeared {
                    hasAppeared = true
                    perform()
                }
            }
    }
}


// MARK: - Simple Category View (Same layout as CategoryArticlesView)
