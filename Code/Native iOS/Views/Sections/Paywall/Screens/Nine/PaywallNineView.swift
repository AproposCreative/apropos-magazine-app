//
//  PaywallNineView.swift
//  Native
//

import SwiftUI

struct PaywallNineView: View {
    
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
    
    /// Level of the pro plan that is currently selected:
    @State private var planLevel: NT_ProPlanLevel = .starter
    
    // MARK: - View:
    
    var body: some View {
        content
    }
    
    private var content: some View {
        item
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
            .onChange(
                of: planLevel,
                planLevelOnChange
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

private extension PaywallNineView {
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

private extension PaywallNineView {
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
        titleSubtitleFeaturesPlans
        PaywallLegalView()
    }
}

// MARK: - Title, subtitle, features, and plans:

private extension PaywallNineView {
    private var titleSubtitleFeaturesPlans: some View {
        VStack(
            alignment: .leading,
            spacing: 32
        ) {
            titleSubtitleFeaturesPlansContent
        }
    }
    
    @ViewBuilder
    private var titleSubtitleFeaturesPlansContent: some View {
        titleSubtitle
        PaywallNineFeaturesView()
        plansContent
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
    
    private var plansContent: some View {
        PaywallNinePlansView(
            plans: plans,
            selectedLevel: $planLevel,
            selectedPlanIdentifier: $selectedPlanIdentifier,
            isFetching: isFetching
        )
    }
}

// MARK: - Toolbar:

private extension PaywallNineView {
    private var toolbar: some View {
        BottomToolbarView() {
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
    PaywallNineView()
}
