//
//  ProfileFiveArticles+FunctionsExtension.swift
//  Native
//

import SwiftUI

extension ProfileFiveArticlesView {
    
    // MARK: - Functions:
    
    /// Returns an array of the articles that are based on the given type:
    func articles(_ type: NT_ProfileAuthorArticleType) -> [NT_BlogArticle] {
        author.articles.filter {
            switch type {
            case .all: return true
            case .featured: return $0.isFeatured
            case .latest: return $0.publishedDate.isThisMonth
            }
        }
    }
    
    /// Returns the title of the given type of the articles:
    func title(_ type: NT_ProfileAuthorArticleType) -> String {
        type.title + " " + "(\(articles(type).count))"
    }
    
    /// Returns the title of the given article:
    func title(_ article: NT_BlogArticle) -> String {
        article.title
    }
    
    /// Returns the category of the given article:
    func category(_ article: NT_BlogArticle) -> String {
        article.category
    }
    
    /// Returns the image of the given article:
    func image(_ article: NT_BlogArticle) -> Image {
        .init(article.image)
    }
    
    /// Method that gets called whenever the type of the articles changes:
    func articleTypeOnChange(
        _ previousType: NT_ProfileAuthorArticleType,
        _ newType: NT_ProfileAuthorArticleType
    ) {
        
        /// Triggering the selection changed haptic feedback indicating that there was a change:
        HapticFeedbacks.selectionChanged()
    }
}
