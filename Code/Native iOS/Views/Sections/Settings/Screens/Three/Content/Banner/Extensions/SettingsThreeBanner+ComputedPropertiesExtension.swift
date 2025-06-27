//
//  SettingsThreeBanner+ComputedPropertiesExtension.swift
//  Native
//

import SwiftUI

extension SettingsThreeBannerView {
    
    // MARK: - Computed properties:
    
    /// Primary color of the view:
    var primaryColor: Color {
        .white
    }
    
    /// Secondary color of the view:
    var secondaryColor: Color {
        primaryColor.opacity(0.8)
    }
    
    /// Tertiary color of the view:
    var tertiaryColor: Color {
        primaryColor.opacity(0.6)
    }
    
    /// Size of the frame of the 'Dismiss' button that is based on the size of the dynamic type that is currently selected:
    var dismissFrame: CGFloat? {
        dynamicTypeSize >= .accessibility1 ? nil : 24
    }
}
