//
//  FileEditingFourLayers+ComputedPropertiesExtension.swift
//  Native
//

import Foundation

extension FileEditingFourLayersView {
    
    // MARK: - Computed properties:
    
    /// An array of the layers that are part of the file to display:
    var layers: [NT_DesignToolLayer] {
        file.layers
    }
    
    /// Opacity of the 'No Layers' overlay:
    var noLayersOpacity: Double {
        layers.isEmpty ? 1 : 0
    }
}
