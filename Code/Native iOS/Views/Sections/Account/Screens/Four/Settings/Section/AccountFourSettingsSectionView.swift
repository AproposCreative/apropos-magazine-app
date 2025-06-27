//
//  AccountFourSettingsSectionView.swift
//  Native
//

import SwiftUI

struct AccountFourSettingsSectionView: View {
    
    // MARK: - Properties:
    
    /// Section to display the settings for:
    let section: NT_AccountSettingsSection
    
    // MARK: - Private properties:
    
    /// 'Bool' value indicating whether or not the content of the section should be expanded:
    @State private var isExpanded: Bool = true
    
    /// 'Bool' value indicating whether or not the notifications should be enabled:
    @State private var isNotificationsEnabled: Bool = true
    
    init(section: NT_AccountSettingsSection) {
        
        /// Properties initialization:
        self.section = section
    }
    
    // MARK: - View:
    
    var body: some View {
        content
    }
    
    private var content: some View {
        Section(isExpanded: $isExpanded) {
            settingsContent
        } header: {
            header
        }
    }
}

// MARK: - Header:

private extension AccountFourSettingsSectionView {
    private var header: some View {
        ExpandableHeaderView(
            isExpanded: $isExpanded,
            title: title
        )
    }
}

// MARK: - Settings:

private extension AccountFourSettingsSectionView {
    private var settingsContent: some View {
        ForEach(
            settings,
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
        AccountFourSettingsSectionView(section: .details)
    }
    .listStyle(.plain)
    .localizedNavigationTitle(title: "Account")
    .navigationDestination(for: NT_AccountSetting.self) { setting in
        PlaceholderView(title: setting.title)
    }
    .navigationStack()
}
