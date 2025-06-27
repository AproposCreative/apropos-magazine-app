//
//  NT_Setting.swift
//  Native
//

import SwiftUI

enum NT_Setting: Int {
    
    // MARK: - Cases:
    
    case accountDetails
    case fontSize
    case appearance
    case hapticFeedbacks
    case language
    case importCSVFile
    case importPDFFile
    case about
    case privacyAndSecurity
    case support
    case ourApps
    case shareTheApp
    
    // MARK: - Computed properties:
    
    /// Identifier of the setting:
    var id: Int {
        rawValue
    }
    
    /// Title of the setting:
    var title: String {
        switch self {
        case .accountDetails: return "Account Details"
        case .fontSize: return "Font Size"
        case .appearance: return "Appearance"
        case .hapticFeedbacks: return "Haptic Feedbacks"
        case .language: return "Language"
        case .importCSVFile: return "CSV File"
        case .importPDFFile: return "PDF File"
        case .about: return "About"
        case .privacyAndSecurity: return "Privacy and Security"
        case .support: return "Support"
        case .ourApps: return "Our Apps"
        case .shareTheApp: return "Share the App"
        }
    }
    
    /// Value of the setting:
    var value: String {
        switch self {
        case .accountDetails: return "John Smith"
        case .fontSize: return "Medium"
        case .appearance: return "System"
        case .hapticFeedbacks: return "Enabled"
        case .language: return "English"
        case .importCSVFile: return ""
        case .importPDFFile: return ""
        case .about: return "Learn more about us"
        case .privacyAndSecurity: return "Manage the permissions"
        case .support: return "Get help from us"
        case .ourApps: return "5 other apps"
        case .shareTheApp: return ""
        }
    }
    
    /// Color of the setting:
    var color: Color {
        switch self {
        case .accountDetails: return .blue
        case .fontSize: return .orange
        case .appearance: return .purple
        case .hapticFeedbacks: return .gray
        case .language: return .pink
        case .importCSVFile: return .blue
        case .importPDFFile: return .green
        case .about: return .purple
        case .privacyAndSecurity: return .green
        case .support: return .orange
        case .ourApps: return .pink
        case .shareTheApp: return .blue
        }
    }
    
    /// Starting color of the gradient of the setting:
    var gradientStart: Color {
        switch self {
        case .accountDetails: return .blueGradientStart
        case .fontSize: return .orangeGradientStart
        case .appearance: return .purpleGradientStart
        case .hapticFeedbacks: return .grayGradientStart
        case .language: return .pinkGradientStart
        case .importCSVFile: return .blueGradientStart
        case .importPDFFile: return .greenGradientStart
        case .about: return .purpleGradientStart
        case .privacyAndSecurity: return .greenGradientStart
        case .support: return .orangeGradientStart
        case .ourApps: return .pinkGradientStart
        case .shareTheApp: return .blueGradientStart
        }
    }
    
    /// Ending color of the gradient of the setting:
    var gradientEnd: Color {
        switch self {
        case .accountDetails: return .blueGradientEnd
        case .fontSize: return .orangeGradientEnd
        case .appearance: return .purpleGradientEnd
        case .hapticFeedbacks: return .grayGradientEnd
        case .language: return .pinkGradientEnd
        case .importCSVFile: return .blueGradientEnd
        case .importPDFFile: return .greenGradientEnd
        case .about: return .purpleGradientEnd
        case .privacyAndSecurity: return .greenGradientEnd
        case .support: return .orangeGradientEnd
        case .ourApps: return .pinkGradientEnd
        case .shareTheApp: return .blueGradientEnd
        }
    }
    
    /// Icon of the setting:
    var icon: String {
        switch self {
        case .accountDetails: return Icons.person
        case .fontSize: return Icons.textformat
        case .appearance: return Icons.paintbrush
        case .hapticFeedbacks: return Icons.handTap
        case .language: return Icons.globe
        case .importCSVFile: return Icons.docPlaintext
        case .importPDFFile: return Icons.docPlaintext
        case .about: return Icons.infoCircle
        case .privacyAndSecurity: return Icons.lock
        case .support: return Icons.personCropCircleBadgeQuestionmark
        case .ourApps: return Icons.app
        case .shareTheApp: return Icons.squareAndArrowUp
        }
    }
    
    /// 'Bool' value indicating whether or not the setting should be a toggle instead of a navigation link:
    var isToggle: Bool {
        switch self {
        case .accountDetails: return false
        case .fontSize: return false
        case .appearance: return false
        case .hapticFeedbacks: return true
        case .language: return false
        case .importCSVFile: return false
        case .importPDFFile: return false
        case .about: return false
        case .privacyAndSecurity: return false
        case .support: return false
        case .ourApps: return false
        case .shareTheApp: return false
        }
    }
    
    /// Section that the setting is a part of:
    var section: NT_SettingsSection {
        switch self {
        case .accountDetails,
                .fontSize,
                .appearance,
                .hapticFeedbacks,
                .language:
            return .customization
        case .importCSVFile,
                .importPDFFile:
            return .importSection
        case .about,
                .privacyAndSecurity,
                .support,
                .ourApps,
                .shareTheApp:
            return .other
        }
    }
}

// MARK: - Identifiable:

extension NT_Setting: Identifiable {  }

// MARK: - CaseIterable:

extension NT_Setting: CaseIterable {  }

// MARK: - Equatable:

extension NT_Setting: Equatable {  }

// MARK: - Hashable:

extension NT_Setting: Hashable {  }
