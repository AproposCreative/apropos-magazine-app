//
//  ProfileFourView.swift
//  Native
//

import SwiftUI

struct ProfileFourView: View {
    
    // MARK: - Private properties:
    
    /// Tab that is currently shown:
    @State private var currentTab: NT_Tab = .fourth
    
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

private extension ProfileFourView {
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
                .init(tasksTitle),
                systemImage: Icons.listBullet,
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
            
            Tab(
                .init(profileTitle),
                systemImage: Icons.personCropCircle,
                value: .fourth
            ) {
                ProfileFourContentView()
            }
        }
    }
}

// MARK: - Preview:

#Preview {
    ProfileFourView()
}
