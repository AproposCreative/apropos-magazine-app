//
//  DataVisualizationThreeView.swift
//  Native
//

import SwiftUI

struct DataVisualizationThreeView: View {
    
    // MARK: - Private properties:
    
    /// Tab that is currently shown:
    @State private var currentTab: NT_Tab = .first
    
    // MARK: - View:
    
    var body: some View {
        content
    }
    
    private var content: some View {
        tabBar
            .onChange(
                of: currentTab,
                currentTabOnChange
            )
    }
}

// MARK: - Tab bar:

private extension DataVisualizationThreeView {
    private var tabBar: some View {
        TabView(selection: $currentTab) {
            Tab(
                .init(overviewTitle),
                systemImage: Icons.chartBar,
                value: .first
            ) {
                DataVisualizationThreeContentView()
            }
            
            Tab(
                .init(transactionsTitle),
                systemImage: Icons.creditcard,
                value: .second
            ) {
                PlaceholderView(title: transactionsTitle)
            }
            
            Tab(
                .init(settingsTitle),
                systemImage: Icons.gearshape,
                value: .third
            ) {
                PlaceholderView(title: settingsTitle)
            }
        }
    }
}

// MARK: - Preview:

#Preview {
    DataVisualizationThreeView()
}
