//
//  SignUpSectionView.swift
//  Native
//

import SwiftUI

struct SignUpSectionView: View {
    
    // MARK: - Properties:
    
    /// Screen that is currently shown (Can be 'nil' or no screen at all):
    @State var currentScreen: NT_SignUpScreen? = nil
    
    // MARK: - View:
    
    var body: some View {
        content
    }
    
    private var content: some View {
        list
            .navigationTitle("Sign Up")
            .sheet(
                item: $currentScreen,
                content: showScreen
            )
    }
}

// MARK: - List:

private extension SignUpSectionView {
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

private extension SignUpSectionView {
    private var screensContent: some View {
        ForEach(
            screens,
            content: screen
        )
    }
    
    private func screen(_ screen: NT_SignUpScreen) -> some View {
        SignUpSectionRowView(
            screen: screen,
            viewAction: view
        )
    }
}

// MARK: - Screen:

private extension SignUpSectionView {
    @ViewBuilder
    private func showScreen(_ screen: NT_SignUpScreen) -> some View {
        switch screen {
        case .first: SignUpOneView()
        case .second: SignUpTwoView()
        case .third: SignUpThreeView()
        case .fourth: SignUpFourView()
        case .fifth: SignUpFiveView()
        }
    }
}

// MARK: - Preview:

#Preview {
    SignUpSectionView()
}
