//
//  ProfileTwo+FunctionsExtension.swift
//  Native
//

import Foundation

extension ProfileTwoView {
    
    // MARK: - Functions:
    
    /// Fetches the data to display:
    func fetchData() async {
        
        /// Firstly making the async task sleep for one second that is transformed into nanoseconds to simulate a network call (Please remove this code in production):
        try? await Task.sleep(nanoseconds: UInt64(1 * 1_000_000_000))
        
        /// Then updating the UI on the main thread:
        await MainActor.run {
            
            /// Then getting the account to display the details for based on the example account:
            let account: NT_ProfileAccount = .example
            
            /// Then assigning the account to display the details for:
            self.account = account
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
