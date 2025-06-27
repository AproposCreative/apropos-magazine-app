//
//  ProfileThreeView.swift
//  Native
//

import SwiftUI

struct ProfileThreeView: View {
    
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
                title: "Done",
                action: dismiss.callAsFunction
            )
            .navigationDestination(
                for: NT_ProfileSetting.self,
                destination: setting
            )
            .navigationStack()
    }
}

// MARK: - List:

private extension ProfileThreeView {
    private var list: some View {
        listContent
            .listStyle(.insetGrouped)
    }
    
    private var listContent: some View {
        List {
            listItem
        }
    }
    
    @ViewBuilder
    private var listItem: some View {
        ProfileThreeUserView()
        ProfileThreeOverviewView()
        ProfileThreeSettingsView()
    }
}

// MARK: - Setting:

private extension ProfileThreeView {
    private func setting(_ setting: NT_ProfileSetting) -> some View {
        PlaceholderView(title: title(setting))
    }
}

// MARK: - Preview:

#Preview {
    ProfileThreeView()
}
