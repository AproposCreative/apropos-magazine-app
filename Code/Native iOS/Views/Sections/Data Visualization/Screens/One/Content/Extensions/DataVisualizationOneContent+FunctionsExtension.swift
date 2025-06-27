//
//  DataVisualizationOneContent+FunctionsExtension.swift
//  Native
//

import Foundation

extension DataVisualizationOneContentView {
    
    // MARK: - Functions:
    
    /// Returns the title of the given overview item:
    func title(_ overviewItem: NT_Overview) -> String {
        overviewItem.title
    }
    
    /// Fetches the data to display:
    func fetchData() async {
        
        /// Firstly making the async task sleep for one second that is transformed into nanoseconds to simulate a network call (Please remove this code in production):
        try? await Task.sleep(nanoseconds: UInt64(1 * 1_000_000_000))
        
        /// Then updating the UI on the main thread:
        await MainActor.run {
            
            /// Then getting an array of the overview items that are based on an array of the example overview items:
            let overviewItems: [NT_Overview] = NT_Overview.example
            
            /// Then assigning an array of the overview items to display:
            self.overviewItems = overviewItems
            
            /// Then also getting an array of the data for the number of the active users that is based on an array of the example data:
            let activeUsersData: [NT_ActiveUsersData] = NT_ActiveUsersData.example
            
            /// Then assigning an array of the data for the number of the active users to display:
            self.activeUsersData = activeUsersData
            
            /// Then also getting an array of the data for the new downloads that is based on an array of the example data:
            let newDownloadsData: [NT_NewDownloadsData] = NT_NewDownloadsData.example
            
            /// Then assigning an array of the data for the new downloads to display:
            self.newDownloadsData = newDownloadsData
            
            /// Then also getting an array of the data for the reviews that is based on an array of the example data:
            let reviewsData: [NT_ReviewsData] = NT_ReviewsData.example
            
            /// Then assigning an array of the data for the reviews to display:
            self.reviewsData = reviewsData
            
            /// Then also getting an array of the data for the total number of users that is based on an array of the example data:
            let totalUsersData: [NT_TotalUsersData] = NT_TotalUsersData.example
            
            /// Then assigning an array of the data for the total number of users to display:
            self.totalUsersData = totalUsersData
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
