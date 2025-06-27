//
//  ProfileFourUserView.swift
//  Native
//

import SwiftUI

struct ProfileFourUserView: View {
    
    // MARK: - View:
    
    var body: some View {
        content
    }
    
    private var content: some View {
        Section {
            user
        }
    }
}

// MARK: - User:

private extension ProfileFourUserView {
    private var user: some View {
        NavigationLink {
            userContent
        } label: {
            userLabel
        }
    }
    
    private var userContent: some View {
        PlaceholderView(
            title: name,
            isTitleLocalized: false
        )
    }
    
    private var userLabel: some View {
        AvatarTitleSubtitleView(
            avatarType: .image,
            avatarImage: image,
            avatarCornerRadius: 12,
            title: name,
            isTitleLocalized: false,
            subtitle: "@john.smith_123",
            verticalPadding: 3,
            horizontalPadding: 0,
            isShowingBackground: false,
            cornerRadius: 0
        )
    }
}

// MARK: - Preview:

#Preview {
    List {
        ProfileFourUserView()
    }
    .listStyle(.plain)
    .localizedNavigationTitle(title: "Profile")
    .navigationStack()
}
