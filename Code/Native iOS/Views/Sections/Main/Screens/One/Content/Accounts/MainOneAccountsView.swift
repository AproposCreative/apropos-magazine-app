//
//  MainOneAccountsView.swift
//  Native
//

import SwiftUI

struct MainOneAccountsView: View {
    
    // MARK: - Properties:
    
    /// Size of the dynamic type that is currently selected:
    @Environment(\.dynamicTypeSize) var dynamicTypeSize
    
    /// An array of the accounts to display:
    let accounts: [NT_TransactionsAccount]
    
    init(accounts: [NT_TransactionsAccount]) {
        
        /// Properties initialization:
        self.accounts = accounts
    }
    
    // MARK: - View:
    
    var body: some View {
        content
    }
    
    @ViewBuilder
    private var content: some View {
        if isShowing {
            item
        }
    }
}

// MARK: - Item:

private extension MainOneAccountsView {
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
        SectionHeaderView(title: "Accounts")
        accountsContent
    }
}

// MARK: - Accounts:

private extension MainOneAccountsView {
    private var accountsContent: some View {
        accountsItem
            .contentBackground(
                verticalPadding: 0,
                horizontalPadding: 0
            )
    }
    
    private var accountsItem: some View {
        VStack(
            alignment: .leading,
            spacing: 0
        ) {
            accountsItemContent
        }
    }
    
    private var accountsItemContent: some View {
        ForEach(
            accounts,
            content: account
        )
    }
    
    private func account(_ account: NT_TransactionsAccount) -> some View {
        NavigationLink(value: account) {
            accountLabel(account)
        }
    }
    
    private func accountLabel(_ account: NT_TransactionsAccount) -> some View {
        IconBackgroundTitleSubtitleValueIconView(
            icon: icon(account),
            iconBackgroundColor: color(account),
            iconBackgroundGradientStart: gradientStart(account),
            iconBackgroundGradientEnd: gradientEnd(account),
            title: title(account),
            value: amount(account),
            subtitle: number(account),
            secondIconFrame: secondIconFrame
        )
    }
}

// MARK: - Preview:

#Preview {
    ScrollView {
        MainOneAccountsView(accounts: NT_TransactionsAccount.example)
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
