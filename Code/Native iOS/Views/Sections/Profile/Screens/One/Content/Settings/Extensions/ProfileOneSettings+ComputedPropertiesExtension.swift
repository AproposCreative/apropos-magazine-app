//
//  ProfileOneSettings+ComputedPropertiesExtension.swift
//  Native
//

import Foundation

extension ProfileOneSettingsView {
    
    // MARK: - Computed properties:
    
    /// An array of the settings to display:
    var settings: [NT_ProfileSetting] {
        NT_ProfileSetting.allCases
    }
    
    /// Size of the frame of each of the second icons of the settings that is based on the size of the dynamic type that is currently selected:
    var secondIconFrame: CGFloat? {
        dynamicTypeSize >= .accessibility1 ? nil : 22
    }
}
