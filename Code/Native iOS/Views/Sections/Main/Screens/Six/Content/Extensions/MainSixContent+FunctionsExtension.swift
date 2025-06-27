//
//  MainSixContent+FunctionsExtension.swift
//  Native
//

import Foundation

extension MainSixContentView {
    
    // MARK: - Functions:
    
    /// Returns the name of the given account:
    func name(_ account: NT_Account) -> String {
        account.name
    }
    
    /// Fetches the data to display:
    func fetchData() async {
        
        /// Firstly making the async task sleep for one second that is transformed into nanoseconds to simulate a network call (Please remove this code in production):
        try? await Task.sleep(nanoseconds: UInt64(1 * 1_000_000_000))
        
        /// Then updating the UI on the main thread:
        await MainActor.run {
            
            /// Then getting an array of the stories that are based on an array of the example stories:
            let stories: [NT_Story] = NT_Story.example
            
            /// Then assigning an array of the stories to display:
            self.stories = stories
            
            /// Then also getting an array of the posts that are based on an array of the example posts:
            let posts: [NT_Post] = NT_Post.example
            
            /// Then assigning an array of the posts to display:
            self.posts = posts
            
            /// Then also getting an array of the accounts that are based on an array of the example accounts:
            let accounts: [NT_Account] = NT_Account.example
            
            /// Then assigning an array of the accounts to display:
            self.accounts = accounts
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
