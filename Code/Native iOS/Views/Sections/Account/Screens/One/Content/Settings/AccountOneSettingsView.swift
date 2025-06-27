//
//  AccountOneSettingsView.swift
//  Native
//

import SwiftUI

struct AccountOneSettingsView: View {
    
    // MARK: - Private properties:
    
    /// 'Bool' value indicating whether or not the notifications should be enabled:
    @State private var isNotificationsEnabled: Bool = true
    
    // MARK: - View:
    
    var body: some View {
        content
    }
    
    private var content: some View {
        sectionsContent
            .headerProminence(.increased)
    }
}

// MARK: - Sections:

private extension AccountOneSettingsView {
    private var sectionsContent: some View {
        ForEach(
            sections,
            content: section
        )
    }
    
    private func section(_ section: NT_AccountSettingsSection) -> some View {
        Section(title(section)) {
            settingsContent(section)
        }
    }
}

// MARK: - Settings:

private extension AccountOneSettingsView {
    private func settingsContent(_ section: NT_AccountSettingsSection) -> some View {
        ForEach(
            settings(section),
            content: setting
        )
    }
    
    @ViewBuilder
    private func setting(_ setting: NT_AccountSetting) -> some View {
        if isToggle(setting) {
            settingToggle(setting)
        } else {
            settingLink(setting)
        }
    }
    
    private func settingToggle(_ setting: NT_AccountSetting) -> some View {
        Toggle(isOn: $isNotificationsEnabled) {
            settingLabel(setting)
        }
    }
    
    private func settingLink(_ setting: NT_AccountSetting) -> some View {
        NavigationLink(value: setting) {
            settingLabel(setting)
        }
    }
    
    private func settingLabel(_ setting: NT_AccountSetting) -> some View {
        IconBackgroundTitleSubtitleView(
            icon: icon(setting),
            iconBackgroundColor: color(setting),
            iconBackgroundGradientStart: gradientStart(setting),
            iconBackgroundGradientEnd: gradientEnd(setting),
            title: title(setting),
            isShowingSubtitle: doesHaveValue(setting),
            subtitle: value(setting),
            isSubtitleLocalized: false,
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
        AccountOneSettingsView()
    }
    .listStyle(.insetGrouped)
    .localizedNavigationTitle(title: "Account")
    .navigationDestination(for: NT_AccountSetting.self) { setting in
        PlaceholderView(title: setting.title)
    }
    .navigationStack()
}
