//
//  SettingsThreeContentView.swift
//  Native
//

import SwiftUI

struct SettingsThreeContentView: View {
    
    // MARK: - View:
    
    var body: some View {
        content
    }
    
    private var content: some View {
        list
            .localizedNavigationTitle(title: "Settings")
            .navigationDestination(
                for: NT_Setting.self,
                destination: setting
            )
            .navigationStack()
    }
}

// MARK: - List:

private extension SettingsThreeContentView {
    private var list: some View {
        listContent
            .listStyle(.plain)
    }
    
    private var listContent: some View {
        List {
            listItem
        }
    }
    
    @ViewBuilder
    private var listItem: some View {
        SettingsThreeBannerView()
        SettingsThreeSectionsView()
    }
}

// MARK: - Setting:

private extension SettingsThreeContentView {
    private func setting(_ setting: NT_Setting) -> some View {
        PlaceholderView(title: title(setting))
    }
}

// MARK: - Preview:

#Preview {
    SettingsThreeContentView()
}
