//
//  ProductDetailsFourKeyFeatures+FunctionsExtension.swift
//  Native
//

import Foundation

extension ProductDetailsFourKeyFeaturesView {
    
    // MARK: - Functions:
    
    /// Returns the title of the given key feature:
    func title(_ keyFeature: NT_ProductKeyFeature) -> String {
        keyFeature.title
    }
    
    /// Returns the value of the given key feature:
    func value(_ keyFeature: NT_ProductKeyFeature) -> String {
        keyFeature.value
    }
    
    /// Returns a 'Bool' value indicating whether or not the divider should be displayed at the top of the given key feature:
    func isShowingTopDivider(_ keyFeature: NT_ProductKeyFeature) -> Bool {
        keyFeatures.first == keyFeature
    }
}
