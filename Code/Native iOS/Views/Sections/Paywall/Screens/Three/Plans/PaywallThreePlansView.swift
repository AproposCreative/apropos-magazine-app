//
//  PaywallThreePlansView.swift
//  Native
//

import SwiftUI

struct PaywallThreePlansView: View {
    
    // MARK: - Properties:
    
    /// Size of the dynamic type that is currently selected:
    @Environment(\.dynamicTypeSize) var dynamicTypeSize
    
    /// Color scheme that is currently selected:
    @Environment(\.colorScheme) var colorScheme
    
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
        item
            .padding(
                .horizontal,
                16
            )
    }
}

// MARK: - Item:

private extension PaywallThreePlansView {
    @ViewBuilder
    private var item: some View {
        if !isEmpty {
            itemContent
        } else if isFetching {
            loading
        }
    }
    
    @ViewBuilder
    private var itemContent: some View {
        if shouldMoveContent {
            verticalItemContent
        } else {
            horizontalItemContent
        }
    }
    
    private var horizontalItemContent: some View {
        HStack(
            alignment: .top,
            spacing: spacing
        ) {
            plansContent
        }
    }
    
    private var verticalItemContent: some View {
        VStack(
            alignment: .leading,
            spacing: spacing
        ) {
            plansContent
        }
    }
}

// MARK: - Loading:

private extension PaywallThreePlansView {
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

private extension PaywallThreePlansView {
    private var plansContent: some View {
        ForEach(
            plans,
            content: plan
        )
    }
    
    private func plan(_ plan: NT_ProPlan) -> some View {
        SelectButtonTitleSubtitleBadgeView(
            selectButtonFrame: 24,
            isSelected: isSelected(plan),
            title: title(plan),
            isTitleColorGradient: isSelected(plan),
            subtitle: price(plan),
            isSubtitleColorGradient: isSelected(plan),
            isShowingBadge: isShowingBadge(plan),
            badgeTitle: "Popular",
            alignment: .vertical,
            backgroundColor: .init(.systemBackground),
            backgroundGradientStart: backgroundGradientStart,
            backgroundGradientEnd: backgroundGradientEnd,
            isBackgroundColorGradient: isSelected(plan),
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
        PaywallThreePlansView(
            plans: NT_ProPlan.examplePlans.filter { $0.type != .lifetime },
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
    .animation(
        .default,
        value: selectedPlanIdentifier
    )
}
