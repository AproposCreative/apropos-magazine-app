//
//  PaywallTwelveLegal+ComputedPropertiesExtension.swift
//  Native
//

import SwiftUI

extension PaywallTwelveLegalView {
    
    // MARK: - Computed properties:
    
    /// 'Bool' value indicating whether or not the content of the view should be moved that is based on the size of the dynamic type that is currently selected:
    var shouldMoveContent: Bool {
        dynamicTypeSize >= .accessibility1
    }
    
    /// Link to the page with the terms of service of the app (You can replace it with your own link):
    var termsOfServiceLink: URL {
        Links.termsOfService
    }
    
    /// Link to the page with the privacy policy of the app (You can replace it with your own link):
    var privacyPolicyLink: URL {
        Links.privacyPolicy
    }
    
    /// Spacing between the content of the view:
    var spacing: Double {
        12
    }
}
