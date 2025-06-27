//
//  PaywallTwelveView.swift
//  Native
//

import SwiftUI

struct PaywallTwelveView: View {
    
    // MARK: - Properties:
    
    /// An array of the pro plans to select from:
    @State var plans: [NT_ProPlan] = []
    
    /// Identifier of the pro plan that is currently selected:
    @State var selectedPlanIdentifier: String = ProPlanIdentifiers.monthly
    
    /// 'Bool' value indicating whether or not the data is currently being fetched:
    @State var isFetching: Bool = true
    
    /// 'Bool' value indicating whether or not the screen with all of the pro plans that are available for purchase is currently presented:
    @State var isAllPlansPresented: Bool = false
    
    // MARK: - Private properties:
    
    /// Dismisses the view:
    @Environment(\.dismiss) private var dismiss
    
    /// Main feature that is currently shown:
    @State private var currentMainFeature: NT_Feature? = .latestTechnologies
    
    // MARK: - View:
    
    var body: some View {
        content
    }
    
    private var content: some View {
        item
            .background(backgroundColor)
            .localizedNavigationTitle(
                title: "AppLayouts Pro",
                isLocalized: false
            )
            .toolbarButton(
                title: "Dismiss",
                icon: Icons.xmarkCircle,
                color: .init(.tertiaryLabel),
                style: .iconOnly,
                placement: .cancellationAction,
                action: dismiss.callAsFunction
            )
            .sheet(
                isPresented: $isAllPlansPresented,
                content: plansContent
            )
            .animation(
                .default,
                value: plans
            )
            .animation(
                .default,
                value: isFetching
            )
            .animation(
                .default,
                value: currentMainFeature
            )
            .task {
                await fetchPlans()
            }
            .navigationStack()
    }
}

// MARK: - Item:

private extension PaywallTwelveView {
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

private extension PaywallTwelveView {
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
            spacing: 32
        ) {
            scrollItemContent
        }
    }
    
    @ViewBuilder
    private var scrollItemContent: some View {
        mainFeaturesContent
        DividerView()
        PaywallTwelveAdditionalFeaturesView()
    }
}

// MARK: - Main features:

private extension PaywallTwelveView {
    private var mainFeaturesContent: some View {
        PaywallTwelveMainFeaturesView(
            features: mainFeatures,
            currentFeature: $currentMainFeature
        )
    }
}

// MARK: - Toolbar:

private extension PaywallTwelveView {
    private var toolbar: some View {
        BottomToolbarView(
            horizontalAlignment: .center,
            backgroundColor: backgroundColor
        ) {
            toolbarContent
        }
    }
    
    @ViewBuilder
    private var toolbarContent: some View {
        pagination
        startMyFreeTrialViewAllPlansLegalButtons
        notice
    }
    
    private var pagination: some View {
        PaginationView(
            current: $currentMainFeature,
            all: mainFeatures
        )
    }
    
    private var startMyFreeTrialViewAllPlansLegalButtons: some View {
        VStack(
            alignment: .leading,
            spacing: 8
        ) {
            startMyFreeTrialViewAllPlansLegalButtonsContent
        }
    }
    
    @ViewBuilder
    private var startMyFreeTrialViewAllPlansLegalButtonsContent: some View {
        startMyFreeTrialButton
        viewAllPlansButton
        PaywallTwelveLegalView(isFetching: isFetching)
    }
    
    private var startMyFreeTrialButton: some View {
        ButtonView(
            title: "Start My Free Trial",
            isLoading: isFetching,
            isDisabled: isPlansEmpty,
            action: startFreeTrial
        )
    }
    
    private var viewAllPlansButton: some View {
        ButtonView(
            title: "View All Plans",
            titleColor: .primary,
            isLoading: isFetching,
            loadingIndicatorColor: .secondary,
            backgroundColor: .init(.secondarySystemGroupedBackground),
            isBackgroundColorGradient: false,
            isDisabled: isPlansEmpty,
            action: showAllPlans
        )
    }
    
    private var notice: some View {
        noticeContent
            .font(.footnote)
            .multilineTextAlignment(.leading)
            .foregroundStyle(.secondary)
    }
    
    private var noticeContent: some View {
        Text("Plan will automatically renew unless cancelled at least 24 hours before the renewal date.")
    }
}

// MARK: - Plans:

private extension PaywallTwelveView {
    private func plansContent() -> some View {
        PaywallTwelvePlansView(
            plans: plans,
            selectedPlanIdentifier: $selectedPlanIdentifier
        )
    }
}

// MARK: - Preview:

#Preview {
    PaywallTwelveView()
}
