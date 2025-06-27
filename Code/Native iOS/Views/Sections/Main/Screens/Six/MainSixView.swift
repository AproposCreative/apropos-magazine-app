//
//  MainSixView.swift
//  Native
//

import SwiftUI

struct MainSixView: View {
    
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

private extension MainSixView {
    private var tabBar: some View {
        TabView(selection: $currentTab) {
            Tab(
                .init(recentTitle),
                systemImage: Icons.clock,
                value: .first
            ) {
                MainSixContentView()
            }
            
            Tab(
                .init(messagesTitle),
                systemImage: Icons.textBubble,
                value: .second
            ) {
                PlaceholderView(title: messagesTitle)
            }
            
            Tab(
                .init(exploreTitle),
                systemImage: Icons.rectangleStack,
                value: .third
            ) {
                PlaceholderView(title: exploreTitle)
            }
            
            Tab(
                .init(profileTitle),
                systemImage: Icons.personCropCircle,
                value: .fourth
            ) {
                PlaceholderView(title: profileTitle)
            }
        }
    }
}

// MARK: - Preview:

#Preview {
    MainSixView()
}
