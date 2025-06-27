//
//  TermsOneSectionsView.swift
//  Native
//

import SwiftUI

struct TermsOneSectionsView: View {
    
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

private extension TermsOneSectionsView {
    private var sectionsContent: some View {
        ForEach(
            sections,
            content: section
        )
    }
    
    private func section(_ section: NT_TermsSection) -> some View {
        VStack(
            alignment: .leading,
            spacing: sectionsSpacing
        ) {
            sectionContent(section)
        }
    }
    
    @ViewBuilder
    private func sectionContent(_ section: NT_TermsSection) -> some View {
        SectionHeaderView(title: title(section))
        subsectionsContent(section)
    }
}

// MARK: - Sub-sections:

private extension TermsOneSectionsView {
    private func subsectionsContent(_ section: NT_TermsSection) -> some View {
        LazyVStack(
            alignment: .leading,
            spacing: sectionsSpacing
        ) {
            subsectionsItem(section)
        }
    }
    
    private func subsectionsItem(_ section: NT_TermsSection) -> some View {
        ForEach(
            subsections(section),
            content: subsection
        )
    }
    
    private func subsection(_ subsection: NT_TermsSubsection) -> some View {
        TitleSubtitleExpandableView(
            title: title(subsection),
            isTitleLocalized: false,
            subtitle: content(subsection),
            isSubtitleLocalized: false
        )
    }
}

// MARK: - Preview:

#Preview {
    ScrollView {
        TermsOneSectionsView(sections: NT_TermsSection.example)
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
