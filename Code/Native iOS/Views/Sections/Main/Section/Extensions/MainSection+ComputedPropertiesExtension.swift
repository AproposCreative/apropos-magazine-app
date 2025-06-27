//
//  MainSection+ComputedPropertiesExtension.swift
//  Native
//

import Foundation

extension MainSectionView {
    
    // MARK: - Computed properties:
    
    /// An array of the screens to display:
    var screens: [NT_MainScreen] {
        NT_MainScreen.allCases
    }
}
