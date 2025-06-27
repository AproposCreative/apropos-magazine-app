//
//  FileEditingFour+FunctionsExtension.swift
//  Native
//

import Foundation

extension FileEditingFourView {
    
    // MARK: - Functions:
    
    /// Shows the screen with all of the layers of the file:
    func showLayers() {
        
        /// Showing the screen with all of the layers of the file by setting the 'isLayersPresented' property to 'true':
        isLayersPresented = true
    }
    
    /// Lets the users add a new layer of the given type to the canvas:
    func addNewLayer(_ type: NT_DesignToolLayerType) {
        
        /*
         
         NOTE: You can add your own logic for adding a new layer here.
         
         */
        
    }
    
    /// Lets the user group the layers:
    func group() {
        
        /*
         
         NOTE: You can add your own logic for grouping the layers here.
         
         */
        
    }
    
    /// Lets the user customize the layers:
    func customize() {
        
        /*
         
         NOTE: You can add your own logic for customizing the layers here.
         
         */
        
    }
    
    /// Lets the user select the layers:
    func select() {
        
        /*
         
         NOTE: You can add your own logic for selecting the layers here.
         
         */
        
    }
    
    /// Lets the user generate the layers with AI:
    func generate() {
        
        /*
         
         NOTE: You can add your own logic for generating the layers here.
         
         */
        
    }
}

// MARK: - Layers:

extension FileEditingFourView {
    
    // MARK: - Functions:
    
    /// Returns the title of the given type of the layer:
    func title(_ type: NT_DesignToolLayerType) -> String {
        type.title
    }
    
    /// Returns the icon of the given type of the layer:
    func icon(_ type: NT_DesignToolLayerType) -> String {
        type.icon
    }
    
    /// Flattens multiple arrays of the given layers and their sub-layers and then returns a single array of all of the layers:
    func flattenLayers(_ layers: [NT_DesignToolLayer]) -> [NT_DesignToolLayer] {
        
        /// Firstly creating an array of all of the layers to return:
        var allLayers: [NT_DesignToolLayer] = []
        
        /// Then iterating through an array of the given layers:
        for layer in layers {
            
            /// Then appending the given layer into an array of all of the layers to return:
            allLayers.append(layer)
            
            /// Then also checking whether or not the given layer has the sub-layers that are part of it:
            if let sublayers: [NT_DesignToolLayer] = layer.sublayers {
                
                /// If yes, then incrementing an array of all of the layers by calling this method again with an array of the given sub-layers:
                allLayers += flattenLayers(sublayers)
            }
        }
        
        /// Finally returning an array of all of the layers:
        return allLayers
    }
}
