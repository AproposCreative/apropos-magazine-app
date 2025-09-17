import SwiftUI
import SDWebImageSwiftUI
import Shimmer

struct FavoritesView: View {
    @EnvironmentObject var viewModel: ArticleViewModel
    @Environment(\.navigationCoordinator) private var navigationCoordinator

    // Sorteringsmuligheder
    enum SortOption: String, CaseIterable, Identifiable {
        case titleAZ = "Titel A-Å"
        case titleZA = "Titel Å-A"
        case ratingHigh = "Bedst bedømt"
        case ratingLow = "Lavest bedømt"
        case newest = "Nyeste først"
        case oldest = "Ældste først"

        var id: String { self.rawValue }
    }

    @State private var selectedSort: SortOption = .titleAZ
    @State private var selectedCategory: String = "Alle"
    @State private var showNavTitle: Bool = false

    // Computed properties for filtering and sorting
    private var availableCategories: [String] {
        let cats: [String] = viewModel.articles.filter { viewModel.isFavorite($0) }
            .compactMap { article in
                viewModel.topics.first(where: { $0.id == article.topicID })?.name
            }
            .filter { !$0.isEmpty }
        return Array(Set(cats)).sorted()
    }

    private var sortedFavorites: [Article] {
        var favs = viewModel.articles.filter { viewModel.isFavorite($0) }

        // Filter by category if not "Alle"
        if selectedCategory != "Alle" {
            favs = favs.filter { article in
                let topicName: String = viewModel.topics.first(where: { $0.id == article.topicID })?.name ?? ""
                return topicName == selectedCategory
            }
        }

        // Sort based on selected option
        switch selectedSort {
        case .titleAZ:
            favs = favs.sorted { ($0.name ?? "").localizedCaseInsensitiveCompare($1.name ?? "") == .orderedAscending }
        case .titleZA:
            favs = favs.sorted { ($0.name ?? "").localizedCaseInsensitiveCompare($1.name ?? "") == .orderedDescending }
        case .ratingHigh:
            favs = favs.sorted { $0.rating > $1.rating }
        case .ratingLow:
            favs = favs.sorted { $0.rating < $1.rating }
        case .newest:
            favs = favs.sorted { $0.id > $1.id } // Forudsætter at id er UUID eller stigende
        case .oldest:
            favs = favs.sorted { $0.id < $1.id }
        }

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
        NavigationView {
            ZStack(alignment: .top) {
                ScrollView {
                    GeometryReader { geo in
                        Color.clear
                            .frame(height: 1)
                            .preference(key: ScrollOffsetKey.self, value: geo.frame(in: .named("scroll")).minY)
                    }

                    VStack(spacing: 0) {
                        // Large Title 'Gemt' shown only when showNavTitle is false
                        if !showNavTitle {
                            HStack {
                                Text("Gemt")
                                    .font(.largeTitle)
                                    .fontWeight(.bold)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.horizontal, 16)
                                    .padding(.top, 12)
                                    .padding(.bottom, 8)
                            }
                            .transition(.opacity)
                        }

                        // Controls
                        VStack(spacing: 16) {
                            HStack(spacing: 12) {
                                // Sort menu
                                Menu {
                                    ForEach(SortOption.allCases) { option in
                                        Button(action: { selectedSort = option }) {
                                            HStack {
                                                Text(option.rawValue)
                                                if selectedSort == option {
                                                    Spacer()
                                                    Image(systemName: "checkmark")
                                                }
                                            }
                                        }
                                    }
                                } label: {
                                    HStack {
                                        Image(systemName: "arrow.up.arrow.down")
                                            .font(.caption)
                                        Text(selectedSort.rawValue)
                                            .font(.subheadline)
                                        Image(systemName: "chevron.down")
                                            .font(.caption2)
                                    }
                                    .foregroundColor(.primary)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .background(Color.gray.opacity(0.1))
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                }

                                // Category filter
                                if !availableCategories.isEmpty {
                                    Menu {
                                        Button("Alle") { selectedCategory = "Alle" }
                                        Divider()
                                        ForEach(availableCategories, id: \.self) { category in
                                            Button(category) { selectedCategory = category }
                                        }
                                    } label: {
                                        HStack {
                                            Image(systemName: "tag")
                                                .font(.caption)
                                            Text(selectedCategory)
                                                .font(.subheadline)
                                            Image(systemName: "chevron.down")
                                                .font(.caption2)
                                        }
                                        .foregroundColor(.primary)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 8)
                                        .background(Color.gray.opacity(0.1))
                                        .clipShape(RoundedRectangle(cornerRadius: 8))
                                    }
                                }

                                Spacer()

                                // Article count
                                Text("\(sortedFavorites.count) artikler")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .padding(.horizontal, 16)
                        }
                        .padding(.bottom, 8)

                        // Articles list
                        if viewModel.isLoading {
                            shimmerPlaceholder
                        } else if sortedFavorites.isEmpty {
                            // Empty state
                            VStack(spacing: 16) {
                                Image(systemName: "bookmark.slash")
                                    .font(.system(size: 48))
                                    .foregroundColor(.secondary)

                                Text("Ingen gemte artikler")
                                    .font(.title2)
                                    .fontWeight(.medium)
                                    .foregroundColor(.primary)

                                Text("Gem artikler ved at trykke på plus-knappen")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                    .multilineTextAlignment(.center)
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(Color.clear)
                            .padding(.top, 100)
                        } else {
                            // Articles list
                            VStack(spacing: 0) {
                                ForEach(sortedFavorites) { article in
                                    Button(action: {
                                        navigationCoordinator.navigateToArticle(article, in: .favorites)
                                    }) {
                                        FavoriteArticleRow(article: article)
                                            .padding(.vertical, 12)
                                            .padding(.horizontal, 16)
                                    }
                                    .buttonStyle(PlainButtonStyle())

                                    if article.id != sortedFavorites.last?.id {
                                        Divider()
                                            .padding(.leading, 112) // Align with content
                                    }
                                }
                            }
                        }

                        Spacer(minLength: 80)
                    }
                }
                .coordinateSpace(name: "scroll")
                .onPreferenceChange(ScrollOffsetKey.self) { value in
                    let offset = value
                    withAnimation(.easeInOut(duration: 0.25)) {
                        showNavTitle = offset < -8
                    }
                }
                .scrollableModernTopBar(
                    title: "Gemt",
                    showNavTitle: $showNavTitle,
                    showSearchButton: true,
                    showMenuButton: true,
                    showNotificationButton: true,
                    showUserMenuButton: true,
                    onSearch: {
                        // Navigate to search
                        navigationCoordinator.navigateToTab(.search)
                    },
                    onMenu: {
                        // Show favorites menu
                        print("Favorites menu tapped")
                    },
                    onNotification: {
                        // Handle notifications
                        print("Notifications tapped")
                    },
                    onUserMenu: {
                        // Handle user menu
                        print("User menu tapped")
                    }
                )
        }
    }
}

// MARK: - Favorite Article Row Component
struct FavoriteArticleRow: View {
    let article: Article
    @EnvironmentObject var viewModel: ArticleViewModel

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            // Image - No rounded corners for Apple premium look
            if let url = URL(string: article.thumbnailURL), !article.thumbnailURL.isEmpty {
                WebImage(url: url, options: [.retryFailed, .continueInBackground])
                    .resizable()
                    .indicator(.activity)
                    .transition(.fade(duration: 0.3))
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 80, height: 80)
                    .clipped() // No rounded corners - Apple premium style
            } else {
                Image("FallbackImage")
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 80, height: 80)
                    .clipped() // No rounded corners - Apple premium style
            }

            // Content
            VStack(alignment: .leading, spacing: 6) {
                // Title
                Text(article.name ?? "")
                    .font(.headline)
                    .foregroundColor(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                // Category (if available)
                if let topicName = viewModel.topics.first(where: { $0.id == article.topicID })?.name,
                   !topicName.isEmpty {
                    Text(topicName)
                        .font(.caption)
                        .textCase(.uppercase)
                        .foregroundColor(.secondary)
                        .tracking(0.5)
                }

                // Intro text
                if let intro = article.intro, !intro.isEmpty {
                    Text(intro)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Removed chevron indicator as requested
        }
        .background(Color.clear)
    }
}

struct FavoritesView_Previews: PreviewProvider {
    static var previews: some View {
        let vm = ArticleViewModel()
        // Simulate a few favorited articles for the preview
        if let firstArticle = vm.articles.first {
            vm.favorites = [firstArticle]
        }

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
}

