//
//  ProfileThreeUserView.swift
//  Native
//

import SwiftUI

struct ProfileThreeUserView: View {
    
    // MARK: - View:
    
    var body: some View {
        content
    }
    
    private var content: some View {
        item
            .listRowInsets(.init(.zero))
    }
}

// MARK: - Item:

private extension ProfileThreeUserView {
    private var item: some View {
        Section {
            user
        }
    }
}

// MARK: - User:

private extension ProfileThreeUserView {
    private var user: some View {
        AvatarTitleSubtitleView(
            avatarType: .image,
            avatarImage: image,
            avatarFrame: 64,
            avatarCornerRadius: 16,
            title: "John Smith",
            titleAlignment: .center,
            subtitle: "@john.smith_123",
            subtitleAlignment: .center,
            titleSubtitleAlignment: .center,
            titleSubtitleMaxWidthAlignment: .center,
            alignment: .vertical,
            horizontalAlignment: .center,
            isShowingBackground: false,
            cornerRadius: 0
        )
    }
}

// MARK: - Preview:

#Preview {
    List {
        ProfileThreeUserView()
    }
    .listStyle(.insetGrouped)
    .localizedNavigationTitle(title: "Profile")
    .navigationStack()
}
