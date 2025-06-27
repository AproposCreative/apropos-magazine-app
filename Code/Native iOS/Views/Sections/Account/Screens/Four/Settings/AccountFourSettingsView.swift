//
//  AccountFourSettingsView.swift
//  Native
//

import SwiftUI

struct AccountFourSettingsView: View {
    
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

private extension AccountFourSettingsView {
    private var sectionsContent: some View {
        ForEach(
            sections,
            content: AccountFourSettingsSectionView.init
        )
    }
}

// MARK: - Preview:

#Preview {
    List {
        AccountFourSettingsView()
    }
    .listStyle(.plain)
    .localizedNavigationTitle(title: "Account")
    .navigationDestination(for: NT_AccountSetting.self) { setting in
        PlaceholderView(title: setting.title)
    }
    .navigationStack()
}
