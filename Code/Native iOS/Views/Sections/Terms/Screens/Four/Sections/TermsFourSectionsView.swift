//
//  TermsFourSectionsView.swift
//  Native
//

import SwiftUI

struct TermsFourSectionsView: View {
    
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

private extension TermsFourSectionsView {
    private var sectionsContent: some View {
        ForEach(
            sections,
            content: section
        )
    }
    
    private func section(_ section: NT_TermsSection) -> some View {
        sectionContent(section)
            .accessibilityElement(children: .combine)
    }
    
    private func sectionContent(_ section: NT_TermsSection) -> some View {
        VStack(
            alignment: .leading,
            spacing: 6
        ) {
            sectionItem(section)
        }
    }
    
    @ViewBuilder
    private func sectionItem(_ section: NT_TermsSection) -> some View {
        sectionHeader(section)
        sectionItemContent(section)
    }
    
    private func sectionHeader(_ section: NT_TermsSection) -> some View {
        SectionHeaderView(
            title: title(section),
            isTitleLocalized: false
        )
    }
    
    private func sectionItemContent(_ section: NT_TermsSection) -> some View {
        Text(content(section))
            .font(.body)
            .multilineTextAlignment(.leading)
            .foregroundStyle(.secondary)
    }
}

// MARK: - Preview:

#Preview {
    ScrollView {
        TermsFourSectionsView(sections: .init(NT_TermsSection.example.prefix(3)))
    }
    .safeAreaPadding(
        .all,
        16
    )
    .safeAreaPadding(
        .bottom,
        16
    )
    .localizedNavigationTitle(title: "Privacy Policy")
    .navigationStack()
}
