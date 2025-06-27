//
//  FileEditingThreeSectionsView.swift
//  Native
//

import SwiftUI

struct FileEditingThreeSectionsView: View {
    
    // MARK: - Properties:
    
    /// An array of the sections to display:
    let sections: [NT_WhiteboardSection]
    
    init(sections: [NT_WhiteboardSection]) {
        
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

private extension FileEditingThreeSectionsView {
    private var item: some View {
        Section {
            sectionsContent
        }
    }
}

// MARK: - Sections:

private extension FileEditingThreeSectionsView {
    private var sectionsContent: some View {
        ForEach(
            sections,
            content: section
        )
    }
    
    private func section(_ section: NT_WhiteboardSection) -> some View {
        NavigationLink(value: section) {
            sectionLabel(section)
        }
    }
    
    private func sectionLabel(_ section: NT_WhiteboardSection) -> some View {
        LabelView(
            icon: icon(section),
            title: title(section),
            isShowingBadge: true,
            badge: boardsCount(section),
            isBadgeLocalized: false
        )
    }
}

// MARK: - Preview:

#Preview {
    List {
        FileEditingThreeSectionsView(sections: NT_WhiteboardSection.example)
    }
    .listStyle(.insetGrouped)
    .localizedNavigationTitle(
        title: "AppLayouts",
        isLocalized: false
    )
    .navigationDestination(for: NT_WhiteboardSection.self) { section in
        PlaceholderView(title: section.title)
    }
    .navigationStack()
}
