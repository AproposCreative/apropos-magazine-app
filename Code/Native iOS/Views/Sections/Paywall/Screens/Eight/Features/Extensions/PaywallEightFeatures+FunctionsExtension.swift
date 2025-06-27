//
//  PaywallEightFeatures+FunctionsExtension.swift
//  Native
//

import Foundation

extension PaywallEightFeaturesView {
    
    // MARK: - Functions:
    
    /// Returns the title of the given feature:
    func title(_ feature: NT_Feature) -> String {
        feature.title
    }
    
    /// Returns the subtitle of the given feature:
    func subtitle(_ feature: NT_Feature) -> String {
        feature.subtitle
    }
    
    /// Returns the icon of the given feature:
    func icon(_ feature: NT_Feature) -> String {
        feature.icon
    }
}
