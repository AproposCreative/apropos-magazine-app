//
//  SettingsTwoSectionsView.swift
//  Native
//

import SwiftUI

struct SettingsTwoSectionsView: View {
    
    // MARK: - Private properties:
    
    /// 'Bool' value indicating whether or not the haptic feedbacks should be enabled:
    @State private var isHapticFeedbacksEnabled: Bool = true
    
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

private extension SettingsTwoSectionsView {
    private var sectionsContent: some View {
        ForEach(
            sections,
            content: section
        )
    }
    
    private func section(_ section: NT_SettingsSection) -> some View {
        Section(title(section)) {
            settingsContent(section)
        }
    }
}

// MARK: - Settings:

private extension SettingsTwoSectionsView {
    private func settingsContent(_ section: NT_SettingsSection) -> some View {
        ForEach(
            settings(section),
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
        SettingsTwoSectionsView()
    }
    .listStyle(.plain)
    .localizedNavigationTitle(title: "Settings")
    .navigationDestination(for: NT_Setting.self) { setting in
        PlaceholderView(title: setting.title)
    }
    .navigationStack()
}
