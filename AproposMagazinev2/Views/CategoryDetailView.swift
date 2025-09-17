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
                        ArticleRowCompact(article: article)
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
