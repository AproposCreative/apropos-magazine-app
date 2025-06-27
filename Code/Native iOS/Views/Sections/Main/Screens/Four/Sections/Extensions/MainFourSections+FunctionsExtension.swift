//
//  MainFourSections+FunctionsExtension.swift
//  Native
//

import SwiftUI

extension MainFourSectionsView {
    
    // MARK: - Functions:
    
    /// Returns an array of the articles that are part of the given section with the news:
    func articles(_ section: NT_NewsSection) -> [NT_NewsArticle] {
        section.articles
    }
    
    /// Returns a 'Bool' value indicating whether or not an array of the articles that are part of the given section with the news is empty:
    func isEmpty(_ section: NT_NewsSection) -> Bool {
        articles(section).isEmpty
    }
    
    /// 'Bool' value indicating whether or not the given section with the news displays the articles that were published today:
    func isToday(_ section: NT_NewsSection) -> Bool {
        section.isToday
    }
    
    /// Returns the title of the given section with the news:
    func title(_ section: NT_NewsSection) -> String {
        articles(section).first?.date.formatted(
            date: .complete,
            time: .omitted
        ) ?? ""
    }
    
    /// Returns the identifier of the given article:
    func identifier(_ article: NT_NewsArticle) -> String {
        article.id
    }
    
    /// Returns the title of the given article:
    func title(_ article: NT_NewsArticle) -> String {
        article.title
    }
    
    /// Returns the subtitle of the given article:
    func subtitle(_ article: NT_NewsArticle) -> String {
        article.subtitle
    }
    
    /// Returns the image of the given article:
    func image(_ article: NT_NewsArticle) -> Image {
        .init(article.image)
    }
}
