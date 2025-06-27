//
//  AccountSection+ComputedPropertiesExtension.swift
//  Native
//

import Foundation

extension AccountSectionView {
    
    // MARK: - Computed properties:
    
    /// An array of the screens to display:
    var screens: [NT_AccountScreen] {
        NT_AccountScreen.allCases
    }
}
