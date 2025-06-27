//
//  AccountFourView.swift
//  Native
//

import SwiftUI

struct AccountFourView: View {
    
    // MARK: - Private properties:
    
    /// Dismisses the view:
    @Environment(\.dismiss) private var dismiss
    
    // MARK: - View:
    
    var body: some View {
        content
    }
    
    private var content: some View {
        list
            .localizedNavigationTitle(title: "Account")
            .toolbarButton(
                title: "Done",
                action: dismiss.callAsFunction
            )
            .navigationDestination(
                for: NT_AccountSetting.self,
                destination: setting
            )
            .navigationStack()
    }
}

// MARK: - List:

private extension AccountFourView {
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
        AccountFourUserView()
        AccountFourSettingsView()
    }
}

// MARK: - Setting:

private extension AccountFourView {
    private func setting(_ setting: NT_AccountSetting) -> some View {
        PlaceholderView(title: title(setting))
    }
}

// MARK: - Preview:

#Preview {
    AccountFourView()
}
