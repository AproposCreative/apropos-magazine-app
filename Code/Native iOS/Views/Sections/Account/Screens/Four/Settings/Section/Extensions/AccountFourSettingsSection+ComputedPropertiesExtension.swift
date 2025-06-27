//
//  AccountFourSettingsSection+ComputedPropertiesExtension.swift
//  Native
//

import Foundation

extension AccountFourSettingsSectionView {
    
    // MARK: - Computed properties:
    
    /// An array of the settings that are part of the section to display:
    var settings: [NT_AccountSetting] {
        section.settings
    }
    
    /// Title of the section:
    var title: String {
        section.title
    }
}
