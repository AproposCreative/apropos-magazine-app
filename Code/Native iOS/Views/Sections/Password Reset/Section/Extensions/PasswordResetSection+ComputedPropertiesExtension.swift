//
//  PasswordResetSection+ComputedPropertiesExtension.swift
//  Native
//

import Foundation

extension PasswordResetSectionView {
    
    // MARK: - Computed properties:
    
    /// An array of the screens to display:
    var screens: [NT_PasswordResetScreen] {
        NT_PasswordResetScreen.allCases
    }
}
