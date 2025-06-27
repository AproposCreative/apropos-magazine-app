//
//  MainOneView.swift
//  Native
//

import SwiftUI

struct MainOneView: View {
    
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

private extension MainOneView {
    private var tabBar: some View {
        TabView(selection: $currentTab) {
            Tab(
                .init(dashboardTitle),
                systemImage: Icons.rectangleThreeGroup,
                value: .first
            ) {
                MainOneContentView()
            }
            
            Tab(
                .init(paymentsTitle),
                systemImage: Icons.arrowLeftArrowRight,
                value: .second
            ) {
                PlaceholderView(title: paymentsTitle)
            }
            
            Tab(
                .init(cardsTitle),
                systemImage: Icons.creditcard,
                value: .third
            ) {
                PlaceholderView(title: cardsTitle)
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
    MainOneView()
}
