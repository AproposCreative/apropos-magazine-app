//
//  NT_SettingsSection.swift
//  Native
//

import Foundation

enum NT_SettingsSection: Int {
    
    // MARK: - Cases:
    
    case customization
    case importSection
    case other
    
    // MARK: - Computed properties:
    
    /// Identifier of the section:
    var id: Int {
        rawValue
    }
    
    /// Title of the section:
    var title: String {
        switch self {
        case .customization: return .init(localized: "Customization")
        case .importSection: return .init(localized: "Import")
        case .other: return .init(localized: "Other")
        }
    }
    
    /// An array of the settings that are part of the section:
    var settings: [NT_Setting] {
        NT_Setting.allCases.filter { $0.section == self }
    }
}

// MARK: - Identifiable:

extension NT_SettingsSection: Identifiable {  }

// MARK: - CaseIterable:

extension NT_SettingsSection: CaseIterable {  }

// MARK: - Equatable:

extension NT_SettingsSection: Equatable {  }

// MARK: - Hashable:

extension NT_SettingsSection: Hashable {  }
