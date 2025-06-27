//
//  OnboardingFifteen+ComputedPropertiesExtension.swift
//  Native
//

import Foundation

extension OnboardingFifteenView {
    
    // MARK: - Computed properties:
    
    /// 'Bool' value indicating whether or not the dark color scheme is currently selected:
    var isDarkColorScheme: Bool {
        colorScheme == .dark
    }
    
    /// 'Bool' value indicating whether or not the content of the view should be moved that is based on the size of the dynamic type that is currently selected:
    var shouldMoveContent: Bool {
        dynamicTypeSize >= .accessibility1
    }
    
    /// An array of the features to display:
    var features: [NT_Feature] {
        .init(NT_Feature.allCases.prefix(4))
    }
    
    /// Link to the page with the terms of service of the app (You can replace it with your own link):
    var termsOfServiceLink: URL {
        Links.termsOfService
    }
    
    /// Spacing between the buttons:
    var buttonsSpacing: Double {
        8
    }
}
