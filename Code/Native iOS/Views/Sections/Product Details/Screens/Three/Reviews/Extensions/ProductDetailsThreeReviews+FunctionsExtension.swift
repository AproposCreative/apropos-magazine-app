//
//  ProductDetailsThreeReviews+FunctionsExtension.swift
//  Native
//

import SwiftUI

extension ProductDetailsThreeReviewsView {
    
    // MARK: - Functions:
    
    /// Returns the title of the given review:
    func title(_ review: NT_ProductReview) -> String {
        review.title
    }
    
    /// Returns the content of the given review:
    func content(_ review: NT_ProductReview) -> String {
        review.content
    }
    
    /// Returns the image of the person who left the given review:
    func image(_ review: NT_ProductReview) -> Image {
        .init(review.image)
    }
    
    /// Returns the rating of the given review:
    func rating(_ review: NT_ProductReview) -> Int {
        review.rating
    }
}
