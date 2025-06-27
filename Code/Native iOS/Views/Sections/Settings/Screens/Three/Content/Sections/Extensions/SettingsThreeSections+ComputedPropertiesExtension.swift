//
//  SettingsThreeSections+ComputedPropertiesExtension.swift
//  Native
//

import Foundation

extension SettingsThreeSectionsView {
    
    // MARK: - Computed properties:
    
    /// An array of the sections with the settings to display:
    var sections: [NT_SettingsSection] {
        NT_SettingsSection.allCases
    }
}
