//
//  MainEightArticles+FunctionsExtension.swift
//  Native
//

import SwiftUI

extension MainEightArticlesView {
    
    // MARK: - Functions:
    
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
}
