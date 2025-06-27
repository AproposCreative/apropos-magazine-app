//
//  AccountFiveUserView.swift
//  Native
//

import SwiftUI

struct AccountFiveUserView: View {
    
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

private extension AccountFiveUserView {
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
        AccountFiveUserView()
    }
    .listStyle(.insetGrouped)
    .localizedNavigationTitle(title: "Profile")
    .navigationStack()
}
