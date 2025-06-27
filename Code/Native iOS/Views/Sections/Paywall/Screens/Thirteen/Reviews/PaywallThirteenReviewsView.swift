//
//  PaywallThirteenReviewsView.swift
//  Native
//

import SwiftUI

struct PaywallThirteenReviewsView: View {
    
    // MARK: - View:
    
    var body: some View {
        content
    }
    
    private var content: some View {
        VStack(
            alignment: .leading,
            spacing: spacing
        ) {
            item
        }
    }
}

// MARK: - Item:

private extension PaywallThirteenReviewsView {
    @ViewBuilder
    private var item: some View {
        SectionHeaderView(title: "Trusted by Millions of Users")
        reviewsContent
    }
}

// MARK: - Reviews:

private extension PaywallThirteenReviewsView {
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
    
    private func review(_ review: NT_Review) -> some View {
        ImageTitleSubtitleRatingView(
            image: image(review),
            title: title(review),
            subtitle: subtitle(review),
            rating: rating(review),
            backgroundColor: .init(.secondarySystemBackground)
        )
    }
}

// MARK: - Preview:

#Preview {
    ScrollView {
        PaywallThirteenReviewsView()
    }
    .safeAreaPadding(
        .all,
        16
    )
    .safeAreaPadding(
        .bottom,
        16
    )
}
