//
//  TermsTwoSections+ComputedPropertiesExtension.swift
//  Native
//

import Foundation

extension TermsTwoSectionsView {
    
    // MARK: - Computed properties:
    
    /// Size of the icon of each of the 'Expand' buttons that are displayed on the view:
    var expandButtonIconSize: NT_IconSize {
        .custom(
            font: .headline,
            nonBackgroundFont: .headline,
            frame: 25,
            cornerRadius: 0,
            cornerStyle: .continuous
        )
    }
}
