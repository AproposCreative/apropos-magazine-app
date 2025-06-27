//
//  DataVisualizationOneView.swift
//  Native
//

import SwiftUI

struct DataVisualizationOneView: View {
    
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

private extension DataVisualizationOneView {
    private var tabBar: some View {
        TabView(selection: $currentTab) {
            Tab(
                .init(overviewTitle),
                systemImage: Icons.chartBar,
                value: .first
            ) {
                DataVisualizationOneContentView()
            }
            
            Tab(
                .init(salesTitle),
                systemImage: Icons.dollarsign,
                value: .second
            ) {
                PlaceholderView(title: salesTitle)
            }
            
            Tab(
                .init(productsTitle),
                systemImage: Icons.docPlaintext,
                value: .third
            ) {
                PlaceholderView(title: productsTitle)
            }
            
            Tab(
                .init(customersTitle),
                systemImage: Icons.person,
                value: .fourth
            ) {
                PlaceholderView(title: customersTitle)
            }
            
            Tab(
                .init(analyticsTitle),
                systemImage: Icons.chartLineUptrendXYAxis,
                value: .fifth
            ) {
                PlaceholderView(title: analyticsTitle)
            }
        }
    }
}

// MARK: - Preview:

#Preview {
    DataVisualizationOneView()
}
