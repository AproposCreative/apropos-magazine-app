//
//  TermsSection+ComputedPropertiesExtension.swift
//  Native
//

import Foundation

extension TermsSectionView {
    
    // MARK: - Computed properties:
    
    /// An array of the screens to display:
    var screens: [NT_TermsScreen] {
        NT_TermsScreen.allCases
    }
}
