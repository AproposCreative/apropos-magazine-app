//
//  PaywallTenReviews+ComputedPropertiesExtension.swift
//  Native
//

import Foundation

extension PaywallTenReviewsView {
    
    // MARK: - Computed properties:
    
    /// An array of the reviews to display:
    var reviews: [NT_Review] {
        NT_Review.allCases
    }
    
    /// Spacing between the content of the view:
    var spacing: Double {
        16
    }
}
