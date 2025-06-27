//
//  ProfileSectionView.swift
//  Native
//

import SwiftUI

struct ProfileSectionView: View {
    
    // MARK: - Properties:
    
    /// Screen that is currently shown (Can be 'nil' or no screen at all):
    @State var currentScreen: NT_ProfileScreen? = nil
    
    // MARK: - View:
    
    var body: some View {
        content
    }
    
    private var content: some View {
        list
            .navigationTitle("Profile")
            .sheet(
                item: $currentScreen,
                content: showScreen
            )
    }
}

// MARK: - List:

private extension ProfileSectionView {
    private var list: some View {
        listContent
            .listStyle(.insetGrouped)
    }
    
    private var listContent: some View {
        List {
            screensContent
        }
    }
}

// MARK: - Screens:

private extension ProfileSectionView {
    private var screensContent: some View {
        ForEach(
            screens,
            content: screen
        )
    }
    
    private func screen(_ screen: NT_ProfileScreen) -> some View {
        ProfileSectionRowView(
            screen: screen,
            viewAction: view
        )
    }
}

// MARK: - Screen:

private extension ProfileSectionView {
    @ViewBuilder
    private func showScreen(_ screen: NT_ProfileScreen) -> some View {
        switch screen {
        case .first: ProfileOneView()
        case .second: ProfileTwoView()
        case .third: ProfileThreeView()
        case .fourth: ProfileFourView()
        case .fifth: ProfileFiveView()
        }
    }
}

// MARK: - Preview:

#Preview {
    ProfileSectionView()
}
