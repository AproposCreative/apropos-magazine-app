//
//  SettingsFiveSectionView.swift
//  Native
//

import SwiftUI

struct SettingsFiveSectionView: View {
    
    // MARK: - Properties:
    
    /// Section to display the settings for:
    let section: NT_SettingsSection
    
    // MARK: - Private properties:
    
    /// 'Bool' value indicating whether or not the content of the section should be expanded:
    @State private var isExpanded: Bool = true
    
    /// 'Bool' value indicating whether or not the haptic feedbacks should be enabled:
    @State private var isHapticFeedbacksEnabled: Bool = true
    
    init(section: NT_SettingsSection) {
        
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

private extension SettingsFiveSectionView {
    private var header: some View {
        ExpandableHeaderView(
            isExpanded: $isExpanded,
            title: title
        )
    }
}

// MARK: - Settings:

private extension SettingsFiveSectionView {
    private var settingsContent: some View {
        ForEach(
            settings,
            content: setting
        )
    }
    
    @ViewBuilder
    private func setting(_ setting: NT_Setting) -> some View {
        if isToggle(setting) {
            settingToggle(setting)
        } else {
            settingLink(setting)
        }
    }
    
    private func settingToggle(_ setting: NT_Setting) -> some View {
        Toggle(isOn: $isHapticFeedbacksEnabled) {
            settingLabel(setting)
        }
    }
    
    private func settingLink(_ setting: NT_Setting) -> some View {
        NavigationLink(value: setting) {
            settingLabel(setting)
        }
    }
    
    private func settingLabel(_ setting: NT_Setting) -> some View {
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
        SettingsFiveSectionView(section: .customization)
    }
    .listStyle(.plain)
    .localizedNavigationTitle(title: "Settings")
    .navigationDestination(for: NT_Setting.self) { setting in
        PlaceholderView(title: setting.title)
    }
    .navigationStack()
}
