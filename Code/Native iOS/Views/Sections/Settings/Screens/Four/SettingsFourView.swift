//
//  SettingsFourView.swift
//  Native
//

import SwiftUI

struct SettingsFourView: View {
    
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

private extension SettingsFourView {
    private var list: some View {
        listContent
            .listStyle(.insetGrouped)
    }
    
    private var listContent: some View {
        List {
            listItem
        }
    }
    
    @ViewBuilder
    private var listItem: some View {
        SettingsFourBannerView()
        SettingsFourSectionsView()
    }
}

// MARK: - Setting:

private extension SettingsFourView {
    private func setting(_ setting: NT_Setting) -> some View {
        PlaceholderView(title: title(setting))
    }
}

// MARK: - Preview:

#Preview {
    SettingsFourView()
}
