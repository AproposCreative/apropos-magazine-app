//
//  DataVisualizationSectionView.swift
//  Native
//

import SwiftUI

struct DataVisualizationSectionView: View {
    
    // MARK: - Properties:
    
    /// Screen that is currently shown (Can be 'nil' or no screen at all):
    @State var currentScreen: NT_DataVisualizationScreen? = nil
    
    // MARK: - View:
    
    var body: some View {
        content
    }
    
    private var content: some View {
        list
            .navigationTitle("Data Visualization")
            .sheet(
                item: $currentScreen,
                content: showScreen
            )
    }
}

// MARK: - List:

private extension DataVisualizationSectionView {
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

private extension DataVisualizationSectionView {
    private var screensContent: some View {
        ForEach(
            screens,
            content: screen
        )
    }
    
    private func screen(_ screen: NT_DataVisualizationScreen) -> some View {
        DataVisualizationSectionRowView(
            screen: screen,
            viewAction: view
        )
    }
}

// MARK: - Screen:

private extension DataVisualizationSectionView {
    @ViewBuilder
    private func showScreen(_ screen: NT_DataVisualizationScreen) -> some View {
        switch screen {
        case .first: DataVisualizationOneView()
        case .second: DataVisualizationTwoView()
        case .third: DataVisualizationThreeView()
        case .fourth: DataVisualizationFourView()
        case .fifth: DataVisualizationFiveView()
        }
    }
}

// MARK: - Preview:

#Preview {
    DataVisualizationSectionView()
}
