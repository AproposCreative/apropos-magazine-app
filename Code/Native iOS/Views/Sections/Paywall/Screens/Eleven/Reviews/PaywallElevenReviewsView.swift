//
//  PaywallElevenReviewsView.swift
//  Native
//

import SwiftUI

struct PaywallElevenReviewsView: View {
    
    // MARK: - View:
    
    var body: some View {
        content
    }
    
    private var content: some View {
        item
            .environment(
                \.colorScheme,
                 .light
            )
    }
}

// MARK: - Item:

private extension PaywallElevenReviewsView {
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
        header
        reviewsContent
    }
}

// MARK: - Header:

private extension PaywallElevenReviewsView {
    private var header: some View {
        SectionHeaderView(
            title: "Trusted by Millions of Users",
            titleColor: .white
        )
    }
}

// MARK: - Reviews:

private extension PaywallElevenReviewsView {
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
            backgroundColor: .init(.systemBackground)
        )
    }
}

// MARK: - Preview:

#Preview {
    ScrollView {
        PaywallElevenReviewsView()
    }
    .safeAreaPadding(
        .all,
        16
    )
    .safeAreaPadding(
        .bottom,
        16
    )
    .background(
        LinearGradient(
            colors: [
                .blueGradientStart,
                .blueGradientEnd
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    )
}
