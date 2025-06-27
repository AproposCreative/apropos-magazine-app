//
//  PaywallElevenView.swift
//  Native
//

import SwiftUI

struct PaywallElevenView: View {
    
    // MARK: - Properties:
    
    /// An array of the pro plans to select from:
    @State var plans: [NT_ProPlan] = []
    
    /// Identifier of the pro plan that is currently selected:
    @State var selectedPlanIdentifier: String = ProPlanIdentifiers.monthly
    
    /// 'Bool' value indicating whether or not the data is currently being fetched:
    @State var isFetching: Bool = true
    
    // MARK: - Private properties:
    
    /// Dismisses the view:
    @Environment(\.dismiss) private var dismiss
    
    /// Feature that is currently shown:
    @State private var currentFeature: NT_Feature? = .latestTechnologies
    
    // MARK: - View:
    
    var body: some View {
        content
    }
    
    private var content: some View {
        item
            .background(backgroundGradient)
            .toolbarButton(
                title: "Restore",
                color: primaryColor,
                isLoading: isFetching,
                loadingIndicatorColor: secondaryColor,
                placement: .cancellationAction,
                action: restore
            )
            .toolbarButton(
                title: "Done",
                color: primaryColor,
                action: dismiss.callAsFunction
            )
            .toolbarBackground(
                .blueGradientStart,
                for: .navigationBar
            )
            .animation(
                .default,
                value: plans
            )
            .animation(
                .default,
                value: selectedPlanIdentifier
            )
            .animation(
                .default,
                value: isFetching
            )
            .animation(
                .default,
                value: currentFeature
            )
            .task {
                await fetchPlans()
            }
            .navigationStack()
            .darkColorScheme()
    }
}

// MARK: - Item:

private extension PaywallElevenView {
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

private extension PaywallElevenView {
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
            spacing: 16
        ) {
            scrollItemContent
        }
    }
    
    @ViewBuilder
    private var scrollItemContent: some View {
        imageTitleSubtitlePlansReviews
        legal
    }
}

// MARK: - Image, title, subtitle, plans, and reviews:

private extension PaywallElevenView {
    private var imageTitleSubtitlePlansReviews: some View {
        VStack(
            alignment: .leading,
            spacing: 32
        ) {
            imageTitleSubtitlePlansReviewsContent
        }
    }
    
    @ViewBuilder
    private var imageTitleSubtitlePlansReviewsContent: some View {
        imageContent
        titleSubtitle
        divider
        plansContent
        divider
        PaywallElevenReviewsView()
    }
    
    private var imageContent: some View {
        ImageBackgroundView(
            image: image,
            isResizable: false,
            isClipped: false,
            height: 344,
            isFullWidth: true,
            isShowingBackground: false,
            cornerRadius: 0
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
        Text("Supercharge Your iOS App Project 🚀")
            .font(.largeTitle.bold())
            .multilineTextAlignment(.leading)
            .foregroundStyle(primaryColor)
    }
    
    private var subtitle: some View {
        subtitleContent
            .font(.title3)
            .multilineTextAlignment(.leading)
            .foregroundStyle(secondaryColor)
    }
    
    private var subtitleContent: some View {
        Text("Library of free and premium resources to help you launch your next app quicker.")
    }
    
    private var plansContent: some View {
        PaywallElevenPlansView(
            plans: plans,
            selectedPlanIdentifier: $selectedPlanIdentifier,
            isFetching: isFetching
        )
    }
    
    private var divider: some View {
        DividerView(color: dividerColor)
    }
}

// MARK: - Legal:

private extension PaywallElevenView {
    private var legal: some View {
        PaywallLegalView(
            color: secondaryColor,
            dividerColor: dividerColor
        )
    }
}

// MARK: - Toolbar:

private extension PaywallElevenView {
    private var toolbar: some View {
        toolbarContent
            .environment(
                \.colorScheme,
                 .light
            )
    }
    
    private var toolbarContent: some View {
        BottomToolbarView() {
            toolbarItem
        }
    }
    
    @ViewBuilder
    private var toolbarItem: some View {
        notice
        startMyFreeTrialButton
    }
    
    private var notice: some View {
        noticeContent
            .font(.footnote)
            .multilineTextAlignment(.leading)
            .foregroundStyle(secondaryColor)
    }
    
    private var noticeContent: some View {
        Text("Plan will automatically renew unless cancelled at least 24 hours before the renewal date.")
    }
    
    private var startMyFreeTrialButton: some View {
        ButtonView(
            title: "Start My Free Trial",
            titleColor: .accent,
            isLoading: isFetching,
            backgroundColor: primaryColor,
            isBackgroundColorGradient: false,
            isDisabled: isPlansEmpty,
            action: startFreeTrial
        )
    }
}

// MARK: - Preview:

#Preview {
    PaywallElevenView()
}
