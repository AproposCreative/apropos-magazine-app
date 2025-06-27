//
//  NT_Feature.swift
//  Native
//

import SwiftUI

enum NT_Feature: Int {
    
    // MARK: - Cases:
    
    case latestTechnologies
    case nativeDesign
    case reusableComponents
    case globalStyleguide
    case fullyAccessible
    case scalableSourceCode
    
    // MARK: - Computed properties:
    
    /// Identifier of the feature:
    var id: Int {
        rawValue
    }
    
    /// Title of the feature:
    var title: String {
        switch self {
        case .latestTechnologies: return "Latest Technologies"
        case .nativeDesign: return "Native Design"
        case .reusableComponents: return "Reusable Components"
        case .globalStyleguide: return "Global Styleguide"
        case .fullyAccessible: return "Fully Accessible"
        case .scalableSourceCode: return "Scalable Source Code"
        }
    }
    
    /// Subtitle of the feature:
    var subtitle: String {
        switch self {
        case .latestTechnologies: return "All of our resources are built with the latest first-party technologies that are offered by Apple."
        case .nativeDesign: return "We always try our best to design our resources with the Apple’s Human Interface Guidelines in mind."
        case .reusableComponents: return "Take advantage of countless coded UI components that you can easily reuse across your different projects."
        case .globalStyleguide: return "You can effortlessly customize the design files for our resources with just a few clicks."
        case .fullyAccessible: return "Our resources support both dark mode and dynamic type offering the full accessibility for the users."
        case .scalableSourceCode: return "Easily build upon the source code that is provided with our resources and take your iOS app project to the whole new level."
        }
    }
    
    /// Color of the feature:
    var color: Color {
        switch self {
        case .latestTechnologies: return .blue
        case .nativeDesign: return .orange
        case .reusableComponents: return .purple
        case .globalStyleguide: return .pink
        case .fullyAccessible: return .green
        case .scalableSourceCode: return .gray
        }
    }
    
    /// Starting color of the gradient of the feature if applicable:
    var gradientStart: Color {
        switch self {
        case .latestTechnologies: return .blueGradientStart
        case .nativeDesign: return .orangeGradientStart
        case .reusableComponents: return .purpleGradientStart
        case .globalStyleguide: return .pinkGradientStart
        case .fullyAccessible: return .greenGradientStart
        case .scalableSourceCode: return .grayGradientStart
        }
    }
    
    /// Ending color of the gradient of the feature if applicable:
    var gradientEnd: Color {
        switch self {
        case .latestTechnologies: return .blueGradientEnd
        case .nativeDesign: return .orangeGradientEnd
        case .reusableComponents: return .purpleGradientEnd
        case .globalStyleguide: return .pinkGradientEnd
        case .fullyAccessible: return .greenGradientEnd
        case .scalableSourceCode: return .grayGradientEnd
        }
    }
    
    /// Icon of the feature:
    var icon: String {
        switch self {
        case .latestTechnologies: return Icons.chevronLeftForwardslashChevronRight
        case .nativeDesign: return Icons.paintbrush
        case .reusableComponents: return Icons.rectangleStack
        case .globalStyleguide: return Icons.pencilAndRuler
        case .fullyAccessible: return Icons.person
        case .scalableSourceCode: return Icons.docText
        }
    }
    
    /// Image of the feature on the second onboarding screen (Only applicable to some of the screens and features):
    var onboarding2Image: String {
        switch self {
        case .latestTechnologies: return Images.onboarding21
        case .nativeDesign: return Images.onboarding22
        case .reusableComponents: return Images.onboarding23
        case .globalStyleguide: return Images.onboarding21
        case .fullyAccessible: return Images.onboarding21
        case .scalableSourceCode: return Images.onboarding21
        }
    }
    
    /// Image of the feature on the sixth onboarding screen (Only applicable to some of the screens and features):
    var onboarding6Image: String {
        switch self {
        case .latestTechnologies: return Images.onboarding61
        case .nativeDesign: return Images.onboarding62
        case .reusableComponents: return Images.onboarding63
        case .globalStyleguide: return Images.onboarding64
        case .fullyAccessible: return Images.onboarding61
        case .scalableSourceCode: return Images.onboarding61
        }
    }
    
    /// Image of the feature on the eighth onboarding screen (Only applicable to some of the screens and features):
    var onboarding8Image: String {
        switch self {
        case .latestTechnologies: return Images.onboarding81
        case .nativeDesign: return Images.onboarding82
        case .reusableComponents: return Images.onboarding83
        case .globalStyleguide: return Images.onboarding81
        case .fullyAccessible: return Images.onboarding81
        case .scalableSourceCode: return Images.onboarding81
        }
    }
    
    /// Image of the feature on the twelfth onboarding screen (Only applicable to some of the screens and features):
    var onboarding12Image: String {
        switch self {
        case .latestTechnologies: return Images.onboarding121
        case .nativeDesign: return Images.onboarding122
        case .reusableComponents: return Images.onboarding123
        case .globalStyleguide: return Images.onboarding121
        case .fullyAccessible: return Images.onboarding121
        case .scalableSourceCode: return Images.onboarding121
        }
    }
    
    /// Image of the feature on the thirteenth onboarding screen (Only applicable to some of the screens and features):
    var onboarding13Image: String {
        switch self {
        case .latestTechnologies: return Images.onboarding131
        case .nativeDesign: return Images.onboarding132
        case .reusableComponents: return Images.onboarding131
        case .globalStyleguide: return Images.onboarding131
        case .fullyAccessible: return Images.onboarding131
        case .scalableSourceCode: return Images.onboarding131
        }
    }
    
    /// Image of the feature on the fifteenth onboarding screen (Only applicable to some of the screens and features):
    var onboarding15Image: String {
        switch self {
        case .latestTechnologies: return Images.onboarding151
        case .nativeDesign: return Images.onboarding152
        case .reusableComponents: return Images.onboarding153
        case .globalStyleguide: return Images.onboarding154
        case .fullyAccessible: return Images.onboarding151
        case .scalableSourceCode: return Images.onboarding151
        }
    }
    
    /// Image of the feature on the third paywall screen (Only applicable to some of the screens and features):
    var paywall3Image: String {
        switch self {
        case .latestTechnologies: return Images.paywall31
        case .nativeDesign: return Images.paywall32
        case .reusableComponents: return Images.paywall33
        case .globalStyleguide: return Images.paywall31
        case .fullyAccessible: return Images.paywall31
        case .scalableSourceCode: return Images.paywall31
        }
    }
    
    /// Image of the feature on the twelfth paywall screen (Only applicable to some of the screens and features):
    var paywall12Image: String {
        switch self {
        case .latestTechnologies: return Images.paywall121
        case .nativeDesign: return Images.paywall122
        case .reusableComponents: return Images.paywall123
        case .globalStyleguide: return Images.paywall121
        case .fullyAccessible: return Images.paywall121
        case .scalableSourceCode: return Images.paywall121
        }
    }
    
    /// Alignment of the image of the feature that is needed to fit its content properly:
    var imageAlignment: Alignment {
        switch self {
        case .latestTechnologies: return .top
        case .nativeDesign: return .top
        case .reusableComponents: return .center
        case .globalStyleguide: return .bottom
        case .fullyAccessible: return .top
        case .scalableSourceCode: return .top
        }
    }
    
    /// Title of the badge of the feature:
    var badgeTitle: String {
        switch self {
        case .latestTechnologies: return "Scalable"
        case .nativeDesign: return "Customizable"
        case .reusableComponents: return "Efficient"
        case .globalStyleguide: return ""
        case .fullyAccessible: return ""
        case .scalableSourceCode: return ""
        }
    }
}

// MARK: - Identifiable:

extension NT_Feature: Identifiable {  }

// MARK: - CaseIterable:

extension NT_Feature: CaseIterable {  }

// MARK: - Equatable:

extension NT_Feature: Equatable {  }

// MARK: - Hashable:

extension NT_Feature: Hashable {  }
