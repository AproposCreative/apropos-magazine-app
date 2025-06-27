//
//  SettingsOneContentView.swift
//  Native
//

import SwiftUI

struct SettingsOneContentView: View {
    
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

private extension SettingsOneContentView {
    private var list: some View {
        listContent
            .listStyle(.insetGrouped)
    }
    
    private var listContent: some View {
        List {
            SettingsOneSectionsView()
        }
    }
}

// MARK: - Setting:

private extension SettingsOneContentView {
    private func setting(_ setting: NT_Setting) -> some View {
        PlaceholderView(title: title(setting))
    }
}

// MARK: - Preview:

#Preview {
    SettingsOneContentView()
}
