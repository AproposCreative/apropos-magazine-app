//
//  MainTwoView.swift
//  Native
//

import SwiftUI

struct MainTwoView: View {
    
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

private extension MainTwoView {
    private var tabBar: some View {
        TabView(selection: $currentTab) {
            Tab(
                .init(coursesTitle),
                systemImage: Icons.docPlaintext,
                value: .first
            ) {
                MainTwoContentView()
            }
            
            Tab(
                .init(exploreTitle),
                systemImage: Icons.mailStack,
                value: .second
            ) {
                PlaceholderView(title: exploreTitle)
            }
            
            Tab(
                .init(startedTitle),
                systemImage: Icons.clock,
                value: .third
            ) {
                PlaceholderView(title: startedTitle)
            }
            
            Tab(
                .init(settingsTitle),
                systemImage: Icons.gearshape,
                value: .fourth
            ) {
                PlaceholderView(title: settingsTitle)
            }
        }
    }
}

// MARK: - Preview:

#Preview {
    MainTwoView()
}
