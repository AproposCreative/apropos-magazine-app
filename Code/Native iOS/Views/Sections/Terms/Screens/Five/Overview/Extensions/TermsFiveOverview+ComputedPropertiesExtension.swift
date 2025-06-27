//
//  TermsFiveOverview+ComputedPropertiesExtension.swift
//  Native
//

import Foundation

extension TermsFiveOverviewView {
    
    // MARK: - Computed properties:
    
    /// Size of the frame of each of the second icons of the overview items if applicable:
    var secondIconFrame: CGFloat? {
        dynamicTypeSize >= .accessibility1 ? nil : 22
    }
}
