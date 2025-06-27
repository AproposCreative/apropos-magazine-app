//
//  SortAndFilterFourView.swift
//  Native
//

import SwiftUI

struct SortAndFilterFourView: View {
    
    // MARK: - Private properties:
    
    /// Tab that is currently shown:
    @State private var currentTab: NT_Tab = .third
    
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

private extension SortAndFilterFourView {
    private var tabBar: some View {
        TabView(selection: $currentTab) {
            Tab(
                .init(todayTitle),
                systemImage: Icons.calendar,
                value: .first
            ) {
                PlaceholderView(title: todayTitle)
            }
            
            Tab(
                .init(projectsTitle),
                systemImage: Icons.mailStack,
                value: .second
            ) {
                PlaceholderView(title: projectsTitle)
            }
            
            Tab(
                .init(filterTitle),
                systemImage: Icons.lineThreeHorizontalDecreaseCircle,
                value: .third
            ) {
                SortAndFilterFourContentView()
            }
        }
    }
}

// MARK: - Preview:

#Preview {
    SortAndFilterFourView()
}
