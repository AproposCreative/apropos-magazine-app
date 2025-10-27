//
//  ProfileView_NewDesign.swift
//  AproposMagazinev2
//
//  New Instagram-style profile design
//  Based on DetailsPro design
//

import SwiftUI

struct ProfileView_NewDesign: View {
    @EnvironmentObject var viewModel: ArticleViewModel
    @Environment(\.colorScheme) var colorScheme
    
    // User profile data
    @State private var userName = "Apropos Reader"
    @State private var userBio = "Exploring culture, music, and art through Apropos Magazine 📚"
    @State private var userWebsite = "aproposmagazine.com"
    
    // Stats
    private var readArticlesCount: Int {
        // Count articles that have been read (you can implement this logic)
        return viewModel.articles.count // For now, using total articles
    }
    
    private var favoriteArticlesCount: Int {
        return viewModel.favorites.count
    }
    
    private var totalArticlesCount: Int {
        return viewModel.articles.count
    }
    
    var body: some View {
        ScrollView {
            VStack {
                // Header with username and settings
                HStack {
                    Text(userName)
                        .font(.system(.headline, weight: .medium))
                    
                    Spacer()
                    
                    Button(action: {
                        // Settings action
                    }) {
                        Image(systemName: "line.3.horizontal")
                            .font(.system(.headline, weight: .medium))
                    }
                }
                .padding(.horizontal)
                
                // Profile Picture
                Image(systemName: "person.circle.fill")
                    .font(.system(size: 100))
                    .foregroundColor(.blue)
                    .clipShape(RoundedRectangle(cornerRadius: 67, style: .continuous))
                
                // Stats Row
                HStack(spacing: 4) {
                    VStack {
                        Text("\(totalArticlesCount)")
                            .font(.system(.headline, weight: .semibold))
                        Text("Articles")
                            .font(.footnote)
                    }
                    .frame(width: 80)
                    
                    VStack {
                        Text("\(readArticlesCount)")
                            .font(.system(.headline, weight: .semibold))
                        Text("Read")
                            .font(.footnote)
                    }
                    .frame(width: 80)
                    
                    VStack {
                        Text("\(favoriteArticlesCount)")
                            .font(.system(.headline, weight: .semibold))
                        Text("Saved")
                            .font(.footnote)
                    }
                    .frame(width: 80)
                }
                .padding()
                
                // Bio Section
                VStack(spacing: 4) {
                    Text(userName)
                        .font(.headline)
                    
                    Text(userBio)
                        .font(.subheadline)
                        .multilineTextAlignment(.center)
                    
                    Text(userWebsite)
                        .underline()
                        .foregroundStyle(.blue)
                        .font(.subheadline)
                }
                .frame(width: 250)
                
                // Content Type Selector
                HStack {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())]) {
                        Image(systemName: "photo")
                            .foregroundStyle(.blue)
                        Image(systemName: "bookmark")
                            .foregroundStyle(.secondary)
                        Image(systemName: "heart")
                            .foregroundStyle(.secondary)
                    }
                }
                .foregroundStyle(.secondary)
                .font(.title2)
                .padding(.top, 40)
                .padding(.bottom, 8)
                .padding(.horizontal, 4)
                
                // Articles Grid
                LazyVGrid(columns: [
                    GridItem(.flexible(), spacing: 1), 
                    GridItem(.flexible(), spacing: 1), 
                    GridItem(.flexible(), spacing: 1)
                ], spacing: 1) {
                    ForEach(Array(viewModel.articles.prefix(9)), id: \.id) { article in
                        NavigationLink(destination: ArticleDetailView(article: article).environmentObject(viewModel)) {
                            ArticleThumbnailView(article: article)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 20)
            .padding(.bottom, 100)
        }
        .navigationBarHidden(true)
    }
}

// MARK: - Article Thumbnail View
struct ArticleThumbnailView: View {
    let article: Article
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        var mutableArticle = article
        let thumbnailURL = mutableArticle.thumbnailURL
        
        AsyncImage(url: URL(string: thumbnailURL)) { image in
            image
                .resizable()
                .aspectRatio(contentMode: .fill)
        } placeholder: {
            Rectangle()
                .fill(Color.gray.opacity(0.3))
                .overlay(
                    Image(systemName: "photo")
                        .foregroundColor(.gray)
                        .font(.title2)
                )
        }
        .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
        .aspectRatio(1/1, contentMode: .fit)
        .clipped()
    }
}

// MARK: - Preview
#Preview {
    NavigationView {
        ProfileView_NewDesign()
            .environmentObject(ArticleViewModel())
    }
}
