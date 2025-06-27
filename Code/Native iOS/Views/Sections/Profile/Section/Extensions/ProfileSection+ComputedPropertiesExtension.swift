//
//  ProfileSection+ComputedPropertiesExtension.swift
//  Native
//

import Foundation

extension ProfileSectionView {
    
    // MARK: - Computed properties:
    
    /// An array of the screens to display:
    var screens: [NT_ProfileScreen] {
        NT_ProfileScreen.allCases
    }
}
