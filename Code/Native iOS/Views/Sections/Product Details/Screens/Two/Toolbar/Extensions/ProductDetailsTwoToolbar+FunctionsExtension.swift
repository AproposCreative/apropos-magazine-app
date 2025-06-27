//
//  ProductDetailsTwoToolbar+FunctionsExtension.swift
//  Native
//

import SwiftUI

extension ProductDetailsTwoToolbarView {
    
    // MARK: - Functions:
    
    /// Returns the title of the given configuration option:
    func title(_ configuration: NT_ProductConfiguration) -> String {
        configuration.title
    }
    
    /// Returns the description of the given configuration option:
    func description(_ configuration: NT_ProductConfiguration) -> String {
        configuration.description
    }
    
    /// Returns a 'Bool' value indicating whether or not the given configuration option is currently selected:
    func isSelected(_ configuration: NT_ProductConfiguration) -> Bool {
        selectedConfiguration == configuration
    }
    
    /// Returns the color of the border of the given configuration option:
    func borderColor(_ configuration: NT_ProductConfiguration) -> Color {
        isSelected(configuration) ? .accent : .init(.systemFill)
    }
    
    /// Returns the width of the border of the given configuration option that is based on whether or not it's currently selected:
    func borderWidth(_ configuration: NT_ProductConfiguration) -> Double {
        isSelected(configuration) ? 2 : 1
    }
    
    /// Selects the given configuration option unless it's already selected:
    func select(_ configuration: NT_ProductConfiguration) {
        
        /// Firstly making sure that the given configuration option isn't already selected:
        if !isSelected(configuration) {
            
            /// If yes, then selecting the given configuration option by updating the 'selectedConfiguration' property with the given configuration option:
            selectedConfiguration = configuration
            
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
