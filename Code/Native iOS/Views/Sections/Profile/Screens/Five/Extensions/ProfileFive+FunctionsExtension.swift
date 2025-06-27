//
//  ProfileFive+FunctionsExtension.swift
//  Native
//

import Foundation

extension ProfileFiveView {
    
    // MARK: - Functions:
    
    /// Returns the title of the given article:
    func title(_ article: NT_BlogArticle) -> String {
        article.title
    }
    
    /// Fetches the data to display:
    func fetchData() async {
        
        /// Firstly making the async task sleep for one second that is transformed into nanoseconds to simulate a network call (Please remove this code in production):
        try? await Task.sleep(nanoseconds: UInt64(1 * 1_000_000_000))
        
        /// Then updating the UI on the main thread:
        await MainActor.run {
            
            /// Then getting the author to display the details for based on the example author:
            let author: NT_ProfileAuthor = .example
            
            /// Then assigning the author to display the details for:
            self.author = author
        }
        
        /*
         
         NOTE: You can add your own logic for fetching the data here.
         
         */
        
        /// Lastly setting the 'isFetching' property to 'false' to stop fetching the data:
        updateIsFetching(false)
    }
    
    /// Lets the user share the account:
    func share() {
        
        /*
         
         NOTE: You can add your own logic for sharing the account here.
         
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
