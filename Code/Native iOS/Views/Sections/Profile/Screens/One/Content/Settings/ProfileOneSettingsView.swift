//
//  ProfileOneSettingsView.swift
//  Native
//

import SwiftUI

struct ProfileOneSettingsView: View {
    
    // MARK: - Properties:
    
    /// Size of the dynamic type that is currently selected:
    @Environment(\.dynamicTypeSize) var dynamicTypeSize
    
    // MARK: - View:
    
    var body: some View {
        content
    }
    
    private var content: some View {
        VStack(
            alignment: .leading,
            spacing: 16
        ) {
            item
        }
    }
}

// MARK: - Item:

private extension ProfileOneSettingsView {
    @ViewBuilder
    private var item: some View {
        SectionHeaderView(title: "Settings")
        settingsContent
    }
}

// MARK: - Settings:

private extension ProfileOneSettingsView {
    private var settingsContent: some View {
        settingsItem
            .contentBackground(
                verticalPadding: 0,
                horizontalPadding: 0
            )
    }
    
    private var settingsItem: some View {
        LazyVStack(
            alignment: .leading,
            spacing: 0
        ) {
            settingsItemContent
        }
    }
    
    private var settingsItemContent: some View {
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
        IconBackgroundTitleSubtitleIconView(
            icon: icon(setting),
            iconColor: color(setting),
            iconGradientStart: gradientStart(setting),
            iconGradientEnd: gradientEnd(setting),
            isIconColorGradient: true,
            isShowingIconBackground: false,
            iconSize: .twentyFourPixels,
            title: title(setting),
            subtitle: description(setting),
            secondIconFrame: secondIconFrame,
            titleSubtitleSecondIconAlignment: .center,
            verticalAlignment: .top,
            isShowingBackground: false,
            cornerRadius: 0
        )
    }
}

// MARK: - Preview:

#Preview {
    ScrollView {
        ProfileOneSettingsView()
    }
    .safeAreaPadding(
        .all,
        16
    )
    .safeAreaPadding(
        .bottom,
        16
    )
    .background(Color(.systemGroupedBackground))
    .localizedNavigationTitle(title: "Profile")
    .navigationDestination(for: NT_ProfileSetting.self) { setting in
        PlaceholderView(title: setting.title)
    }
    .navigationStack()
}
