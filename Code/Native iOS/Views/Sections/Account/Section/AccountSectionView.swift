//
//  AccountSectionView.swift
//  Native
//

import SwiftUI

struct AccountSectionView: View {
    
    // MARK: - Properties:
    
    /// Screen that is currently shown (Can be 'nil' or no screen at all):
    @State var currentScreen: NT_AccountScreen? = nil
    
    // MARK: - View:
    
    var body: some View {
        content
    }
    
    private var content: some View {
        list
            .navigationTitle("Account")
            .sheet(
                item: $currentScreen,
                content: showScreen
            )
    }
}

// MARK: - List:

private extension AccountSectionView {
    private var list: some View {
        listContent
            .listStyle(.insetGrouped)
    }
    
    private var listContent: some View {
        List {
            screensContent
        }
    }
}

// MARK: - Screens:

private extension AccountSectionView {
    private var screensContent: some View {
        ForEach(
            screens,
            content: screen
        )
    }
    
    private func screen(_ screen: NT_AccountScreen) -> some View {
        AccountSectionRowView(
            screen: screen,
            viewAction: view
        )
    }
}

// MARK: - Screen:

private extension AccountSectionView {
    @ViewBuilder
    private func showScreen(_ screen: NT_AccountScreen) -> some View {
        switch screen {
        case .first: AccountOneView()
        case .second: AccountTwoView()
        case .third: AccountThreeView()
        case .fourth: AccountFourView()
        case .fifth: AccountFiveView()
        }
    }
}

// MARK: - Preview:

#Preview {
    AccountSectionView()
}
