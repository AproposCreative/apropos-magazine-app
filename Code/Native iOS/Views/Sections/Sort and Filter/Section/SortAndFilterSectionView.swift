//
//  SortAndFilterSectionView.swift
//  Native
//

import SwiftUI

struct SortAndFilterSectionView: View {
    
    // MARK: - Properties:
    
    /// Screen that is currently shown (Can be 'nil' or no screen at all):
    @State var currentScreen: NT_SortAndFilterScreen? = nil
    
    // MARK: - View:
    
    var body: some View {
        content
    }
    
    private var content: some View {
        list
            .navigationTitle("Sort and Filter")
            .sheet(
                item: $currentScreen,
                content: showScreen
            )
    }
}

// MARK: - List:

private extension SortAndFilterSectionView {
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

private extension SortAndFilterSectionView {
    private var screensContent: some View {
        ForEach(
            screens,
            content: screen
        )
    }
    
    private func screen(_ screen: NT_SortAndFilterScreen) -> some View {
        SortAndFilterSectionRowView(
            screen: screen,
            viewAction: view
        )
    }
}

// MARK: - Screen:

private extension SortAndFilterSectionView {
    @ViewBuilder
    private func showScreen(_ screen: NT_SortAndFilterScreen) -> some View {
        switch screen {
        case .first: SortAndFilterOneView()
        case .second: SortAndFilterTwoView()
        case .third: SortAndFilterThreeView()
        case .fourth: SortAndFilterFourView()
        case .fifth: SortAndFilterFiveView()
        }
    }
}

// MARK: - Preview:

#Preview {
    SortAndFilterSectionView()
}
