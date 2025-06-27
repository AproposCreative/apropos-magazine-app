//
//  PaywallTwelvePlansView.swift
//  Native
//

import SwiftUI

struct PaywallTwelvePlansView: View {
    
    // MARK: - Properties:
    
    /// Dismisses the view:
    @Environment(\.dismiss) var dismiss
    
    /// Identifier of the pro plan that is currently selected:
    @Binding var selectedPlanIdentifier: String
    
    /// An array of the pro plans to display:
    let plans: [NT_ProPlan]
    
    init(
        plans: [NT_ProPlan],
        selectedPlanIdentifier: Binding<String>
    ) {
        
        /// Properties initialization:
        self.plans = plans
        _selectedPlanIdentifier = selectedPlanIdentifier
    }
    
    // MARK: - View:
    
    var body: some View {
        content
    }
    
    private var content: some View {
        scroll
            .background(Color(.systemGroupedBackground))
            .localizedNavigationTitle(title: "All Plans")
            .toolbarButton(
                title: "Done",
                action: dismiss.callAsFunction
            )
            .animation(
                .default,
                value: selectedPlanIdentifier
            )
            .navigationStack()
            .presentationDetents([.medium])
    }
}

// MARK: - Scroll:

private extension PaywallTwelvePlansView {
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
            plansContent
        }
    }
}

// MARK: - Plans:

private extension PaywallTwelvePlansView {
    private var plansContent: some View {
        ForEach(
            plans,
            content: plan
        )
    }
    
    private func plan(_ plan: NT_ProPlan) -> some View {
        SelectButtonTitleSubtitleBadgeView(
            isSelected: isSelected(plan),
            title: title(plan),
            subtitle: price(plan),
            isShowingBadge: isShowingBadge(plan),
            badgeTitle: "Most Popular"
        ) {
            select(plan)
        }
    }
}

// MARK: - Preview:

#Preview {
    @Previewable @State var selectedPlanIdentifier: String = ProPlanIdentifiers.monthly
    
    PaywallTwelvePlansView(
        plans: NT_ProPlan.examplePlans,
        selectedPlanIdentifier: $selectedPlanIdentifier
    )
}
