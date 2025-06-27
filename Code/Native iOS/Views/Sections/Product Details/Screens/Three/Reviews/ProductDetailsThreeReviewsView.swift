//
//  ProductDetailsThreeReviewsView.swift
//  Native
//

import SwiftUI

struct ProductDetailsThreeReviewsView: View {
    
    // MARK: - Properties:
    
    /// An actual product to display the details for:
    let product: NT_Product
    
    init(product: NT_Product) {
        
        /// Properties initialization:
        self.product = product
    }
    
    // MARK: - View:
    
    var body: some View {
        content
    }
    
    @ViewBuilder
    private var content: some View {
        if isShowing {
            item
        }
    }
}

// MARK: - Item:

private extension ProductDetailsThreeReviewsView {
    private var item: some View {
        VStack(
            alignment: .leading,
            spacing: spacing
        ) {
            itemContent
        }
    }
    
    @ViewBuilder
    private var itemContent: some View {
        SectionHeaderView(title: "Reviews")
        reviewsContent
    }
}

// MARK: - Reviews:

private extension ProductDetailsThreeReviewsView {
    private var reviewsContent: some View {
        VStack(
            alignment: .leading,
            spacing: spacing
        ) {
            reviewsItem
        }
    }
    
    private var reviewsItem: some View {
        ForEach(
            reviews,
            content: review
        )
    }
    
    private func review(_ review: NT_ProductReview) -> some View {
        ImageTitleSubtitleRatingView(
            image: image(review),
            title: title(review),
            subtitle: content(review),
            rating: rating(review)
        )
    }
}

// MARK: - Preview:

#Preview {
    ScrollView {
        ProductDetailsThreeReviewsView(product: .example.first!)
    }
    .safeAreaPadding(
        .all,
        16
    )
    .safeAreaPadding(
        .bottom,
        16
    )
    .background(Color(.systemGroupedBackground))
    .localizedNavigationTitle(title: "Product Details")
    .navigationStack()
}
