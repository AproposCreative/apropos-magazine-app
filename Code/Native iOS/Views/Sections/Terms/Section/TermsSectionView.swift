//
//  TermsSectionView.swift
//  Native
//

import SwiftUI

struct TermsSectionView: View {
    
    // MARK: - Properties:
    
    /// Screen that is currently shown (Can be 'nil' or no screen at all):
    @State var currentScreen: NT_TermsScreen? = nil
    
    // MARK: - View:
    
    var body: some View {
        content
    }
    
    private var content: some View {
        list
            .navigationTitle("Terms")
            .sheet(
                item: $currentScreen,
                content: showScreen
            )
    }
}

// MARK: - List:

private extension TermsSectionView {
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

private extension TermsSectionView {
    private var screensContent: some View {
        ForEach(
            screens,
            content: screen
        )
    }
    
    private func screen(_ screen: NT_TermsScreen) -> some View {
        TermsSectionRowView(
            screen: screen,
            viewAction: view
        )
    }
}

// MARK: - Screen:

private extension TermsSectionView {
    @ViewBuilder
    private func showScreen(_ screen: NT_TermsScreen) -> some View {
        switch screen {
        case .first: TermsOneView()
        case .second: TermsTwoView()
        case .third: TermsThreeView()
        case .fourth: TermsFourView()
        case .fifth: TermsFiveView()
        }
    }
}

// MARK: - Preview:

#Preview {
    TermsSectionView()
}
