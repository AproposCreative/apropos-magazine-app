//
//  FileEditingSection+ComputedPropertiesExtension.swift
//  Native
//

import Foundation

extension FileEditingSectionView {
    
    // MARK: - Computed properties:
    
    /// An array of the screens to display:
    var screens: [NT_FileEditingScreen] {
        NT_FileEditingScreen.allCases
    }
}
