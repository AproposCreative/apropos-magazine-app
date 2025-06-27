//
//  PaywallOnePlansView.swift
//  Native
//

import SwiftUI

struct PaywallOnePlansView: View {
    
    // MARK: - Properties:
    
    /// Identifier of the pro plan that is currently selected:
    @Binding var selectedPlanIdentifier: String
    
    /// An array of the pro plans to display:
    let plans: [NT_ProPlan]
    
    // MARK: - Private properties:
    
    /// 'Bool' value indicating whether or not the data is currently being fetched:
    private let isFetching: Bool
    
    init(
        plans: [NT_ProPlan],
        selectedPlanIdentifier: Binding<String>,
        isFetching: Bool
    ) {
        
        /// Properties initialization:
        self.plans = plans
        _selectedPlanIdentifier = selectedPlanIdentifier
        self.isFetching = isFetching
    }
    
    // MARK: - View:
    
    var body: some View {
        content
    }
    
    @ViewBuilder
    private var content: some View {
        if !isEmpty {
            item
        } else if isFetching {
            loading
        }
    }
}

// MARK: - Item:

private extension PaywallOnePlansView {
    private var item: some View {
        VStack(
            alignment: .leading,
            spacing: 16
        ) {
            itemContent
        }
    }
    
    @ViewBuilder
    private var itemContent: some View {
        SectionHeaderView(title: "Pick a Plan that Suits You")
        plansContent
    }
}

// MARK: - Loading:

private extension PaywallOnePlansView {
    private var loading: some View {
        loadingContent
            .frame(
                maxWidth: .infinity,
                alignment: .center
            )
    }
    
    private var loadingContent: some View {
        LoadingView(
            isShowing: isEmpty,
            color: .secondary,
            scale: 1.5
        )
    }
}

// MARK: - Plans:

private extension PaywallOnePlansView {
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
    
    ScrollView {
        PaywallOnePlansView(
            plans: NT_ProPlan.examplePlans,
            selectedPlanIdentifier: $selectedPlanIdentifier,
            isFetching: false
        )
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
