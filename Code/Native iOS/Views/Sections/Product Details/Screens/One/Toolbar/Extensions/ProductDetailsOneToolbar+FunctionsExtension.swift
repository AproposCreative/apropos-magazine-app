//
//  ProductDetailsOneToolbar+FunctionsExtension.swift
//  Native
//

import SwiftUI

extension ProductDetailsOneToolbarView {
    
    // MARK: - Functions:
    
    /// Returns the title of the given storage option:
    func title(_ storage: NT_ProductStorage) -> String {
        storage.title
    }
    
    /// Returns a 'Bool' value indicating whether or not the given storage option is currently selected:
    func isSelected(_ storage: NT_ProductStorage) -> Bool {
        selectedStorage == storage
    }
    
    /// Returns the color of the border of the given storage option:
    func borderColor(_ storage: NT_ProductStorage) -> Color {
        isSelected(storage) ? .accent : .init(.systemFill)
    }
    
    /// Returns the width of the border of the given storage option that is based on whether or not it's currently selected:
    func borderWidth(_ storage: NT_ProductStorage) -> Double {
        isSelected(storage) ? 2 : 1
    }
    
    /// Selects the given storage option unless it's already selected:
    func select(_ storage: NT_ProductStorage) {
        
        /// Firstly making sure that the given storage option isn't already selected:
        if !isSelected(storage) {
            
            /// If yes, then selecting the given storage option by updating the 'selectedStorage' property with the given storage option:
            selectedStorage = storage
            
            /// Lastly triggering the selection changed haptic feedback indicating that there was a change:
            HapticFeedbacks.selectionChanged()
        }
    }
    
    /// Lets the user buy the product:
    func buy() {
        
        /*
         
         NOTE: You can add your own logic for buying the product here.
         
         */
        
    }
}
