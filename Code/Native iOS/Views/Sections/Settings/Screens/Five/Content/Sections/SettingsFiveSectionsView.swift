//
//  SettingsFiveSectionsView.swift
//  Native
//

import SwiftUI

struct SettingsFiveSectionsView: View {
    
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

private extension SettingsFiveSectionsView {
    private var sectionsContent: some View {
        ForEach(
            sections,
            content: SettingsFiveSectionView.init
        )
    }
}

// MARK: - Preview:

#Preview {
    List {
        SettingsFiveSectionsView()
    }
    .listStyle(.plain)
    .localizedNavigationTitle(title: "Settings")
    .navigationDestination(for: NT_Setting.self) { setting in
        PlaceholderView(title: setting.title)
    }
    .navigationStack()
}
