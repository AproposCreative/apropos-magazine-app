//
//  CategoryDetailView.swift
//  AproposMagazinev2
//
//  Created by AI Assistant on 04/09/2025.
//  Category detail view for displaying articles in a specific category
//

import SwiftUI

struct CategoryDetailView: View {
    let categoryName: String
    @EnvironmentObject var viewModel: ArticleViewModel
    @Environment(\.navigationCoordinator) private var navigationCoordinator
    
    private var articlesInCategory: [Article] {
        viewModel.articles.filter { article in
            let topicName = viewModel.topics.first(where: { $0.id == article.topicID })?.name ?? ""
            return topicName == categoryName
        }
    }
    
    var body: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                ForEach(articlesInCategory) { article in
                    Button(action: {
                        navigationCoordinator.navigateToArticle(article, in: .categories)
                    }) {
                        ArticleCardView_Enhanced(
                            article: article,
                            isFavorite: viewModel.favorites.contains(article)
                        ) { article in
                            viewModel.toggleFavorite(for: article)
                        }
                        .padding(.horizontal, 16)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            .padding(.top, 16)
        }
        .navigationTitle(categoryName)
        .navigationBarTitleDisplayMode(.large)
    }
}

struct CategoryDetailView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
            CategoryDetailView(categoryName: "Anmeldelser")
                .environmentObject(ArticleViewModel())
        }
    }
}
