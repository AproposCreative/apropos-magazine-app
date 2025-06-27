//
//  SettingsSection+ComputedPropertiesExtension.swift
//  Native
//

import Foundation

extension SettingsSectionView {
    
    // MARK: - Computed properties:
    
    /// An array of the screens to display:
    var screens: [NT_SettingsScreen] {
        NT_SettingsScreen.allCases
    }
}
