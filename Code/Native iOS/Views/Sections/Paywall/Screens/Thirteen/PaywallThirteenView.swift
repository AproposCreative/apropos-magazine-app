//
//  PaywallThirteenView.swift
//  Native
//

import SwiftUI

struct PaywallThirteenView: View {
    
    // MARK: - Properties:
    
    /// An actual pro plan that the users can purchase:
    @State var plan: NT_ProPlan? = nil
    
    /// 'Bool' value indicating whether or not the data is currently being fetched:
    @State var isFetching: Bool = true
    
    // MARK: - Private properties:
    
    /// Dismisses the view:
    @Environment(\.dismiss) private var dismiss
    
    // MARK: - View:
    
    var body: some View {
        content
    }
    
    private var content: some View {
        item
            .localizedNavigationTitle(
                title: "AppLayouts Pro",
                isLocalized: false
            )
            .toolbarButton(
                title: "Restore",
                isLoading: isFetching,
                placement: .cancellationAction,
                action: restore
            )
            .toolbarButton(
                title: "Done",
                action: dismiss.callAsFunction
            )
            .animation(
                .default,
                value: plan
            )
            .animation(
                .default,
                value: isFetching
            )
            .task {
                await fetchPlan()
            }
            .navigationStack()
    }
}

// MARK: - Item:

private extension PaywallThirteenView {
    private var item: some View {
        VStack(
            alignment: .leading,
            spacing: 0
        ) {
            itemContent
        }
    }
    
    @ViewBuilder
    private var itemContent: some View {
        scroll
        toolbar
    }
}

// MARK: - Scroll:

private extension PaywallThirteenView {
    private var scroll: some View {
        scrollContent
            .safeAreaPadding(
                .all,
                16
            )
            .safeAreaPadding(
                .bottom,
                16
            )
    }
    
    private var scrollContent: some View {
        ScrollView {
            scrollItem
        }
    }
    
    private var scrollItem: some View {
        VStack(
            alignment: .leading,
            spacing: 24
        ) {
            scrollItemContent
        }
    }
    
    @ViewBuilder
    private var scrollItemContent: some View {
        imageTitleSubtitleSocialProofReviews
        PaywallLegalView()
    }
}

// MARK: - Image, title, subtitle, social proof, and reviews:

private extension PaywallThirteenView {
    private var imageTitleSubtitleSocialProofReviews: some View {
        VStack(
            alignment: .leading,
            spacing: 32
        ) {
            imageTitleSubtitleSocialProofReviewsContent
        }
    }
    
    @ViewBuilder
    private var imageTitleSubtitleSocialProofReviewsContent: some View {
        imageContent
        titleSubtitle
        PaywallThirteenSocialProofView()
        PaywallThirteenReviewsView()
    }
    
    private var imageContent: some View {
        ImageBackgroundView(
            image: image,
            height: 344,
            alignment: .top,
            backgroundColor: .init(.secondarySystemBackground),
            isBackgroundColorGradient: false
        )
    }
    
    private var titleSubtitle: some View {
        titleSubtitleContent
            .accessibilityElement(children: .combine)
    }
    
    private var titleSubtitleContent: some View {
        VStack(
            alignment: .leading,
            spacing: 16
        ) {
            titleSubtitleItem
        }
    }
    
    @ViewBuilder
    private var titleSubtitleItem: some View {
        title
        subtitle
    }
    
    private var title: some View {
        titleContent
            .font(.largeTitle.bold())
            .multilineTextAlignment(.leading)
            .foregroundStyle(.primary)
    }
    
    private var titleContent: some View {
        Text("Supercharge Your \(Text("iOS App Project").foregroundStyle(titleGradient)) 🚀")
    }
    
    private var subtitle: some View {
        subtitleContent
            .font(.title3)
            .multilineTextAlignment(.leading)
            .foregroundStyle(.secondary)
    }
    
    private var subtitleContent: some View {
        Text("Library of free and premium resources to help you launch your next app quicker.")
    }
}

// MARK: - Toolbar:

private extension PaywallThirteenView {
    private var toolbar: some View {
        BottomToolbarView() {
            purchaseButton
        }
    }
    
    private var purchaseButton: some View {
        ButtonView(
            title: purchaseTitle,
            isLoading: isFetching,
            isDisabled: !isPlanAvailable,
            action: purchase
        )
    }
}

// MARK: - Preview:

#Preview {
    PaywallThirteenView()
}
