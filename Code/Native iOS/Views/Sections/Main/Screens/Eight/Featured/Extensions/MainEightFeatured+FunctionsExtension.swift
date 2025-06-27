//
//  MainEightFeatured+FunctionsExtension.swift
//  Native
//

import SwiftUI

extension MainEightFeaturedView {
    
    // MARK: - Functions:
    
    /// Returns the title of the given article:
    func title(_ article: NT_BlogArticle) -> String {
        article.title
    }
    
    /// Returns the description of the given article:
    func description(_ article: NT_BlogArticle) -> String {
        article.description
    }
    
    /// Returns the title of the 'Bookmark' button that is based on whether or not the user has bookmarked the given article:
    func bookmarkTitle(_ article: NT_BlogArticle) -> String {
        isBookmarked(article) ? "Remove a Bookmark" : "Bookmark"
    }
    
    /// Returns the full image of the given article:
    func fullImage(_ article: NT_BlogArticle) -> Image {
        .init(article.fullImage)
    }
    
    /// Returns the symbol variant of the icon of the 'Bookmark' button that is based on whether or not the user has bookmarked the given article:
    func bookmarkIconSymbolVariant(_ article: NT_BlogArticle) -> SymbolVariants {
        isBookmarked(article) ? .fill : .none
    }
    
    /// Returns the scale effect of the content in the given phase (Needed to add the scroll transition when scrolling between the different features):
    nonisolated func scaleEffect(inPhase phase: ScrollTransitionPhase) -> Double {
        phase.isIdentity ? 1 : 0.8
    }
    
    /// Lets the user bookmark the given article:
    func bookmark(_ article: NT_BlogArticle) {
        
        /*
         
         NOTE: You can add your own logic for bookmarking the article here.
         
         */
        
    }
    
    // MARK: - Private functions:
    
    /// Returns a 'Bool' value indicating whether or not the given article is currently bookmarked by the user:
    private func isBookmarked(_ article: NT_BlogArticle) -> Bool {
        article.isBookmarked
    }
}
