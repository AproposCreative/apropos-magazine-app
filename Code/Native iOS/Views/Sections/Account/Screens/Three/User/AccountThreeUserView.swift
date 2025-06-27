//
//  AccountThreeUserView.swift
//  Native
//

import SwiftUI

struct AccountThreeUserView: View {
    
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

private extension AccountThreeUserView {
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
            verticalAlignment: .center,
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
        AccountThreeUserView()
    }
    .listStyle(.insetGrouped)
    .localizedNavigationTitle(title: "Profile")
    .navigationStack()
}
