//
//  DataVisualizationFourView.swift
//  Native
//

import SwiftUI

struct DataVisualizationFourView: View {
    
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

private extension DataVisualizationFourView {
    private var tabBar: some View {
        TabView(selection: $currentTab) {
            Tab(
                .init(analyticsTitle),
                systemImage: Icons.chartLineUptrendXYAxis,
                value: .first
            ) {
                DataVisualizationFourContentView()
            }
            
            Tab(
                .init(profileTitle),
                systemImage: Icons.personCropCircle,
                value: .second
            ) {
                PlaceholderView(title: profileTitle)
            }
        }
    }
}

// MARK: - Preview:

#Preview {
    DataVisualizationFourView()
}
