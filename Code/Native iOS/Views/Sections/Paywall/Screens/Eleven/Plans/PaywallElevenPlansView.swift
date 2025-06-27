//
//  PaywallElevenPlansView.swift
//  Native
//

import SwiftUI

struct PaywallElevenPlansView: View {
    
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
            .environment(
                \.colorScheme,
                 .light
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

private extension PaywallElevenPlansView {
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
        header
        plansContent
    }
}

// MARK: - Loading:

private extension PaywallElevenPlansView {
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
            color: color.opacity(0.8),
            scale: 1.5
        )
    }
}

// MARK: - Header:

private extension PaywallElevenPlansView {
    private var header: some View {
        SectionHeaderView(
            title: "Pick a Plan that Suits You",
            titleColor: color
        )
    }
}

// MARK: - Plans:

private extension PaywallElevenPlansView {
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
            backgroundColor: .init(.systemBackground)
        ) {
            select(plan)
        }
    }
}

// MARK: - Preview:

#Preview {
    @Previewable @State var selectedPlanIdentifier: String = ProPlanIdentifiers.monthly
    
    ScrollView {
        PaywallElevenPlansView(
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
