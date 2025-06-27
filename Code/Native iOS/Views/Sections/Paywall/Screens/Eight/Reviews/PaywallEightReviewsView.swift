//
//  PaywallEightReviewsView.swift
//  Native
//

import SwiftUI

struct PaywallEightReviewsView: View {
    
    // MARK: - View:
    
    var body: some View {
        content
    }
    
    private var content: some View {
        VStack(
            alignment: .leading,
            spacing: 16
        ) {
            item
        }
    }
}

// MARK: - Item:

private extension PaywallEightReviewsView {
    @ViewBuilder
    private var item: some View {
        SectionHeaderView(title: "Trusted by Millions of Users")
        reviewsContent
    }
}

// MARK: - Reviews:

private extension PaywallEightReviewsView {
    private var reviewsContent: some View {
        ForEach(
            reviews,
            content: review
        )
    }
    
    private func review(_ review: NT_Review) -> some View {
        ImageTitleSubtitleRatingView(
            image: image(review),
            title: title(review),
            subtitle: subtitle(review),
            rating: rating(review)
        )
    }
}

// MARK: - Preview:

#Preview {
    ScrollView {
        PaywallEightReviewsView()
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
}
