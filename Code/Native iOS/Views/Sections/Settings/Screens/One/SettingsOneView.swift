//
//  SettingsOneView.swift
//  Native
//

import SwiftUI

struct SettingsOneView: View {
    
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

private extension SettingsOneView {
    private var tabBar: some View {
        TabView(selection: $currentTab) {
            Tab(
                .init(homeTitle),
                systemImage: Icons.house,
                value: .first
            ) {
                PlaceholderView(title: homeTitle)
            }
            
            Tab(
                .init(summaryTitle),
                systemImage: Icons.chartPie,
                value: .second
            ) {
                PlaceholderView(title: summaryTitle)
            }
            
            Tab(
                .init(settingsTitle),
                systemImage: Icons.gearshape,
                value: .third
            ) {
                SettingsOneContentView()
            }
        }
    }
}

// MARK: - Preview:

#Preview {
    SettingsOneView()
}
