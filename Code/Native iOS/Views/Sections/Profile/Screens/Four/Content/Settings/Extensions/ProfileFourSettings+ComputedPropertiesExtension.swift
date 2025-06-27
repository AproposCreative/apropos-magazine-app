//
//  ProfileFourSettings+ComputedPropertiesExtension.swift
//  Native
//

import Foundation

extension ProfileFourSettingsView {
    
    // MARK: - Computed properties:
    
    /// An array of the settings to display:
    var settings: [NT_ProfileSetting] {
        NT_ProfileSetting.allCases
    }
}
