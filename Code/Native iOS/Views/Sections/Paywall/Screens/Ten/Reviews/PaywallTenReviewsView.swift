//
//  PaywallTenReviewsView.swift
//  Native
//

import SwiftUI

struct PaywallTenReviewsView: View {
    
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

private extension PaywallTenReviewsView {
    @ViewBuilder
    private var item: some View {
        SectionHeaderView(title: "Trusted by Millions of Users")
        reviewsContent
    }
}

// MARK: - Reviews:

private extension PaywallTenReviewsView {
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
        PaywallTenReviewsView()
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
