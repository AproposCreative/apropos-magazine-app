//
//  AccountFourUserView.swift
//  Native
//

import SwiftUI

struct AccountFourUserView: View {
    
    // MARK: - View:
    
    var body: some View {
        content
    }
    
    private var content: some View {
        item
            .listRowSeparator(.hidden)
    }
}

// MARK: - Item:

private extension AccountFourUserView {
    private var item: some View {
        Section {
            user
        }
    }
}

// MARK: - User:

private extension AccountFourUserView {
    private var user: some View {
        AvatarTitleSubtitleView(
            avatarType: .image,
            avatarImage: image,
            avatarFrame: 96,
            avatarCornerRadius: 48,
            title: "John Smith",
            titleFont: .title2.bold(),
            titleAlignment: .center,
            subtitle: "@john.smith_123",
            subtitleFont: .body,
            subtitleAlignment: .center,
            titleSubtitleAlignment: .center,
            titleSubtitleSpacing: 6,
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
        AccountFourUserView()
    }
    .listStyle(.plain)
    .localizedNavigationTitle(title: "Profile")
    .navigationStack()
}
