//
//  NT_ProfileSetting.swift
//  Native
//

import SwiftUI

enum NT_ProfileSetting: Int {
    
    // MARK: - Cases:
    
    case accountDetails
    case billing
    case notifications
    case security
    case about
    
    // MARK: - Computed properties:
    
    /// Identifier of the setting:
    var id: Int {
        rawValue
    }
    
    /// Title of the setting:
    var title: String {
        switch self {
        case .accountDetails: return "Account Details"
        case .billing: return "Billing"
        case .notifications: return "Notifications"
        case .security: return "Security"
        case .about: return "About"
        }
    }
    
    /// Description of the setting:
    var description: String {
        switch self {
        case .accountDetails: return "Edit your name and email address"
        case .billing: return "Manage your plan"
        case .notifications: return "Manage your preferences"
        case .security: return "Update your password"
        case .about: return "Learn more about our app"
        }
    }
    
    /// Color of the setting:
    var color: Color {
        switch self {
        case .accountDetails: return .blue
        case .billing: return .orange
        case .notifications: return .purple
        case .security: return .pink
        case .about: return .green
        }
    }
    
    /// Starting color of the gradient of the setting:
    var gradientStart: Color {
        switch self {
        case .accountDetails: return .blueGradientStart
        case .billing: return .orangeGradientStart
        case .notifications: return .purpleGradientStart
        case .security: return .pinkGradientStart
        case .about: return .greenGradientStart
        }
    }
    
    /// Ending color of the gradient of the setting:
    var gradientEnd: Color {
        switch self {
        case .accountDetails: return .blueGradientEnd
        case .billing: return .orangeGradientEnd
        case .notifications: return .purpleGradientEnd
        case .security: return .pinkGradientEnd
        case .about: return .greenGradientEnd
        }
    }
    
    /// Icon of the setting:
    var icon: String {
        switch self {
        case .accountDetails: return Icons.person
        case .billing: return Icons.creditcard
        case .notifications: return Icons.bell
        case .security: return Icons.lock
        case .about: return Icons.infoCircle
        }
    }
}

// MARK: - Identifiable:

extension NT_ProfileSetting: Identifiable {  }

// MARK: - CaseIterable:

extension NT_ProfileSetting: CaseIterable {  }

// MARK: - Equatable:

extension NT_ProfileSetting: Equatable {  }

// MARK: - Hashable:

extension NT_ProfileSetting: Hashable {  }
