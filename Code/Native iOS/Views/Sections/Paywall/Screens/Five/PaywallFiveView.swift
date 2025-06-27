//
//  PaywallFiveView.swift
//  Native
//

import SwiftUI

struct PaywallFiveView: View {
    
    // MARK: - Properties:
    
    /// An actual pro plan that the users can purchase:
    @State var plan: NT_ProPlan? = nil
    
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
        item
            .background(imageContent)
            .toolbarButton(
                title: "Done",
                color: .primary,
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
            .task {
                await fetchPlan()
            }
            .navigationStack()
            .environment(
                \.colorScheme,
                 .dark
            )
    }
}

// MARK: - Item:

private extension PaywallFiveView {
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

// MARK: - Image:

private extension PaywallFiveView {
    private var imageContent: some View {
        image
            .resizable()
            .ignoresSafeArea()
    }
}

// MARK: - Scroll:

private extension PaywallFiveView {
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
            alignment: .center,
            spacing: 48
        ) {
            scrollItemContent
        }
    }
    
    @ViewBuilder
    private var scrollItemContent: some View {
        title
        PaywallFiveFeaturesView()
    }
}

// MARK: - Title:

private extension PaywallFiveView {
    private var title: some View {
        titleContent
            .font(.largeTitle.bold())
            .multilineTextAlignment(.center)
            .foregroundStyle(.primary)
    }
    
    private var titleContent: some View {
        Text("Supercharge Your \(Text("iOS App Project").foregroundStyle(titleGradient)) 🚀")
    }
}

// MARK: - Toolbar:

private extension PaywallFiveView {
    private var toolbar: some View {
        BottomToolbarView() {
            purchaseRestoreButtons
        }
    }
    
    private var purchaseRestoreButtons: some View {
        VStack(
            alignment: .leading,
            spacing: 8
        ) {
            purchaseRestoreButtonsContent
        }
    }
    
    @ViewBuilder
    private var purchaseRestoreButtonsContent: some View {
        purchaseButton
        restoreButton
    }
    
    private var purchaseButton: some View {
        ButtonView(
            title: purchaseTitle,
            isLoading: isFetching,
            isDisabled: !isPlanAvailable,
            action: purchase
        )
    }
    
    private var restoreButton: some View {
        ButtonView(
            title: "Restore",
            titleColor: .primary,
            isLoading: isFetching,
            backgroundColor: .init(.systemFill),
            isBackgroundColorGradient: false,
            action: restore
        )
    }
}

// MARK: - Preview:

#Preview {
    PaywallFiveView()
}
