//
//  AccountFiveSettingsView.swift
//  Native
//

import SwiftUI

struct AccountFiveSettingsView: View {
    
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

private extension AccountFiveSettingsView {
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

private extension AccountFiveSettingsView {
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
        LabelView(
            icon: icon(setting),
            iconColor: color(setting),
            iconGradientStart: gradientStart(setting),
            iconGradientEnd: gradientEnd(setting),
            title: title(setting)
        )
    }
}

// MARK: - Preview:

#Preview {
    List {
        AccountFiveSettingsView()
    }
    .listStyle(.insetGrouped)
    .localizedNavigationTitle(title: "Account")
    .navigationDestination(for: NT_AccountSetting.self) { setting in
        PlaceholderView(title: setting.title)
    }
    .navigationStack()
}
