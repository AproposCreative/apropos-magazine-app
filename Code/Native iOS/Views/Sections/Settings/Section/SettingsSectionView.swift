//
//  SettingsSectionView.swift
//  Native
//

import SwiftUI

struct SettingsSectionView: View {
    
    // MARK: - Properties:
    
    /// Screen that is currently shown (Can be 'nil' or no screen at all):
    @State var currentScreen: NT_SettingsScreen? = nil
    
    // MARK: - View:
    
    var body: some View {
        content
    }
    
    private var content: some View {
        list
            .navigationTitle("Settings")
            .sheet(
                item: $currentScreen,
                content: showScreen
            )
    }
}

// MARK: - List:

private extension SettingsSectionView {
    private var list: some View {
        listContent
            .listStyle(.insetGrouped)
    }
    
    private var listContent: some View {
        List {
            screensContent
        }
    }
}

// MARK: - Screens:

private extension SettingsSectionView {
    private var screensContent: some View {
        ForEach(
            screens,
            content: screen
        )
    }
    
    private func screen(_ screen: NT_SettingsScreen) -> some View {
        SettingsSectionRowView(
            screen: screen,
            viewAction: view
        )
    }
}

// MARK: - Screen:

private extension SettingsSectionView {
    @ViewBuilder
    private func showScreen(_ screen: NT_SettingsScreen) -> some View {
        switch screen {
        case .first: SettingsOneView()
        case .second: SettingsTwoView()
        case .third: SettingsThreeView()
        case .fourth: SettingsFourView()
        case .fifth: SettingsFiveView()
        }
    }
}

// MARK: - Preview:

#Preview {
    SettingsSectionView()
}
