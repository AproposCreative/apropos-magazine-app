//
//  EmptyStateSectionView.swift
//  Native
//

import SwiftUI

struct EmptyStateSectionView: View {
    
    // MARK: - Properties:
    
    /// Screen that is currently shown (Can be 'nil' or no screen at all):
    @State var currentScreen: NT_EmptyStateScreen? = nil
    
    // MARK: - View:
    
    var body: some View {
        content
    }
    
    private var content: some View {
        list
            .navigationTitle("Empty State")
            .sheet(
                item: $currentScreen,
                content: showScreen
            )
    }
}

// MARK: - List:

private extension EmptyStateSectionView {
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

private extension EmptyStateSectionView {
    private var screensContent: some View {
        ForEach(
            screens,
            content: screen
        )
    }
    
    private func screen(_ screen: NT_EmptyStateScreen) -> some View {
        EmptyStateSectionRowView(
            screen: screen,
            viewAction: view
        )
    }
}

// MARK: - Screen:

private extension EmptyStateSectionView {
    @ViewBuilder
    private func showScreen(_ screen: NT_EmptyStateScreen) -> some View {
        switch screen {
        case .first: EmptyStateOneView()
        case .second: EmptyStateTwoView()
        case .third: EmptyStateThreeView()
        case .fourth: EmptyStateFourView()
        case .fifth: EmptyStateFiveView()
        }
    }
}

// MARK: - Preview:

#Preview {
    EmptyStateSectionView()
}
