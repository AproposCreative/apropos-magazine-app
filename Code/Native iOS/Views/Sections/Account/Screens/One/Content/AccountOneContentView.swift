//
//  AccountOneContentView.swift
//  Native
//

import SwiftUI

struct AccountOneContentView: View {
    
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

private extension AccountOneContentView {
    private var list: some View {
        listContent
            .listStyle(.insetGrouped)
    }
    
    private var listContent: some View {
        List {
            listItem
        }
    }
    
    @ViewBuilder
    private var listItem: some View {
        AccountOneUserView()
        AccountOneSettingsView()
    }
}

// MARK: - Setting:

private extension AccountOneContentView {
    private func setting(_ setting: NT_AccountSetting) -> some View {
        PlaceholderView(title: title(setting))
    }
}

// MARK: - Preview:

#Preview {
    AccountOneContentView()
}
