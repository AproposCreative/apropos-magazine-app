//
//  MainFiveView.swift
//  Native
//

import SwiftUI

struct MainFiveView: View {
    
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

private extension MainFiveView {
    private var tabBar: some View {
        TabView(selection: $currentTab) {
            Tab(
                .init(overviewTitle),
                systemImage: Icons.trayFull,
                value: .first
            ) {
                MainFiveContentView()
            }
            
            Tab(
                .init(tasksTitle),
                systemImage: Icons.checklist,
                value: .second
            ) {
                PlaceholderView(title: tasksTitle)
            }
            
            Tab(
                .init(projectsTitle),
                systemImage: Icons.mailStack,
                value: .third
            ) {
                PlaceholderView(title: projectsTitle)
            }
        }
    }
}

// MARK: - Preview:

#Preview {
    MainFiveView()
}
