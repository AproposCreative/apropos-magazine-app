//
//  TermsThreeSectionsView.swift
//  Native
//

import SwiftUI

struct TermsThreeSectionsView: View {
    
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
        sectionsContent
            .headerProminence(.increased)
    }
}

// MARK: - Sections:

private extension TermsThreeSectionsView {
    private var sectionsContent: some View {
        ForEach(
            sections,
            content: section
        )
    }
    
    private func section(_ section: NT_TermsSection) -> some View {
        Section(title(section)) {
            sectionContent(section)
        }
    }
    
    private func sectionContent(_ section: NT_TermsSection) -> some View {
        Text(content(section))
            .font(.subheadline)
            .multilineTextAlignment(.leading)
            .foregroundStyle(.secondary)
            .padding(
                .vertical,
                2
            )
    }
}

// MARK: - Preview:

#Preview {
    List {
        TermsThreeSectionsView(sections: .init(NT_TermsSection.example.prefix(3)))
    }
    .listStyle(.insetGrouped)
    .localizedNavigationTitle(title: "Terms of Service")
    .navigationStack()
}
