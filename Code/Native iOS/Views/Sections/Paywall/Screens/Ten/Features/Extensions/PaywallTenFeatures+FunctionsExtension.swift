//
//  PaywallTenFeatures+FunctionsExtension.swift
//  Native
//

import SwiftUI

extension PaywallTenFeaturesView {
    
    // MARK: - Functions:
    
    /// Returns the title of the given feature:
    func title(_ feature: NT_Feature) -> String {
        feature.title
    }
    
    /// Returns the subtitle of the given feature:
    func subtitle(_ feature: NT_Feature) -> String {
        feature.subtitle
    }
    
    /// Returns the starting color of the gradient of the given feature if applicable:
    func gradientStart(_ feature: NT_Feature) -> Color {
        .init(feature.gradientStart)
    }
    
    /// Returns the ending color of the gradient of the given feature if applicable:
    func gradientEnd(_ feature: NT_Feature) -> Color {
        .init(feature.gradientEnd)
    }
    
    /// Returns the icon of the given feature:
    func icon(_ feature: NT_Feature) -> String {
        feature.icon
    }
}
