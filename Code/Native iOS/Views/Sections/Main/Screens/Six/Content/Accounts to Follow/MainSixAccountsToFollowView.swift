//
//  MainSixAccountsToFollowView.swift
//  Native
//

import SwiftUI

struct MainSixAccountsToFollowView: View {
    
    // MARK: - Properties:
    
    /// An array of the accounts to display:
    let accounts: [NT_Account]
    
    init(accounts: [NT_Account]) {
        
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
            mainContent
        }
    }
    
    private var mainContent: some View {
        item
            .headerProminence(.increased)
    }
}

// MARK: - Item:

private extension MainSixAccountsToFollowView {
    private var item: some View {
        Section("Accounts to Follow") {
            accountsContent
        }
    }
}

// MARK: - Accounts:

private extension MainSixAccountsToFollowView {
    private var accountsContent: some View {
        ForEach(
            accounts,
            content: account
        )
    }
    
    private func account(_ account: NT_Account) -> some View {
        NavigationLink(value: account) {
            accountLabel(account)
        }
    }
    
    private func accountLabel(_ account: NT_Account) -> some View {
        AvatarTitleSubtitleView(
            avatarType: .image,
            avatarImage: image(account),
            title: name(account),
            subtitle: description(account),
            verticalPadding: 0,
            horizontalPadding: 0,
            isShowingBackground: false,
            cornerRadius: 0
        )
    }
}

// MARK: - Preview:

#Preview {
    List {
        MainSixAccountsToFollowView(accounts: NT_Account.example)
    }
    .listStyle(.plain)
    .localizedNavigationTitle(title: "Recent")
    .navigationStack()
}
