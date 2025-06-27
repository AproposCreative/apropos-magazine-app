//
//  MainEight+FunctionsExtension.swift
//  Native
//

import Foundation

extension MainEightView {
    
    // MARK: - Functions:
    
    /// Returns the title of the given article:
    func title(_ article: NT_BlogArticle) -> String {
        article.title
    }
    
    /// Returns the title of the given topic:
    func title(_ topic: NT_BlogTopic) -> String {
        topic.title
    }
    
    /// Fetches the data to display:
    func fetchData() async {
        
        /// Firstly making the async task sleep for one second that is transformed into nanoseconds to simulate a network call (Please remove this code in production):
        try? await Task.sleep(nanoseconds: UInt64(1 * 1_000_000_000))
        
        /// Then updating the UI on the main thread:
        await MainActor.run {
            
            /// Then getting an array of the featured articles that are based on an array of the example articles:
            let featuredArticles: [NT_BlogArticle] = NT_BlogArticle.example.filter { $0.isFeatured }
            
            /// Then assigning an array of the featured articles to display:
            self.featuredArticles = featuredArticles
            
            /// Then assigning the featured article that should be shown:
            currentFeaturedArticle = featuredArticles.first
            
            /// Then also getting an array of the articles that are based on an array of the example articles:
            let articles: [NT_BlogArticle] = NT_BlogArticle.example
            
            /// Then assigning an array of the articles to display:
            self.articles = articles
            
            /// Then also getting an array of the topics that are based on an array of the example topics:
            let topics: [NT_BlogTopic] = NT_BlogTopic.example
            
            /// Then assigning an array of the topics to display:
            self.topics = topics
        }
        
        /*
         
         NOTE: You can add your own logic for fetching the data here.
         
         */
        
        /// Lastly setting the 'isFetching' property to 'false' to stop fetching the data:
        updateIsFetching(false)
    }
    
    /// Shows the settings screen:
    func showSettings() {
        
        /*
         
         NOTE: You can add your own logic for showing the settings here.
         
         */
        
    }
    
    // MARK: - Private functions:
    
    /// Updates the 'isFetching' property with the given value:
    @MainActor
    private func updateIsFetching(_ isFetching: Bool) {
        
        /// Firstly making sure that the 'isFetching' property isn't the same as the given value:
        if self.isFetching != isFetching {
            
            /// If yes, then updating the 'isFetching' property with the given value:
            self.isFetching = isFetching
        }
    }
}
