//
//  TermsTwoSectionsView.swift
//  Native
//

import SwiftUI

struct TermsTwoSectionsView: View {
    
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
            spacing: 24
        ) {
            sectionsContent
        }
    }
}

// MARK: - Sections:

private extension TermsTwoSectionsView {
    private var sectionsContent: some View {
        ForEach(
            sections,
            content: section
        )
    }
    
    private func section(_ section: NT_TermsSection) -> some View {
        VStack(
            alignment: .leading,
            spacing: 12
        ) {
            sectionContent(section)
        }
    }
    
    @ViewBuilder
    private func sectionContent(_ section: NT_TermsSection) -> some View {
        sectionItem(section)
        DividerView()
    }
    
    private func sectionItem(_ section: NT_TermsSection) -> some View {
        TitleSubtitleExpandableView(
            title: title(section),
            isTitleLocalized: false,
            titleFont: .title3.bold(),
            subtitle: content(section),
            isSubtitleLocalized: false,
            subtitleFont: .body,
            expandButtonIconSize: expandButtonIconSize,
            spacing: 6,
            verticalPadding: 0,
            horizontalPadding: 0,
            isShowingBackground: false,
            cornerRadius: 0
        )
    }
}

// MARK: - Preview:

#Preview {
    ScrollView {
        TermsTwoSectionsView(sections: NT_TermsSection.example)
    }
    .safeAreaPadding(
        .all,
        16
    )
    .safeAreaPadding(
        .bottom,
        16
    )
    .localizedNavigationTitle(title: "Terms of Service")
    .navigationStack()
}
