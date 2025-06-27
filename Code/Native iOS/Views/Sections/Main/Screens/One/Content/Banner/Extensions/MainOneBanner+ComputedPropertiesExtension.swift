//
//  MainOneBanner+ComputedPropertiesExtension.swift
//  Native
//

import Foundation

extension MainOneBannerView {
    
    // MARK: - Computed properties:
    
    /// Size of the frame of the 'Dismiss' button that is based on the size of the dynamic type that is currently selected:
    var dismissFrame: CGFloat? {
        dynamicTypeSize >= .accessibility1 ? nil : 24
    }
}
