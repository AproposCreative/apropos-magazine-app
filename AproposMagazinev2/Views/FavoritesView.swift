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
    @State private var showSettings: Bool = false

    // Computed properties for filtering and sorting
    private var enrichedFavorites: [Article] {
        viewModel.favorites.map { favorite in
            viewModel.articles.first(where: { $0.id == favorite.id }) ?? favorite
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
        List {
            Section {
                header
                controls
            }
            .listRowInsets(EdgeInsets())
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
        .sheet(isPresented: $showSettings) {
            SettingsView()
                .environmentObject(viewModel)
        }
    }

    private var header: some View {
        HStack(alignment: .center) {
            Text("Min side")
                .font(.largeTitle.bold())

            Spacer()

            Button {
                showSettings = true
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(.primary)
                    .frame(width: 36, height: 36)
                    .background(Color.gray.opacity(0.1))
                    .clipShape(Circle())
            }
            .accessibilityLabel("Indstillinger")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 12)
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
        VStack(spacing: 16) {
            HStack(spacing: 12) {
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
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.up.arrow.down")
                            .font(.caption)
                        Text(selectedSort.rawValue)
                            .font(.subheadline)
                            .lineLimit(1)
                            .truncationMode(.tail)
                        Image(systemName: "chevron.down")
                            .font(.caption2)
                    }
                    .foregroundColor(.primary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .frame(minWidth: 134, maxWidth: 170)
                    .background(Color.gray.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }

                if !availableCategories.isEmpty {
                    Menu {
                        Button("Alle") { selectedCategory = "Alle" }
                        Divider()
                        ForEach(availableCategories, id: \.self) { category in
                            Button(category) { selectedCategory = category }
                        }
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "tag")
                                .font(.caption)
                            Text(selectedCategory)
                                .font(.subheadline)
                                .lineLimit(1)
                                .truncationMode(.tail)
                                .fixedSize(horizontal: true, vertical: false)
                            Image(systemName: "chevron.down")
                                .font(.caption2)
                        }
                        .foregroundColor(.primary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .frame(minWidth: 86, maxWidth: 132)
                        .background(Color.gray.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                }

                Spacer()

                Button {
                    navigationCoordinator.navigateToTab(.search)
                } label: {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.primary)
                        .padding(8)
                        .background(Color.gray.opacity(0.1))
                        .clipShape(Circle())
                }

                Text("\(sortedFavorites.count) artikler")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
            }
            .padding(.horizontal, 16)
        }
        .padding(.bottom, 8)
    }

    private var emptyState: some View {
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
    }
}

// MARK: - Favorite Article Row Component
struct FavoriteArticleRow: View {
    var article: Article
    @EnvironmentObject var viewModel: ArticleViewModel
    @State private var imageFailed = false

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            ZStack {
                ArticleImagePlaceholder(mode: imageFailed ? .offline : .loading, cornerRadius: 8)

                if let url = article.offlineListThumbnailURL, !imageFailed {
                    WebImage(url: url, options: [.retryFailed, .continueInBackground, .scaleDownLargeImages])
                        .resizable()
                        .onFailure { _ in
                            imageFailed = true
                        }
                        .transition(.fade(duration: 0.25))
                        .aspectRatio(contentMode: .fill)
                }
            }
            .frame(width: 80, height: 80)
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .onChange(of: article.id) { _, _ in
                imageFailed = false
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

