//
//  NT_AccountSettingsSection.swift
//  Native
//

import Foundation

enum NT_AccountSettingsSection: Int {
    
    // MARK: - Cases:
    
    case details
    case preferences
    case other
    
    // MARK: - Computed properties:
    
    /// Identifier of the section:
    var id: Int {
        rawValue
    }
    
    /// Title of the section:
    var title: String {
        switch self {
        case .details: return .init(localized: "Details")
        case .preferences: return .init(localized: "Preferences")
        case .other: return .init(localized: "Other")
        }
    }
    
    /// An array of the settings that are part of the section:
    var settings: [NT_AccountSetting] {
        NT_AccountSetting.allCases.filter { $0.section == self }
    }
}

// MARK: - Identifiable:

extension NT_AccountSettingsSection: Identifiable {  }

// MARK: - CaseIterable:

extension NT_AccountSettingsSection: CaseIterable {  }

// MARK: - Equatable:

extension NT_AccountSettingsSection: Equatable {  }

// MARK: - Hashable:

extension NT_AccountSettingsSection: Hashable {  }
