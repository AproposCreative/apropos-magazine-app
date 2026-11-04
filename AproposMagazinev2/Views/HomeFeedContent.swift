import SwiftUI

struct HomeResumeOwnership: Equatable {
    let context: PodcastProgressContext
    let generation: UUID
}

@MainActor
struct HomeFeedActions {
    var openArticle: (Article, HomeFeedAuthority, String?) -> Void = { _, _, _ in }
    var toggleFavorite: (Article, HomeFeedAuthority) -> Void = { _, _ in }
    var play: (PodcastArticlePair, HomeFeedAuthority, HomeResumeOwnership?) -> Void = { _, _, _ in }
    var refresh: () async -> Void = {}
    var firstAppearance: () -> Void = {}
    var snapshotAccepted: (HomeFeedSnapshot) -> Void = { _ in }
}

/// The actual Home screen. Production and the native fixture supply the same
/// prepared model, navigation actions and progress dependencies.
struct HomeFeedContent: View {
    @ObservedObject var model: HomeFeedPreparationModel
    let progressStore: PodcastPlaybackProgressStore
    let presentation: PodcastPlayerPresentationModel
    let favoriteIDs: Set<String>
    let isLoading: Bool
    let errorMessage: String?
    let actions: HomeFeedActions
    var articleHeroNamespace: Namespace.ID? = nil

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.homeReduceMotionOverride) private var homeReduceMotionOverride
    private var reduceMotion: Bool { systemReduceMotion || homeReduceMotionOverride }
    @Environment(\.scenePhase) private var scenePhase
    @State private var selectedHeroID: String?
    @State private var showGlassTopBar = false
    @State private var didAppear = false
    @State private var podcastsOwner: UUID?

    var body: some View {
        GeometryReader { geometry in
            // Restore the original 70% hero using this container's full extent,
            // including the safe areas excluded from its proposed content size.
            let heroHeight = (geometry.size.height + geometry.safeAreaInsets.top + geometry.safeAreaInsets.bottom) * 0.7
            ZStack(alignment: .top) {
                ScrollViewReader { proxy in
                    ScrollView {
                        // Keep the zero-height scroll probe adjacent to the hero.
                        // An implicit stack adds 8pt above the full-bleed image.
                        VStack(spacing: 0) {
                            GeometryReader { probe in
                                Color.clear.onChange(of: probe.frame(in: .named("homeScroll")).minY) { _, offset in
                                    let next = offset < -16
                                    if next != showGlassTopBar {
                                        withAnimation(AppMotion.easeOut(duration: 0.16, reduceMotion: reduceMotion)) { showGlassTopBar = next }
                                    }
                                }
                            }
                            .frame(height: 0).id("homeScrollTop")

                            if let snapshot = model.snapshot, hasContent(snapshot) {
                                feed(snapshot, heroHeight: heroHeight)
                            } else if isLoading || model.state.isPreparing {
                                FullPageSkeleton().accessibilityIdentifier("home.loading")
                            } else if errorMessage != nil || model.state.errorMessage != nil {
                                EmptyStateView(icon: "exclamationmark.triangle.fill", title: "Kunne ikke hente artikler",
                                    subtitle: "Tjek forbindelsen, eller prøv at opdatere igen.", actionTitle: "Prøv igen") {
                                        Task { await actions.refresh() }
                                    }
                                    .padding(.top, 160).padding(.horizontal, 16)
                            } else {
                                ContentUnavailableView("Ingen artikler endnu", systemImage: "doc.text",
                                    description: Text("Opdatér for at hente de nyeste historier."))
                                    .padding(.top, 120)
                            }
                        }
                    }
                    .accessibilityIdentifier("home.feed")
                    .onReceive(NotificationCenter.default.publisher(for: .scrollHomeToTop)) { _ in
                        withAnimation(AppMotion.easeOut(duration: 0.25, reduceMotion: reduceMotion)) {
                            proxy.scrollTo("homeScrollTop", anchor: .top)
                        }
                        showGlassTopBar = false
                    }
                }
                .coordinateSpace(name: "homeScroll")
                .scrollContentBackground(.hidden)
                .refreshable { await actions.refresh() }

                logoBar(topInset: geometry.safeAreaInsets.top)
                    .allowsHitTesting(false).zIndex(1)
            }
            .ignoresSafeArea(edges: .top)
        }
        .toolbar(.hidden, for: .navigationBar)
        .toolbarBackground(.hidden, for: .navigationBar)
        .onAppear {
            if !didAppear { didAppear = true; actions.firstAppearance() }
            acceptPresentation()
        }
        .onChange(of: model.state.revision) { _, _ in acceptPresentation() }
        .onChange(of: scenePhase) { _, phase in if phase == .active { model.sceneBecameActive() } }
        .navigationDestination(isPresented: Binding(get: { podcastsOwner != nil }, set: { if !$0 { podcastsOwner = nil } })) {
            if let owner = podcastsOwner {
                HomePreparedPodcastList(model: model, progressStore: progressStore, originalOwner: owner, actions: actions)
            }
        }
    }

    private func acceptPresentation() {
        guard let snapshot = model.snapshot else { return }
        if selectedHeroID == nil || !snapshot.hero.contains(where: { $0.id == selectedHeroID }) {
            selectedHeroID = snapshot.hero.first?.id
        }
        if hasContent(snapshot), !model.state.isPreparing { actions.snapshotAccepted(snapshot) }
    }

    private func hasContent(_ snapshot: HomeFeedSnapshot) -> Bool {
        !snapshot.hero.isEmpty || !snapshot.podcastPairs.isEmpty || snapshot.rails.contains { !$0.visible.isEmpty }
    }

    private func logoBar(topInset: CGFloat) -> some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: topInset)
            Image(colorScheme == .dark ? "AproposLogoWhite" : "AproposLogoBlack")
                .resizable().aspectRatio(contentMode: .fit).frame(height: 30).opacity(0.9)
                .frame(maxWidth: .infinity).padding(.vertical, 12).frame(height: 60)
        }
        .background {
            if showGlassTopBar { Rectangle().fill(.ultraThinMaterial).ignoresSafeArea(edges: .top) }
        }
        .accessibilityHidden(true)
    }

    private func feed(_ snapshot: HomeFeedSnapshot, heroHeight: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if !snapshot.hero.isEmpty {
                HeroSwipeBar(articles: snapshot.hero, metadataByID: snapshot.metadataByID, favoriteIDs: favoriteIDs,
                    selectedHeroID: $selectedHeroID, heroHeight: heroHeight, heroTransitionNamespace: articleHeroNamespace,
                    onOpen: { actions.openArticle($0, snapshot.authority, nil) },
                    onFavorite: { actions.toggleFavorite($0, snapshot.authority) })
            }

            HomeResumeContent(snapshot: snapshot, progressStore: progressStore, presentation: presentation, actions: actions)

            if !snapshot.podcastPairs.isEmpty {
                PodcastSectionView(progressStore: progressStore,
                    pairs: Array(snapshot.podcastPairs.prefix(2)), allPairs: snapshot.podcastPairs,
                    authorProvider: { snapshot.podcastByline(for: $0) },
                    categoriesProvider: { snapshot.metadataByID[$0.id]?.categories ?? ["Generelt"] },
                    onOpenArticle: { actions.openArticle($0, snapshot.authority, nil) },
                    onPlayPair: { actions.play($0, snapshot.authority, nil) }, onSeeAll: { podcastsOwner = snapshot.authority.owner })
                    .padding(.top, 20)
            }

            ForEach(snapshot.rails) { rail in
                if !rail.visible.isEmpty {
                    ArticleSectionView(model: model, rail: rail, snapshot: snapshot, actions: actions)
                        .padding(.top, rail.kind == .recommended ? 44 : 20)
                }
            }
            HomeBottomSpacer(presentation: presentation)
        }
    }
}

/// Clock/progress changes are confined to listening UI. The editorial parent
/// never observes the progress store or playback clock.
private struct HomeResumeContent: View {
    let snapshot: HomeFeedSnapshot
    @ObservedObject var progressStore: PodcastPlaybackProgressStore
    @ObservedObject var presentation: PodcastPlayerPresentationModel
    let actions: HomeFeedActions

    var body: some View {
        let progress = progressStore.snapshot
        let id = progress.lastPlayedEpisodeID
        let pair = snapshot.resumeIndex.pair(episodeID: id, articleID: progress.lastPlayedArticleID,
            hasResumableProgress: id.map(progress.hasResumableProgress) ?? false)
        VStack(spacing: 0) {
            PodcastProgressNotice(store: progressStore).padding(.horizontal, 16)
            if let pair, pair.episode.id != presentation.snapshot.activeEpisodeID {
                let original = HomeResumeOwnership(context: progressStore.context, generation: progress.generation)
                PodcastContinueListeningBanner(pair: pair,
                    onContinue: { actions.play(pair, snapshot.authority, original) },
                    onOpenArticle: { actions.openArticle(pair.article, snapshot.authority, nil) })
                    .padding(.top, 32)
            }
        }
    }
}

private struct HomeBottomSpacer: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ObservedObject var presentation: PodcastPlayerPresentationModel
    var body: some View {
        Color.clear.frame(height: PodcastMiniPlayerLayout.feedBottomPadding(isPlayerVisible: presentation.snapshot.hasActiveEpisode, size: dynamicTypeSize))
    }
}

struct ArticleSectionView: View {
    let model: HomeFeedPreparationModel
    let rail: HomeRail
    let snapshot: HomeFeedSnapshot
    let actions: HomeFeedActions

    var body: some View {
        let cardWidth: CGFloat = rail.isTopic ? 270 : 173
        let imageHeight: CGFloat = rail.isTopic ? 310 : 96
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                Text(LocalizedStringKey(rail.title)).font(.system(size: 25, weight: .heavy))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier("home.rail.\(rail.kind.rawValue)")
                if rail.all.count > rail.visible.count {
                    NavigationLink {
                        HomePreparedArticleList(model: model, kind: rail.kind, originalOwner: snapshot.authority.owner, actions: actions)
                    } label: {
                        Text("Se alle").font(.subheadline.weight(.medium)).foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("home.seeAll.\(rail.kind.rawValue)")
                    .accessibilityLabel("Se alle: \(rail.title)")
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 14)

            ScrollView(.horizontal, showsIndicators: false) {
                // Rails already contain a bounded visible selection. Measuring
                // those actual cards lets date/rating/large text determine the
                // height instead of clipping them to an estimated allowance.
                HStack(alignment: .top, spacing: 10) {
                    ForEach(rail.visible) { article in
                        let metadata = snapshot.metadataByID[article.id]
                        ArticleCardView_Enhanced(article: article,
                            cardHeight: imageHeight, showStars: rail.isTopic, showTopic: rail.isTopic,
                            recommendationReason: rail.reasonsByID[article.id], categories: metadata?.categories ?? ["Generelt"],
                            imageURL: metadata?.cardImageURL,
                            onOpen: {
                                actions.openArticle($0, snapshot.authority,
                                    rail.kind == .recommended ? rail.reasonsByID[$0.id] ?? "" : nil)
                            }, openAccessibilityID: "home.card.\(rail.kind.rawValue).\(article.id)",
                            deferImageUntilVisible: true)
                            .frame(width: cardWidth)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.horizontal, 16)
            }
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier("home.rail.scroll.\(rail.kind.rawValue)")
        }
    }
}

/// Its rail and metadata are reread from the committed model. An owner change
/// withdraws the route; a content refresh never leaves a retained old payload.
struct HomePreparedArticleList: View {
    @ObservedObject var model: HomeFeedPreparationModel
    let kind: HomeRail.Kind
    let originalOwner: UUID
    let actions: HomeFeedActions

    var body: some View {
        ScrollView {
            if let snapshot = model.snapshot, snapshot.authority.owner == originalOwner {
                let rail = snapshot.rail(kind)
                LazyVStack(spacing: 0) {
                    Text(LocalizedStringKey(rail.title)).font(.largeTitle.bold()).frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 16)
                    Text("\(rail.all.count) artikler").font(.subheadline).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(.bottom, 12)
                        .accessibilityIdentifier("home.list.count")
                    ForEach(rail.all) { article in
                        Button {
                            actions.openArticle(article, snapshot.authority,
                                kind == .recommended ? rail.reasonsByID[article.id] ?? "" : nil)
                        } label: {
                            HomePreparedArticleRow(article: article, metadata: snapshot.metadataByID[article.id])
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("home.list.article.\(article.id)")
                        Divider()
                    }
                }
                .padding(.horizontal, 16)
            } else {
                ContentUnavailableView("Indholdet er opdateret", systemImage: "arrow.clockwise",
                    description: Text("Gå tilbage til Hjem for at se det aktuelle udvalg."))
                    .accessibilityIdentifier("home.list.unavailable")
            }
        }
        .navigationTitle(LocalizedStringKey(kind.title)).navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .accessibilityIdentifier("home.list")
    }
}

struct HomePreparedArticleRow: View {
    let article: Article
    let metadata: HomeArticleMetadata?
    @Environment(\.homeImagePolicy) private var imagePolicy
    var body: some View {
        HStack(alignment: .bottom, spacing: 12) {
            HomePreparedThumbnail(url: metadata?.listImageURL, policy: imagePolicy)
            VStack(alignment: .leading, spacing: 6) {
                Text(article.name ?? "Uden titel").font(.headline).foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                LocalizedArticleTaxonomy(metadata?.categories ?? ["Generelt"])
                    .font(.caption).foregroundStyle(.secondary)
                if let name = metadata?.authorName { Text(name).font(.caption).foregroundStyle(.secondary) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Image(systemName: "chevron.right").foregroundStyle(.secondary).accessibilityHidden(true)
        }
        .padding(.vertical, 14)
    }
}

private struct HomePreparedThumbnail: View {
    let url: URL?
    let policy: HomeImagePolicy
    var body: some View {
        ZStack {
            ArticleImagePlaceholder(showShimmer: false, cornerRadius: 10)
            if policy.allowsRemoteImages {
                AsyncImage(url: url) { image in image.resizable().scaledToFill() } placeholder: { Color.clear }
            }
        }
        .frame(width: 72, height: 72).clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

private struct HomePreparedPodcastList: View {
    @ObservedObject var model: HomeFeedPreparationModel
    let progressStore: PodcastPlaybackProgressStore
    let originalOwner: UUID
    let actions: HomeFeedActions
    var body: some View {
        if let snapshot = model.snapshot, snapshot.authority.owner == originalOwner {
            PodcastListView(progressStore: progressStore, pairs: snapshot.podcastPairs,
                authorProvider: { snapshot.podcastByline(for: $0) },
                categoriesProvider: { snapshot.metadataByID[$0.id]?.categories ?? ["Generelt"] },
                onOpenArticle: { actions.openArticle($0, snapshot.authority, nil) },
                onPlayPair: { actions.play($0, snapshot.authority, nil) })
                .toolbar(.visible, for: .navigationBar)
        } else {
            ContentUnavailableView("Indholdet er opdateret", systemImage: "arrow.clockwise",
                description: Text("Gå tilbage til Hjem for at se det aktuelle udvalg."))
                .navigationTitle("Lydindhold").toolbar(.visible, for: .navigationBar)
        }
    }
}
