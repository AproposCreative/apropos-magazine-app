//
//  DataVisualizationSection+ComputedPropertiesExtension.swift
//  Native
//

import Foundation

extension DataVisualizationSectionView {
    
    // MARK: - Computed properties:
    
    /// An array of the screens to display:
    var screens: [NT_DataVisualizationScreen] {
        NT_DataVisualizationScreen.allCases
    }
}
