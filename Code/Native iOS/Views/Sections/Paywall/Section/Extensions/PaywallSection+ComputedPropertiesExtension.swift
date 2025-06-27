//
//  PaywallSection+ComputedPropertiesExtension.swift
//  Native
//

import Foundation

extension PaywallSectionView {
    
    // MARK: - Computed properties:
    
    /// An array of the screens to display:
    var screens: [NT_PaywallScreen] {
        NT_PaywallScreen.allCases
    }
}
