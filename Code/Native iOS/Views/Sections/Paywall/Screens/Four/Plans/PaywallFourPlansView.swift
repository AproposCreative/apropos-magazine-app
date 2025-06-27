//
//  PaywallFourPlansView.swift
//  Native
//

import SwiftUI

struct PaywallFourPlansView: View {
    
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
    
    private var content: some View {
        mainContent
            .padding(
                .horizontal,
                16
            )
    }
    
    @ViewBuilder
    private var mainContent: some View {
        if !isEmpty {
            item
        } else if isFetching {
            loading
        }
    }
}

// MARK: - Item:

private extension PaywallFourPlansView {
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

private extension PaywallFourPlansView {
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

private extension PaywallFourPlansView {
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
            badgeTitle: "Most Popular",
            backgroundColor: .init(.systemBackground),
            borderWidth: borderWidth(plan),
            borderColor: borderColor(plan),
            isBorderGradient: isSelected(plan)
        ) {
            select(plan)
        }
    }
}

// MARK: - Preview:

#Preview {
    @Previewable @State var selectedPlanIdentifier: String = ProPlanIdentifiers.monthly
    
    ScrollView {
        PaywallFourPlansView(
            plans: NT_ProPlan.examplePlans,
            selectedPlanIdentifier: $selectedPlanIdentifier,
            isFetching: false
        )
    }
    .safeAreaPadding(
        .top,
        16
    )
    .safeAreaPadding(
        .bottom,
        32
    )
}
