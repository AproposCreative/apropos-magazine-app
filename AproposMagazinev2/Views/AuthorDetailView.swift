import SwiftUI
import SDWebImageSwiftUI

struct AuthorDetailView: View {
    let author: Author

    @EnvironmentObject private var viewModel: ArticleViewModel
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var imageFailed = false
    @State private var showGlassTopBar = false
    @State private var topSafeAreaInset: CGFloat = 0

    /// Lift name + title slightly above the hero bottom edge.
    private let heroTextLift: CGFloat = 24

    private var heroHeight: CGFloat {
        UIScreen.main.bounds.height * 0.7
    }

    private var authorArticles: [Article] {
        viewModel.articles(byAuthorId: author.id)
    }

    private var previewArticles: [Article] {
        Array(authorArticles.prefix(8))
    }

    private var firstName: String {
        let parts = author.name
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)
        return parts.first ?? author.name
    }

    private var photoURL: URL? {
        let raw = [author.photoURL, author.imageURL ?? ""]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
        guard let raw else { return nil }
        return URL(string: raw) ?? URL(string: raw.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? raw)
    }

    private var heroBottomGradient: LinearGradient {
        if colorScheme == .dark {
            return LinearGradient(
                gradient: Gradient(colors: [.clear, .black.opacity(0.3), .black]),
                startPoint: .top,
                endPoint: .bottom
            )
        }
        return LinearGradient(
            gradient: Gradient(stops: [
                .init(color: .clear, location: 0.0),
                .init(color: .clear, location: 0.42),
                .init(color: .white.opacity(0.12), location: 0.62),
                .init(color: .white.opacity(0.38), location: 0.78),
                .init(color: .white.opacity(0.72), location: 0.9),
                .init(color: .white, location: 1.0)
            ]),
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private var textColor: Color {
        colorScheme == .dark ? .white : .black
    }

    var body: some View {
        ZStack(alignment: .top) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    GeometryReader { geo in
                        Color.clear
                            .frame(height: 0.1)
                            .onChange(of: geo.frame(in: .named("authorScroll")).minY) { _, newValue in
                                let shouldShow = newValue < -16
                                if shouldShow != showGlassTopBar {
                                    withAnimation(AppMotion.easeOut(duration: 0.16, reduceMotion: reduceMotion)) {
                                        showGlassTopBar = shouldShow
                                    }
                                }
                            }
                    }
                    .frame(height: 0.1)

                    authorHero
                        .frame(height: heroHeight)
                        // Match Home hero: bleed under status bar (author page only).
                        .padding(.top, -topSafeAreaInset)

                    if let bio = author.bio?.trimmingCharacters(in: .whitespacesAndNewlines), !bio.isEmpty {
                        Text(bio)
                            .font(.system(size: 20, weight: .medium))
                            .foregroundColor(textColor)
                            .kerning(-0.43)
                            .lineSpacing(6)
                            .padding(.horizontal, 16)
                            .padding(.top, 4)
                            .multilineTextAlignment(.leading)
                    }

                    authorArticlesSection
                        .padding(.top, 40)
                        .padding(.bottom, 100)
                }
            }
            .coordinateSpace(name: "authorScroll")
            .ignoresSafeArea(edges: .top)

            authorTopBar
        }
        .background(
            GeometryReader { geometry in
                Color.clear
                    .onAppear { topSafeAreaInset = geometry.safeAreaInsets.top }
                    .onChange(of: geometry.safeAreaInsets.top) { _, newValue in
                        topSafeAreaInset = newValue
                    }
            }
        )
        .navigationBarBackButtonHidden(true)
        .enhancedSwipeToGoBack(isEnabled: true)
        .toolbar(.hidden, for: .navigationBar)
        .onAppear {
            if viewModel.authors.first(where: { $0.id == author.id }) == nil {
                viewModel.fetchAuthor(by: author.id) { _ in }
            }
        }
    }

    private var authorHero: some View {
        ZStack(alignment: .bottom) {
            ArticleImagePlaceholder(mode: imageFailed ? .offline : .loading, cornerRadius: 0)
                .frame(width: UIScreen.main.bounds.width, height: heroHeight)

            if !imageFailed, let photoURL {
                WebImage(url: photoURL, options: [.retryFailed, .continueInBackground, .scaleDownLargeImages])
                    .resizable()
                    .onSuccess { _, _, _ in
                        imageFailed = false
                    }
                    .onFailure { _ in
                        imageFailed = true
                    }
                    .aspectRatio(contentMode: .fill)
                    .frame(width: UIScreen.main.bounds.width, height: heroHeight)
                    .clipped()
            }

            // Gradient stays flush with the bottom edge of the image.
            heroBottomGradient
                .frame(maxWidth: .infinity, maxHeight: heroHeight)

            VStack(spacing: 10) {
                Text(author.name)
                    .font(.system(size: 34, weight: .bold))
                    .foregroundColor(.white)
                    .shadow(radius: 4)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                if !author.position.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(author.position.uppercased())
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 16)
            .padding(.bottom, 20 + heroTextLift)
        }
        .frame(width: UIScreen.main.bounds.width, height: heroHeight)
        .clipped()
    }

    private var authorArticlesSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Skrevet af \(firstName)")
                    .font(.system(size: 25, weight: .bold))
                    .foregroundStyle(.primary)

                Spacer()

                if authorArticles.count > previewArticles.count {
                    NavigationLink {
                        SimpleCategoryView(
                            title: "Skrevet af \(firstName)",
                            articles: authorArticles
                        )
                        .environmentObject(viewModel)
                    } label: {
                        Text("Se alle")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            .padding(.horizontal, 16)

            if previewArticles.isEmpty {
                Text("Ingen artikler endnu")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 16)
            } else {
                VStack(spacing: 12) {
                    ForEach(previewArticles) { article in
                        NavigationLink(value: article) {
                            AuthorArticleCardView(
                                article: article,
                                categoryText: viewModel.categories(for: article).first ?? "Artikel"
                            )
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }

    private var authorTopBar: some View {
        VStack(spacing: 0) {
            HStack {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(showGlassTopBar ? .primary : .white)
                        .frame(width: 36, height: 36)
                        .background(
                            Circle()
                                .fill(showGlassTopBar ? Color(.systemBackground).opacity(0.92) : Color.black.opacity(0.28))
                        )
                }
                .buttonStyle(.plain)

                Spacer()

                if showGlassTopBar {
                    Text(author.name)
                        .font(.headline)
                        .lineLimit(1)
                }

                Spacer()

                Color.clear.frame(width: 36, height: 36)
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 10)
            .background {
                if showGlassTopBar {
                    Rectangle()
                        .fill(.ultraThinMaterial)
                        .ignoresSafeArea(edges: .top)
                }
            }
        }
    }
}

/// Card layout matching `PodcastCardView`, without audio/AI chrome.
struct AuthorArticleCardView: View {
    let article: Article
    let categoryText: String

    @Environment(\.colorScheme) private var colorScheme

    private var cardBackground: Color {
        colorScheme == .dark ? Color.white.opacity(0.06) : Color.black.opacity(0.04)
    }

    private var artworkURL: URL? {
        article.listThumbnailURL ?? article.mobileImageURL ?? article.thumbURL ?? article.coverURL
    }

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            ZStack {
                ArticleImagePlaceholder(showShimmer: false, cornerRadius: 12)

                WebImage(url: artworkURL, options: [.retryFailed, .continueInBackground, .scaleDownLargeImages, .queryMemoryData])
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            }
            .frame(width: 92, height: 92)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            VStack(alignment: .leading, spacing: 6) {
                Text(categoryText.uppercased())
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Text(article.name ?? "Artikel")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)

                Spacer(minLength: 6)

                if let intro = article.intro?.trimmingCharacters(in: .whitespacesAndNewlines), !intro.isEmpty {
                    Text(intro)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 92, alignment: .leading)
        }
        .padding(12)
        .background(cardBackground)
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.white.opacity(colorScheme == .dark ? 0.18 : 0.12), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}
