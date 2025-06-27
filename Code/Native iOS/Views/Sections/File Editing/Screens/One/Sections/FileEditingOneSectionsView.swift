//
//  FileEditingOneSectionsView.swift
//  Native
//

import SwiftUI

struct FileEditingOneSectionsView: View {
    
    // MARK: - Properties:
    
    /// An array of the sections to display:
    let sections: [NT_DesignToolSection]
    
    init(sections: [NT_DesignToolSection]) {
        
        /// Properties initialization:
        self.sections = sections
    }
    
    // MARK: - View:
    
    var body: some View {
        content
    }
    
    @ViewBuilder
    private var content: some View {
        if isShowing {
            item
        }
    }
}

// MARK: - Item:

private extension FileEditingOneSectionsView {
    private var item: some View {
        Section {
            sectionsContent
        }
    }
}

// MARK: - Sections:

private extension FileEditingOneSectionsView {
    private var sectionsContent: some View {
        ForEach(
            sections,
            content: section
        )
    }
    
    private func section(_ section: NT_DesignToolSection) -> some View {
        NavigationLink(value: section) {
            sectionLabel(section)
        }
    }
    
    private func sectionLabel(_ section: NT_DesignToolSection) -> some View {
        LabelView(
            icon: icon(section),
            title: title(section),
            isShowingBadge: true,
            badge: filesCount(section),
            isBadgeLocalized: false
        )
    }
}

// MARK: - Preview:

#Preview {
    List {
        FileEditingOneSectionsView(sections: NT_DesignToolSection.example)
    }
    .listStyle(.insetGrouped)
    .localizedNavigationTitle(
        title: "AppLayouts",
        isLocalized: false
    )
    .navigationDestination(for: NT_DesignToolSection.self) { section in
        PlaceholderView(title: section.title)
    }
    .navigationStack()
}
