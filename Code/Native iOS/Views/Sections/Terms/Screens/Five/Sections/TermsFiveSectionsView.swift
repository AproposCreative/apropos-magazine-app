//
//  TermsFiveSectionsView.swift
//  Native
//

import SwiftUI

struct TermsFiveSectionsView: View {
    
    // MARK: - Properties:
    
    /// An array of the sections with the terms to display:
    let sections: [NT_TermsSection]
    
    init(sections: [NT_TermsSection]) {
        
        /// Properties initialization:
        self.sections = sections
    }
    
    // MARK: - View:
    
    var body: some View {
        content
    }
    
    private var content: some View {
        LazyVStack(
            alignment: .leading,
            spacing: 32
        ) {
            sectionsContent
        }
    }
}

// MARK: - Sections:

private extension TermsFiveSectionsView {
    private var sectionsContent: some View {
        ForEach(
            sections,
            content: section
        )
    }
    
    private func section(_ section: NT_TermsSection) -> some View {
        VStack(
            alignment: .leading,
            spacing: 16
        ) {
            sectionContent(section)
        }
    }
    
    @ViewBuilder
    private func sectionContent(_ section: NT_TermsSection) -> some View {
        sectionHeader(section)
        sectionItem(section)
    }
    
    private func sectionHeader(_ section: NT_TermsSection) -> some View {
        SectionHeaderView(
            title: title(section),
            isTitleLocalized: false
        )
    }
    
    private func sectionItem(_ section: NT_TermsSection) -> some View {
        Text(content(section))
            .font(.body)
            .multilineTextAlignment(.leading)
            .foregroundStyle(.secondary)
            .contentBackground()
    }
}

// MARK: - Preview:

#Preview {
    ScrollView {
        TermsFiveSectionsView(sections: .init(NT_TermsSection.example.prefix(3)))
    }
    .safeAreaPadding(
        .all,
        16
    )
    .safeAreaPadding(
        .bottom,
        16
    )
    .background(Color(.systemGroupedBackground))
    .localizedNavigationTitle(title: "Terms of Service")
    .navigationStack()
}
