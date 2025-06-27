//
//  ProfileThreeSettingsView.swift
//  Native
//

import SwiftUI

struct ProfileThreeSettingsView: View {
    
    // MARK: - View:
    
    var body: some View {
        content
    }
    
    private var content: some View {
        item
            .headerProminence(.increased)
    }
}

// MARK: - Item:

private extension ProfileThreeSettingsView {
    private var item: some View {
        Section("Settings") {
            settingsContent
        }
    }
}

// MARK: - Settings:

private extension ProfileThreeSettingsView {
    private var settingsContent: some View {
        ForEach(
            settings,
            content: setting
        )
    }
    
    private func setting(_ setting: NT_ProfileSetting) -> some View {
        NavigationLink(value: setting) {
            settingLabel(setting)
        }
    }
    
    private func settingLabel(_ setting: NT_ProfileSetting) -> some View {
        IconBackgroundTitleSubtitleView(
            icon: icon(setting),
            iconColor: color(setting),
            iconGradientStart: gradientStart(setting),
            iconGradientEnd: gradientEnd(setting),
            isIconColorGradient: true,
            isShowingIconBackground: false,
            iconSize: .twentyFourPixels,
            title: title(setting),
            subtitle: description(setting),
            verticalAlignment: .top,
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
        ProfileThreeSettingsView()
    }
    .listStyle(.insetGrouped)
    .localizedNavigationTitle(title: "Profile")
    .navigationDestination(for: NT_ProfileSetting.self) { setting in
        PlaceholderView(title: setting.title)
    }
    .navigationStack()
}
