//
//  DataVisualizationTwo+FunctionsExtension.swift
//  Native
//

import Foundation

extension DataVisualizationTwoView {
    
    // MARK: - Functions:
    
    /// Fetches the data to display:
    func fetchData() async {
        
        /// Firstly making the async task sleep for one second that is transformed into nanoseconds to simulate a network call (Please remove this code in production):
        try? await Task.sleep(nanoseconds: UInt64(1 * 1_000_000_000))
        
        /// Then updating the UI on the main thread:
        await MainActor.run {
            
            /// Then getting an array of the usage items that are based on an array of the example usage items:
            let usageItems: [NT_Usage] = NT_Usage.example
            
            /// Then assigning an array of the usage items to display:
            self.usageItems = usageItems
            
            /// Then getting an array of the performance items that are based on an array of the example performance items:
            let performanceItems: [NT_Performance] = NT_Performance.example
            
            /// Then assigning an array of the performance items to display:
            self.performanceItems = performanceItems
            
            /// Then assigning the performance item that should be shown currently:
            currentPerformanceItem = performanceItems.first
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
