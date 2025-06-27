//
//  SignUpSection+ComputedPropertiesExtension.swift
//  Native
//

import Foundation

extension SignUpSectionView {
    
    // MARK: - Computed properties:
    
    /// An array of the screens to display:
    var screens: [NT_SignUpScreen] {
        NT_SignUpScreen.allCases
    }
}
