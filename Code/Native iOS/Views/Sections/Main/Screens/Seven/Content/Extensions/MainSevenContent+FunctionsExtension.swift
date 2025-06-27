//
//  MainSevenContent+FunctionsExtension.swift
//  Native
//

import Foundation

extension MainSevenContentView {
    
    // MARK: - Functions:
    
    /// Returns the title of the given category:
    func title(_ category: NT_ProductsCategory) -> String {
        category.title
    }
    
    /// Fetches the data to display:
    func fetchData() async {
        
        /// Firstly making the async task sleep for one second that is transformed into nanoseconds to simulate a network call (Please remove this code in production):
        try? await Task.sleep(nanoseconds: UInt64(1 * 1_000_000_000))
        
        /// Then updating the UI on the main thread:
        await MainActor.run {
            
            /// Then getting an array of the products that are based on an array of the example products:
            let products: [NT_Product] = NT_Product.example
            
            /// Then assigning an array of the products to display:
            self.products = products
            
            /// Then also getting an array of the categories that are based on an array of the example categories:
            let categories: [NT_ProductsCategory] = NT_ProductsCategory.example
            
            /// Then assigning an array of the categories to display:
            self.categories = categories
        }
        
        /*
         
         NOTE: You can add your own logic for fetching the data here.
         
         */
        
        /// Lastly setting the 'isFetching' property to 'false' to stop fetching the data:
        updateIsFetching(false)
    }
    
    /// Shows the messages screen:
    func showMessages() {
        
        /*
         
         NOTE: You can add your own logic for showing the messages here.
         
         */
        
    }
    
    /// Shows the cart screen:
    func showCart() {
        
        /*
         
         NOTE: You can add your own logic for showing the cart here.
         
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
