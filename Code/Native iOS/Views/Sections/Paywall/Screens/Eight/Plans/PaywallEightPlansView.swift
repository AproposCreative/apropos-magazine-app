//
//  PaywallEightPlansView.swift
//  Native
//

import SwiftUI

struct PaywallEightPlansView: View {
    
    // MARK: - Properties:
    
    /// Size of the dynamic type that is currently selected:
    @Environment(\.dynamicTypeSize) var dynamicTypeSize
    
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

private extension PaywallEightPlansView {
    @ViewBuilder
    private var item: some View {
        if shouldMoveContent {
            verticalItem
        } else {
            horizontalItem
        }
    }
    
    private var horizontalItem: some View {
        HStack(
            alignment: .top,
            spacing: spacing
        ) {
            plansContent
        }
    }
    
    private var verticalItem: some View {
        VStack(
            alignment: .leading,
            spacing: spacing
        ) {
            plansContent
        }
    }
}

// MARK: - Loading:

private extension PaywallEightPlansView {
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

private extension PaywallEightPlansView {
    private var plansContent: some View {
        ForEach(
            plans,
            content: plan
        )
    }
    
    private func plan(_ plan: NT_ProPlan) -> some View {
        SelectButtonTitleSubtitleBadgeView(
            selectButtonFrame: nil,
            isSelected: isSelected(plan),
            title: title(plan),
            subtitle: price(plan),
            isShowingBadge: isShowingBadge(plan),
            badgeTitle: "Popular",
            alignment: .vertical,
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
        PaywallEightPlansView(
            plans: NT_ProPlan.examplePlans.filter { $0.type != .lifetime },
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
        32
    )
    .background(Color(.systemGroupedBackground))
}
