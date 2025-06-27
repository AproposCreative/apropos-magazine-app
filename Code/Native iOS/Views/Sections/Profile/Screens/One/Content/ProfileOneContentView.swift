//
//  ProfileOneContentView.swift
//  Native
//

import SwiftUI

struct ProfileOneContentView: View {
    
    // MARK: - View:
    
    var body: some View {
        content
    }
    
    private var content: some View {
        scroll
            .background(Color(.systemGroupedBackground))
            .localizedNavigationTitle(title: "Profile")
            .navigationDestination(
                for: NT_ProfileSetting.self,
                destination: setting
            )
            .navigationStack()
    }
}

// MARK: - Scroll:

private extension ProfileOneContentView {
    private var scroll: some View {
        scrollContent
            .safeAreaPadding(
                .all,
                16
            )
            .safeAreaPadding(
                .bottom,
                16
            )
    }
    
    private var scrollContent: some View {
        ScrollView {
            scrollItem
        }
    }
    
    private var scrollItem: some View {
        VStack(
            alignment: .leading,
            spacing: 32
        ) {
            scrollItemContent
        }
    }
    
    @ViewBuilder
    private var scrollItemContent: some View {
        ProfileOneDetailsView()
        ProfileOneSettingsView()
    }
}

// MARK: - Setting:

private extension ProfileOneContentView {
    private func setting(_ setting: NT_ProfileSetting) -> some View {
        PlaceholderView(title: title(setting))
    }
}

// MARK: - Preview:

#Preview {
    ProfileOneContentView()
}
