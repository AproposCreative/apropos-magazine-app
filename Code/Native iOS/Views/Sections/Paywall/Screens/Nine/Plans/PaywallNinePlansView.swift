//
//  PaywallNinePlansView.swift
//  Native
//

import SwiftUI

struct PaywallNinePlansView: View {
    
    // MARK: - Properties:
    
    /// Identifier of the pro plan that is currently selected:
    @Binding var selectedPlanIdentifier: String
    
    /// An array of the pro plans to display:
    let plans: [NT_ProPlan]
    
    // MARK: - Private properties:
    
    /// Level of the pro plan that is currently selected:
    @Binding private var selectedLevel: NT_ProPlanLevel
    
    /// 'Bool' value indicating whether or not the data is currently being fetched:
    private let isFetching: Bool
    
    init(
        plans: [NT_ProPlan],
        selectedLevel: Binding<NT_ProPlanLevel>,
        selectedPlanIdentifier: Binding<String>,
        isFetching: Bool
    ) {
        
        /// Properties initialization:
        self.plans = plans
        _selectedLevel = selectedLevel
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

private extension PaywallNinePlansView {
    private var item: some View {
        VStack(
            alignment: .center,
            spacing: spacing
        ) {
            itemContent
        }
    }
    
    @ViewBuilder
    private var itemContent: some View {
        levelPicker
        plansContent
    }
}

// MARK: - Loading:

private extension PaywallNinePlansView {
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

// MARK: - Level picker:

private extension PaywallNinePlansView {
    private var levelPicker: some View {
        levelPickerContent
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(
                width: 200,
                alignment: .center
            )
    }
    
    private var levelPickerContent: some View {
        Picker(
            "Level",
            selection: $selectedLevel
        ) {
            levelsContent
        }
    }
    
    private var levelsContent: some View {
        ForEach(
            levels,
            content: level
        )
    }
    
    private func level(_ level: NT_ProPlanLevel) -> some View {
        Text(title(level))
            .tag(level)
    }
}

// MARK: - Plans:

private extension PaywallNinePlansView {
    private var plansContent: some View {
        VStack(
            alignment: .leading,
            spacing: spacing
        ) {
            plansItem
        }
    }
    
    private var plansItem: some View {
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
    @Previewable @State var selectedLevel: NT_ProPlanLevel = .starter
    @Previewable @State var selectedPlanIdentifier: String = ProPlanIdentifiers.monthly
    
    ScrollView {
        PaywallNinePlansView(
            plans: NT_ProPlan.examplePlans.filter { $0.type != .lifetime },
            selectedLevel: $selectedLevel,
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
}
