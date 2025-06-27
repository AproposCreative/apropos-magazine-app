//
//  ProductDetailsThreeReviews+ComputedPropertiesExtension.swift
//  Native
//

import Foundation

extension ProductDetailsThreeReviewsView {
    
    // MARK: - Computed properties:
    
    /// An array of the reviews to display:
    var reviews: [NT_ProductReview] {
        product.reviews
    }
    
    /// 'Bool' value indicating whether or not the content of the view should be shown at all:
    var isShowing: Bool {
        !reviews.isEmpty
    }
    
    /// Spacing between the content of the view:
    var spacing: Double {
        16
    }
}
