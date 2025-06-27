//
//  PaywallOneView.swift
//  Native
//

import SwiftUI

struct PaywallOneView: View {
    
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
            .task {
                await fetchPlans()
            }
            .navigationStack()
    }
}

// MARK: - Item:

private extension PaywallOneView {
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

private extension PaywallOneView {
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
        featuresPlans
        PaywallLegalView()
    }
}

// MARK: - Features and plans:

private extension PaywallOneView {
    private var featuresPlans: some View {
        VStack(
            alignment: .leading,
            spacing: 32
        ) {
            featuresPlansContent
        }
    }
    
    @ViewBuilder
    private var featuresPlansContent: some View {
        PaywallOneFeaturesView()
        plansContent
    }
    
    private var plansContent: some View {
        PaywallOnePlansView(
            plans: plans,
            selectedPlanIdentifier: $selectedPlanIdentifier,
            isFetching: isFetching
        )
    }
}

// MARK: - Toolbar:

private extension PaywallOneView {
    private var toolbar: some View {
        BottomToolbarView(backgroundColor: backgroundColor) {
            toolbarContent
        }
    }
    
    @ViewBuilder
    private var toolbarContent: some View {
        notice
        startMyFreeTrialButton
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
    
    private var startMyFreeTrialButton: some View {
        ButtonView(
            title: "Start My Free Trial",
            isLoading: isFetching,
            isDisabled: isPlansEmpty,
            action: startFreeTrial
        )
    }
}

// MARK: - Preview:

#Preview {
    PaywallOneView()
}
