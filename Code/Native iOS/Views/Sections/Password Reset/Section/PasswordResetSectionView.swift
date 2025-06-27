//
//  PasswordResetSectionView.swift
//  Native
//

import SwiftUI

struct PasswordResetSectionView: View {
    
    // MARK: - Properties:
    
    /// Screen that is currently shown (Can be 'nil' or no screen at all):
    @State var currentScreen: NT_PasswordResetScreen? = nil
    
    // MARK: - View:
    
    var body: some View {
        content
    }
    
    private var content: some View {
        list
            .navigationTitle("Password Reset")
            .sheet(
                item: $currentScreen,
                content: showScreen
            )
    }
}

// MARK: - List:

private extension PasswordResetSectionView {
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

private extension PasswordResetSectionView {
    private var screensContent: some View {
        ForEach(
            screens,
            content: screen
        )
    }
    
    private func screen(_ screen: NT_PasswordResetScreen) -> some View {
        PasswordResetSectionRowView(
            screen: screen,
            viewAction: view
        )
    }
}

// MARK: - Screen:

private extension PasswordResetSectionView {
    @ViewBuilder
    private func showScreen(_ screen: NT_PasswordResetScreen) -> some View {
        switch screen {
        case .first: PasswordResetOneView()
        case .second: PasswordResetTwoView()
        case .third: PasswordResetThreeView()
        case .fourth: PasswordResetFourView()
        case .fifth: PasswordResetFiveView()
        }
    }
}

// MARK: - Preview:

#Preview {
    PasswordResetSectionView()
}
