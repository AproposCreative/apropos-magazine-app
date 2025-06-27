//
//  EmptyStateSection+ComputedPropertiesExtension.swift
//  Native
//

import Foundation

extension EmptyStateSectionView {
    
    // MARK: - Computed properties:
    
    /// An array of the screens to display:
    var screens: [NT_EmptyStateScreen] {
        NT_EmptyStateScreen.allCases
    }
}
