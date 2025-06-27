//
//  AccountTwoContentView.swift
//  Native
//

import SwiftUI

struct AccountTwoContentView: View {
    
    // MARK: - View:
    
    var body: some View {
        content
    }
    
    private var content: some View {
        list
            .localizedNavigationTitle(title: "Account")
            .navigationDestination(
                for: NT_AccountSetting.self,
                destination: setting
            )
            .navigationStack()
    }
}

// MARK: - List:

private extension AccountTwoContentView {
    private var list: some View {
        listContent
            .listStyle(.plain)
    }
    
    private var listContent: some View {
        List {
            listItem
        }
    }
    
    @ViewBuilder
    private var listItem: some View {
        AccountTwoUserView()
        AccountTwoSettingsView()
    }
}

// MARK: - Setting:

private extension AccountTwoContentView {
    private func setting(_ setting: NT_AccountSetting) -> some View {
        PlaceholderView(title: title(setting))
    }
}

// MARK: - Preview:

#Preview {
    AccountTwoContentView()
}
