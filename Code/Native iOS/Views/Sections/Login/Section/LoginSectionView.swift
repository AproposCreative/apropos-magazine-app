//
//  LoginSectionView.swift
//  Native
//

import SwiftUI

struct LoginSectionView: View {
    
    // MARK: - Properties:
    
    /// Screen that is currently shown (Can be 'nil' or no screen at all):
    @State var currentScreen: NT_LoginScreen? = nil
    
    // MARK: - View:
    
    var body: some View {
        content
    }
    
    private var content: some View {
        list
            .navigationTitle("Login")
            .sheet(
                item: $currentScreen,
                content: showScreen
            )
    }
}

// MARK: - List:

private extension LoginSectionView {
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

private extension LoginSectionView {
    private var screensContent: some View {
        ForEach(
            screens,
            content: screen
        )
    }
    
    private func screen(_ screen: NT_LoginScreen) -> some View {
        LoginSectionRowView(
            screen: screen,
            viewAction: view
        )
    }
}

// MARK: - Screen:

private extension LoginSectionView {
    @ViewBuilder
    private func showScreen(_ screen: NT_LoginScreen) -> some View {
        switch screen {
        case .first: LoginOneView()
        case .second: LoginTwoView()
        case .third: LoginThreeView()
        case .fourth: LoginFourView()
        case .fifth: LoginFiveView()
        }
    }
}

// MARK: - Preview:

#Preview {
    LoginSectionView()
}
