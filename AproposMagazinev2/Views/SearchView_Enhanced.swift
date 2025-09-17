import SwiftUI
import SDWebImageSwiftUI

struct SearchView_Enhanced: View {
    @EnvironmentObject var viewModel: ArticleViewModel
    @Environment(\.navigationCoordinator) private var navigationCoordinator
    @Environment(\.colorScheme) var colorScheme
    @State private var scrollOffset: CGFloat = 0
    @State private var showNavTitle = false
    
    var body: some View {
        ScrollView(.vertical, showsIndicators: true) {
            VStack(spacing: 0) {
                GeometryReader { geo in
                    Rectangle()
                        .fill(.clear)
                        .preference(key: ScrollOffsetKey.self, value: geo.frame(in: .named("scroll")).minY)
                }
                .frame(height: 0)

                // Large title - shown only at top
                if !showNavTitle {
                    Text("Alle Artikler")
                        .font(.largeTitle.bold())
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 16)
                        .padding(.top, 16)
                        .padding(.bottom, 12)
                        .transition(.opacity)
                }

                // Article list
                if viewModel.isLoading {
                    shimmerPlaceholder
                } else if viewModel.fetchError != nil {
                    EmptyStateView(
                        icon: "exclamationmark.triangle.fill",
                        title: "Kunne ikke hente artikler",
                        subtitle: "Tjek din internetforbindelse, og prøv igen.",
                        actionTitle: "Prøv igen"
                    ) {
                        viewModel.fetchArticles()
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, showNavTitle ? 12 : 0)
                } else {
                    VStack(spacing: 0) {
                        ForEach(viewModel.articles) { article in
                            Button(action: {
                                navigationCoordinator.navigateToArticle(article, in: .search)
                            }) {
                                ArticleRowCompact(article: article)
                            }
                            .buttonStyle(PlainButtonStyle())
                            
                            if article.id != viewModel.articles.last?.id {
                                Divider()
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 8)
                            }
                        }
                    }
                    .padding(.top, showNavTitle ? 12 : 0)
                }
                
                Spacer(minLength: 80)
            }
        }
        .coordinateSpace(name: "scroll")
        .onPreferenceChange(ScrollOffsetKey.self) { value in
            withAnimation(.easeInOut(duration: 0.2)) {
                showNavTitle = value < -40
            }
        }
        .scrollableModernTopBar(
            title: "Alle Artikler",
            showNavTitle: $showNavTitle,
            showSearchButton: true,
            showMenuButton: true,
            onSearch: {
                // Search functionality
                print("Search tapped")
            },
            onMenu: {
                // Menu functionality
                print("Menu tapped")
            }
        )
        .navigationTitle(showNavTitle ? "Alle Artikler" : "")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            showNavTitle = false
        }
    }
    
    private var shimmerPlaceholder: some View {
        VStack(spacing: 0) {
            ForEach(0..<6, id: \.self) { index in
                ListItemSkeleton()
                
                if index < 5 {
                    Divider()
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                }
            }
        }
        .padding(.top, showNavTitle ? 12 : 0)
    }
}

// MARK: - Preview
struct SearchView_Enhanced_Previews: PreviewProvider {
    static var previews: some View {
        SearchView_Enhanced()
            .environmentObject(ArticleViewModel())
            .environment(\.navigationCoordinator, NavigationCoordinator())
    }
} 
