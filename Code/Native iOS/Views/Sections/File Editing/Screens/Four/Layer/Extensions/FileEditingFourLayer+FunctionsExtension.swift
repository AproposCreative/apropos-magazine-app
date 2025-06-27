//
//  FileEditingFourLayer+FunctionsExtension.swift
//  Native
//

import Foundation

extension FileEditingFourLayerView {
    
    // MARK: - Functions:
    
    /// Selects the layer unless it's already selected:
    func select() {
        
        /// Firstly making sure that the layer isn't already selected:
        if !isSelected {
            
            /// If yes, then selecting the layer by updating the 'selectedLayer' property with the layer:
            selectedLayer = layer
        }
    }
}
