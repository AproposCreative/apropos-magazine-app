//
//  PaywallFiveFeatures+ComputedPropertiesExtension.swift
//  Native
//

import Foundation

extension PaywallFiveFeaturesView {
    
    // MARK: - Computed properties:
    
    /// An array of the features to display:
    var features: [NT_Feature] {
        .init(NT_Feature.allCases.prefix(3))
    }
}
