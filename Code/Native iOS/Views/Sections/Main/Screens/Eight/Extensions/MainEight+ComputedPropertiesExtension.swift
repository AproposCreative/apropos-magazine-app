//
//  MainEight+ComputedPropertiesExtension.swift
//  Native
//

import Foundation

extension MainEightView {
    
    // MARK: - Computed properties:
    
    /// An array of the featured articles that are filtered by the search text that is inputed by the user:
    var searchFeaturedArticles: [NT_BlogArticle] {
        featuredArticles.filter {
            isSearchTextEmpty
                ? true
                : $0.title.localizedCaseInsensitiveContains(searchText)
        }
    }
    
    /// An array of the articles that are filtered by the search text that is inputed by the user:
    var searchArticles: [NT_BlogArticle] {
        articles.filter {
            isSearchTextEmpty
                ? true
                : $0.title.localizedCaseInsensitiveContains(searchText)
        }
    }
    
    /// An array of the topics that are filtered by the search text that is inputed by the user:
    var searchTopics: [NT_BlogTopic] {
        topics.filter {
            isSearchTextEmpty
                ? true
                : $0.title.localizedCaseInsensitiveContains(searchText)
        }
    }
    
    /// Opacity of the loading indicator:
    var loadingOpacity: Double {
        isFetching ? 1 : 0
    }
    
    /// Opacity of the 'Nothing Here' overlay:
    var nothingHereOpacity: Double {
        isFetching || (
            !searchFeaturedArticles.isEmpty
            || !searchArticles.isEmpty
            || !searchTopics.isEmpty
        ) ? 0 : 1
    }
    
    // MARK: - Private computed properties:
    
    /// 'Bool' value indicating whether or not the text to search the articles and the topics by that is inputed the user is empty:
    private var isSearchTextEmpty: Bool {
        searchText.isEmpty
    }
}
