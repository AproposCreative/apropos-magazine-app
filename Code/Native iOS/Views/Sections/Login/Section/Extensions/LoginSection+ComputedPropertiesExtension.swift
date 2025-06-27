//
//  LoginSection+ComputedPropertiesExtension.swift
//  Native
//

import Foundation

extension LoginSectionView {
    
    // MARK: - Computed properties:
    
    /// An array of the screens to display:
    var screens: [NT_LoginScreen] {
        NT_LoginScreen.allCases
    }
}
