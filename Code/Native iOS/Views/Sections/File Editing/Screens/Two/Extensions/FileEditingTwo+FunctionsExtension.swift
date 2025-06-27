//
//  FileEditingTwo+FunctionsExtension.swift
//  Native
//

import Foundation

extension FileEditingTwoView {
    
    // MARK: - Functions:
    
    /// Returns the title of the given category:
    func title(_ category: NT_PhotoEditorCategory) -> String {
        category.title
    }
    
    /// Returns the icon of the given category:
    func icon(_ category: NT_PhotoEditorCategory) -> String {
        category.icon
    }
    
    /// Fetches the data to display:
    func fetchData() async {
        
        /// Firstly making the async task sleep for one second that is transformed into nanoseconds to simulate a network call (Please remove this code in production):
        try? await Task.sleep(nanoseconds: UInt64(1 * 1_000_000_000))
        
        /// Then updating the UI on the main thread:
        await MainActor.run {
            
            /// Then getting an array of the categories that are based on an array of the example categories:
            let categories: [NT_PhotoEditorCategory] = NT_PhotoEditorCategory.example
            
            /// Then assigning an array of the categories to display:
            self.categories = categories
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
