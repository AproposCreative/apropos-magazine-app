//
//  PaywallElevenReviews+FunctionsExtension.swift
//  Native
//

import SwiftUI

extension PaywallElevenReviewsView {
    
    // MARK: - Functions:
    
    /// Returns the title of the given review:
    func title(_ review: NT_Review) -> String {
        review.title
    }
    
    /// Returns the subtitle of the given review:
    func subtitle(_ review: NT_Review) -> String {
        review.subtitle
    }
    
    /// Returns the image of the person who left the given review:
    func image(_ review: NT_Review) -> Image {
        .init(review.paywall10Image)
    }
    
    /// Returns the rating of the given review:
    func rating(_ review: NT_Review) -> Int {
        review.rating
    }
}
