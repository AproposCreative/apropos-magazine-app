//
//  FileEditingFourLayers+FunctionsExtension.swift
//  Native
//

import Foundation

extension FileEditingFourLayersView {
    
    // MARK: - Functions:
    
    /// Returns the name of the given layer:
    func name(_ layer: NT_DesignToolLayer) -> String {
        layer.name
    }
    
    /// Returns the icon of the given layer:
    func icon(_ layer: NT_DesignToolLayer) -> String {
        layer.icon
    }
    
    /// Returns a 'Bool' value indicating whether or not the given layer is currently selected:
    func isSelected(_ layer: NT_DesignToolLayer) -> Bool {
        selectedLayer == layer
    }
    
    /// Selects the given layer unless it's already selected:
    func select(_ layer: NT_DesignToolLayer) {
        
        /// Firstly making sure that the given layer isn't already selected:
        if !isSelected(layer) {
            
            /// If yes, then selecting the given layer by updating the 'selectedLayer' property with the given layer:
            selectedLayer = layer
            
            /// Then dismissing the view after selecting the layer:
            dismiss()
            
            /// Lastly triggering the selection changed haptic feedback indicating that there was a change:
            HapticFeedbacks.selectionChanged()
        }
    }
}
