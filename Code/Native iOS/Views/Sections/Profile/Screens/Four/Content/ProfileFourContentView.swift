//
//  ProfileFourContentView.swift
//  Native
//

import SwiftUI

struct ProfileFourContentView: View {
    
    // MARK: - Private properties:
    
    /// Dismisses the view:
    @Environment(\.dismiss) private var dismiss
    
    // MARK: - View:
    
    var body: some View {
        content
    }
    
    private var content: some View {
        list
            .localizedNavigationTitle(title: "Profile")
            .toolbarButton(
                title: "Share",
                icon: Icons.squareAndArrowUp,
                iconSymbolVariant: .none,
                font: .body,
                style: .iconOnly,
                action: share
            )
            .navigationDestination(
                for: NT_ProfileSetting.self,
                destination: setting
            )
            .navigationStack()
    }
}

// MARK: - List:

private extension ProfileFourContentView {
    private var list: some View {
        listContent
            .listStyle(.plain)
    }
    
    private var listContent: some View {
        List {
            listItem
        }
    }
    
    @ViewBuilder
    private var listItem: some View {
        ProfileFourUserView()
        ProfileFourSettingsView()
    }
}

// MARK: - Setting:

private extension ProfileFourContentView {
    private func setting(_ setting: NT_ProfileSetting) -> some View {
        PlaceholderView(title: title(setting))
    }
}

// MARK: - Preview:

#Preview {
    ProfileFourContentView()
}
