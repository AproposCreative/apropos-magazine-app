//
//  PaywallTwoView.swift
//  Native
//

import SwiftUI

struct PaywallTwoView: View {
    
    // MARK: - Properties:
    
    /// Color scheme that is currently selected:
    @Environment(\.colorScheme) var colorScheme
    
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
        scroll
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

// MARK: - Scroll:

private extension PaywallTwoView {
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
            spacing: 32
        ) {
            scrollItemContent
        }
    }
    
    @ViewBuilder
    private var scrollItemContent: some View {
        title
        PaywallTwoFeaturesView()
        buttons
        notice
    }
}

// MARK: - Title:

private extension PaywallTwoView {
    private var title: some View {
        titleContent
            .font(.largeTitle.bold())
            .multilineTextAlignment(.leading)
            .foregroundStyle(.primary)
    }
    
    private var titleContent: some View {
        Text("Supercharge Your \(Text("iOS App Project").foregroundStyle(titleGradient)) 🚀")
    }
}

// MARK: - Buttons:

private extension PaywallTwoView {
    @ViewBuilder
    private var buttons: some View {
        if isFetching {
            buttonsLoading
        } else {
            buttonsContent
        }
    }
    
    private var buttonsLoading: some View {
        buttonsLoadingContent
            .frame(
                maxWidth: .infinity,
                alignment: .center
            )
    }
    
    private var buttonsLoadingContent: some View {
        LoadingView(
            isShowing: isPlansEmpty,
            color: .secondary,
            scale: 1.5
        )
    }
    
    private var buttonsContent: some View {
        VStack(
            alignment: .leading,
            spacing: 8
        ) {
            buttonsItem
        }
    }
    
    @ViewBuilder
    private var buttonsItem: some View {
        plansButtons
        restoreButton
    }
    
    @ViewBuilder
    private var plansButtons: some View {
        if !isPlansEmpty {
            plansButtonsContent
        }
    }
    
    private var plansButtonsContent: some View {
        ForEach(
            plans,
            content: planButton
        )
    }
    
    private var restoreButton: some View {
        ButtonView(
            title: "Restore",
            titleColor: .primary,
            isLoading: isFetching,
            backgroundColor: .init(.secondarySystemBackground),
            isBackgroundColorGradient: false,
            action: restore
        )
    }
    
    private func planButton(_ plan: NT_ProPlan) -> some View {
        ButtonView(
            title: price(plan),
            isTitleColorGradient: !isMonthly(plan),
            isLoading: isFetching,
            backgroundGradientStart: planButtonBackgroundGradientStart(plan),
            backgroundGradientEnd: planButtonBackgroundGradientEnd(plan),
            isDisabled: isPlansEmpty
        ) {
            purchase(plan)
        }
    }
}

// MARK: - Notice:

private extension PaywallTwoView {
    private var notice: some View {
        noticeContent
            .font(.footnote)
            .multilineTextAlignment(.leading)
            .foregroundStyle(.secondary)
    }
    
    private var noticeContent: some View {
        Text("Your subscription will automatically renew unless cancelled at least 24 hours before the renewal date. By signing up, you acknowledge that you have read and agree to the \(Text("[terms of service](https://www.applayouts.com/terms-of-use)").underline().foregroundStyle(.accent)) and \(Text("[privacy policy](https://www.applayouts.com/privacy-policy)").underline().foregroundStyle(.accent)).")
    }
}

// MARK: - Preview:

#Preview {
    PaywallTwoView()
}
