//
//  SettingsTwoView.swift
//  Native
//

import SwiftUI

struct SettingsTwoView: View {
    
    // MARK: - Private properties:
    
    /// Dismisses the view:
    @Environment(\.dismiss) private var dismiss
    
    // MARK: - View:
    
    var body: some View {
        content
    }
    
    private var content: some View {
        list
            .localizedNavigationTitle(title: "Settings")
            .toolbarButton(
                title: "Done",
                action: dismiss.callAsFunction
            )
            .navigationDestination(
                for: NT_Setting.self,
                destination: setting
            )
            .navigationStack()
    }
}

// MARK: - List:

private extension SettingsTwoView {
    private var list: some View {
        listContent
            .listStyle(.plain)
    }
    
    private var listContent: some View {
        List {
            SettingsTwoSectionsView()
        }
    }
}

// MARK: - Setting:

private extension SettingsTwoView {
    private func setting(_ setting: NT_Setting) -> some View {
        PlaceholderView(title: title(setting))
    }
}

// MARK: - Preview:

#Preview {
    SettingsTwoView()
}
