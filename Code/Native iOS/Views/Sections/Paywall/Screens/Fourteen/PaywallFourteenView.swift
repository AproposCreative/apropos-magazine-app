//
//  PaywallFourteenView.swift
//  Native
//

import SwiftUI

struct PaywallFourteenView: View {
    
    // MARK: - Properties:
    
    /// Size of the dynamic type that is currently selected:
    @Environment(\.dynamicTypeSize) var dynamicTypeSize
    
    /// An actual pro plan that the users can purchase:
    @State var plan: NT_ProPlan? = nil
    
    /// 'Bool' value indicating whether or not the data is currently being fetched:
    @State var isFetching: Bool = true
    
    /// 'Bool' value indicating whether or not the user enabled the free trial of the pro plan:
    @State var isFreeTrialEnabled: Bool = true
    
    // MARK: - Private properties:
    
    /// Dismisses the view:
    @Environment(\.dismiss) private var dismiss
    
    // MARK: - View:
    
    var body: some View {
        content
    }
    
    private var content: some View {
        item
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
            .animation(
                .default,
                value: plan
            )
            .animation(
                .default,
                value: isFetching
            )
            .animation(
                .default,
                value: isFreeTrialEnabled
            )
            .task {
                await fetchPlan()
            }
            .navigationStack()
    }
}

// MARK: - Item:

private extension PaywallFourteenView {
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

private extension PaywallFourteenView {
    private var scroll: some View {
        scrollContent
            .safeAreaPadding(
                .top,
                16
            )
            .safeAreaPadding(
                .bottom,
                32
            )
    }
    
    private var scrollContent: some View {
        ScrollView {
            scrollItem
        }
    }
    
    private var scrollItem: some View {
        VStack(
            alignment: .center,
            spacing: 32
        ) {
            scrollItemContent
        }
    }
    
    @ViewBuilder
    private var scrollItemContent: some View {
        imageContent
        PaywallFourteenFeaturesView()
        PaywallFourteenTimelineView()
    }
}

// MARK: - Image:

private extension PaywallFourteenView {
    private var imageContent: some View {
        ImageBackgroundView(
            image: image,
            alignment: .top,
            cornerRadius: 0
        )
    }
}

// MARK: - Toolbar:

private extension PaywallFourteenView {
    private var toolbar: some View {
        BottomToolbarView() {
            toolbarContent
        }
    }
    
    @ViewBuilder
    private var toolbarContent: some View {
        enableFreeTrial
        purchaseLegalButtons
        notice
    }
    
    @ViewBuilder
    private var enableFreeTrial: some View {
        if shouldMoveContent {
            verticalEnableFreeTrialContent
        } else {
            horizontalEnableFreeTrialContent
        }
    }
    
    private var horizontalEnableFreeTrialContent: some View {
        HStack(
            alignment: .center,
            spacing: enableFreeTrialSpacing
        ) {
            enableFreeTrialItem
        }
    }
    
    private var verticalEnableFreeTrialContent: some View {
        VStack(
            alignment: .leading,
            spacing: enableFreeTrialSpacing
        ) {
            enableFreeTrialItem
        }
    }
    
    @ViewBuilder
    private var enableFreeTrialItem: some View {
        enableFreeTrialToggle
        enableFreeTrialTitleContent
    }
    
    private var enableFreeTrialToggle: some View {
        enableFreeTrialToggleContent
            .labelsHidden()
            // .disabled(<#T##disabled: Bool##Bool#>)
    }
    
    private var enableFreeTrialToggleContent: some View {
        Toggle(
            enableFreeTrialTitle,
            isOn: $isFreeTrialEnabled
        )
    }
    
    private var enableFreeTrialTitleContent: some View {
        Text(enableFreeTrialTitle)
            .font(.headline)
            .multilineTextAlignment(.leading)
            .foregroundStyle(.primary)
    }
    
    private var purchaseLegalButtons: some View {
        VStack(
            alignment: .leading,
            spacing: 8
        ) {
            purchaseLegalButtonsContent
        }
    }
    
    @ViewBuilder
    private var purchaseLegalButtonsContent: some View {
        purchaseButton
        PaywallTwelveLegalView(isFetching: isFetching)
    }
    
    private var purchaseButton: some View {
        ButtonView(
            title: purchaseTitle,
            isLoading: isFetching,
            isDisabled: !isPlanAvailable,
            action: startFreeTrial
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

// MARK: - Preview:

#Preview {
    PaywallFourteenView()
}
