//
//  PaywallSixFeatures+ComputedPropertiesExtension.swift
//  Native
//

import Foundation

extension PaywallSixFeaturesView {
    
    // MARK: - Computed properties:
    
    /// An array of the features to display:
    var features: [NT_Feature] {
        NT_Feature.allCases
    }
}
