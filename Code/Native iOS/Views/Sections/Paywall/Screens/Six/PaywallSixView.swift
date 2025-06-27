//
//  PaywallSixView.swift
//  Native
//

import SwiftUI

struct PaywallSixView: View {
    
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
            .background(backgroundColor)
            .localizedNavigationTitle(
                title: "AppLayouts Pro",
                isLocalized: false
            )
            .toolbarButton(
                title: "Restore",
                isLoading: isFetching,
                placement: .cancellationAction,
                action: restore
            )
            .toolbarButton(
                title: "Done",
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
    }
}

// MARK: - Item:

private extension PaywallSixView {
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

private extension PaywallSixView {
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
            scrollItemContent
        }
    }
    
    @ViewBuilder
    private var scrollItemContent: some View {
        PaywallSixFeaturesView()
        PaywallLegalView()
    }
}

// MARK: - Toolbar:

private extension PaywallSixView {
    private var toolbar: some View {
        BottomToolbarView(backgroundColor: backgroundColor) {
            toolbarContent
        }
    }
    
    @ViewBuilder
    private var toolbarContent: some View {
        notice
        purchaseButton
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
    
    private var purchaseButton: some View {
        ButtonView(
            title: purchaseTitle,
            isLoading: isFetching,
            isDisabled: !isPlanAvailable,
            action: purchase
        )
    }
}

// MARK: - Preview:

#Preview {
    PaywallSixView()
}
