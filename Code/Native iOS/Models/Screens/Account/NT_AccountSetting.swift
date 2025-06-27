//
//  NT_AccountSetting.swift
//  Native
//

import SwiftUI

enum NT_AccountSetting: Int {
    
    // MARK: - Cases:
    
    case fullName
    case username
    case dateOfBirth
    case emailAddress
    case phone
    case password
    case notifications
    case blockedUsers
    case privacy
    case security
    case analytics
    case logOut
    
    // MARK: - Computed properties:
    
    /// Identifier of the setting:
    var id: Int {
        rawValue
    }
    
    /// Title of the setting:
    var title: String {
        switch self {
        case .fullName: return "Full Name"
        case .username: return "Username"
        case .dateOfBirth: return "Date of Birth"
        case .emailAddress: return "Email Address"
        case .phone: return "Phone"
        case .password: return "Password"
        case .notifications: return "Notifications"
        case .blockedUsers: return "Blocked Users"
        case .privacy: return "Privacy"
        case .security: return "Security"
        case .analytics: return "Analytics"
        case .logOut: return "Log Out"
        }
    }
    
    /// Value of the setting:
    var value: String {
        switch self {
        case .fullName: return "John Smith"
        case .username: return "@john.smith_123"
        case .dateOfBirth: return "19 July 1992"
        case .emailAddress: return "john.smith@email.com"
        case .phone: return "+1 (096) 348 089"
        case .password: return "**********"
        case .notifications: return "Enabled"
        case .blockedUsers: return "No users"
        case .privacy: return ""
        case .security: return ""
        case .analytics: return ""
        case .logOut: return ""
        }
    }
    
    /// Color of the setting:
    var color: Color {
        switch self {
        case .fullName: return .blue
        case .username: return .orange
        case .dateOfBirth: return .purple
        case .emailAddress: return .pink
        case .phone: return .green
        case .password: return .gray
        case .notifications: return .green
        case .blockedUsers: return .red
        case .privacy: return .blue
        case .security: return .green
        case .analytics: return .orange
        case .logOut: return .red
        }
    }
    
    /// Starting color of the gradient of the setting:
    var gradientStart: Color {
        switch self {
        case .fullName: return .blueGradientStart
        case .username: return .orangeGradientStart
        case .dateOfBirth: return .purpleGradientStart
        case .emailAddress: return .pinkGradientStart
        case .phone: return .greenGradientStart
        case .password: return .grayGradientStart
        case .notifications: return .greenGradientStart
        case .blockedUsers: return .redGradientStart
        case .privacy: return .blueGradientStart
        case .security: return .greenGradientStart
        case .analytics: return .orangeGradientStart
        case .logOut: return .redGradientStart
        }
    }
    
    /// Ending color of the gradient of the setting:
    var gradientEnd: Color {
        switch self {
        case .fullName: return .blueGradientEnd
        case .username: return .orangeGradientEnd
        case .dateOfBirth: return .purpleGradientEnd
        case .emailAddress: return .pinkGradientEnd
        case .phone: return .greenGradientEnd
        case .password: return .grayGradientEnd
        case .notifications: return .greenGradientEnd
        case .blockedUsers: return .redGradientEnd
        case .privacy: return .blueGradientEnd
        case .security: return .greenGradientEnd
        case .analytics: return .orangeGradientEnd
        case .logOut: return .redGradientEnd
        }
    }
    
    /// Icon of the setting:
    var icon: String {
        switch self {
        case .fullName: return Icons.person
        case .username: return Icons.at
        case .dateOfBirth: return Icons.calendar
        case .emailAddress: return Icons.envelope
        case .phone: return Icons.phone
        case .password: return Icons.key
        case .notifications: return Icons.bell
        case .blockedUsers: return Icons.xmarkCircle
        case .privacy: return Icons.handRaised
        case .security: return Icons.lock
        case .analytics: return Icons.chartPie
        case .logOut: return Icons.arrowRight
        }
    }
    
    /// 'Bool' value indicating whether or not the setting should be a toggle instead of a navigation link:
    var isToggle: Bool {
        switch self {
        case .fullName: return false
        case .username: return false
        case .dateOfBirth: return false
        case .emailAddress: return false
        case .phone: return false
        case .password: return false
        case .notifications: return true
        case .blockedUsers: return false
        case .privacy: return false
        case .security: return false
        case .analytics: return false
        case .logOut: return false
        }
    }
    
    /// Section that the setting is a part of:
    var section: NT_AccountSettingsSection {
        switch self {
        case .fullName,
                .username,
                .dateOfBirth,
                .emailAddress,
                .phone,
                .password:
            return .details
        case .notifications,
                .blockedUsers:
            return .preferences
        case .privacy,
                .security,
                .analytics,
                .logOut:
            return .other
        }
    }
}

// MARK: - Identifiable:

extension NT_AccountSetting: Identifiable {  }

// MARK: - CaseIterable:

extension NT_AccountSetting: CaseIterable {  }

// MARK: - Equatable:

extension NT_AccountSetting: Equatable {  }

// MARK: - Hashable:

extension NT_AccountSetting: Hashable {  }
