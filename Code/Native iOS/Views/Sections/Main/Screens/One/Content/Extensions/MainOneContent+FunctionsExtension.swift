//
//  MainOneContent+FunctionsExtension.swift
//  Native
//

import Foundation

extension MainOneContentView {
    
    // MARK: - Functions:
    
    /// Returns the title of the given account:
    func title(_ account: NT_TransactionsAccount) -> String {
        account.title
    }
    
    /// Fetches the data to display:
    func fetchData() async {
        
        /// Firstly making the async task sleep for one second that is transformed into nanoseconds to simulate a network call (Please remove this code in production):
        try? await Task.sleep(nanoseconds: UInt64(1 * 1_000_000_000))
        
        /// Then updating the UI on the main thread:
        await MainActor.run {
            
            /// Then getting an array of the accounts that are based on an array of the example accounts:
            let accounts: [NT_TransactionsAccount] = NT_TransactionsAccount.example
            
            /// Then assigning an array of the accounts to display:
            self.accounts = accounts
            
            /// Then also getting an array of the bars to display in the chart that are based on an array of the example bars:
            let bars: [NT_ChartBar] = NT_ChartBar.example
            
            /// Then assigning an array of the bars to display in the chart:
            self.bars = bars
        }
        
        /*
         
         NOTE: You can add your own logic for fetching the data here.
         
         */
        
        /// Lastly setting the 'isFetching' property to 'false' to stop fetching the data:
        updateIsFetching(false)
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
