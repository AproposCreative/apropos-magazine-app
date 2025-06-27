//
//  MainNineView.swift
//  Native
//

import SwiftUI

struct MainNineView: View {
    
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

private extension MainNineView {
    private var tabBar: some View {
        TabView(selection: $currentTab) {
            Tab(
                .init(foldersTitle),
                systemImage: Icons.folder,
                value: .first
            ) {
                MainNineContentView()
            }
            
            Tab(
                .init(sharedTitle),
                systemImage: Icons.personThree,
                value: .second
            ) {
                PlaceholderView(title: sharedTitle)
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
    MainNineView()
}
