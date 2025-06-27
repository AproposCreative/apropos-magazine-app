//
//  MainSevenView.swift
//  Native
//

import SwiftUI

struct MainSevenView: View {
    
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

private extension MainSevenView {
    private var tabBar: some View {
        TabView(selection: $currentTab) {
            Tab(
                .init(exploreTitle),
                systemImage: Icons.bag,
                value: .first
            ) {
                MainSevenContentView()
            }
            
            Tab(
                .init(wishlistTitle),
                systemImage: Icons.heart,
                value: .second
            ) {
                PlaceholderView(title: wishlistTitle)
            }
            
            Tab(
                .init(profileTitle),
                systemImage: Icons.personCropCircle,
                value: .third
            ) {
                PlaceholderView(title: profileTitle)
            }
        }
    }
}

// MARK: - Preview:

#Preview {
    MainSevenView()
}
