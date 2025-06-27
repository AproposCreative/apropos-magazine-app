//
//  MainFourSectionsView.swift
//  Native
//

import SwiftUI

struct MainFourSectionsView: View {
    
    // MARK: - Properties:
    
    /// Size of the dynamic type that is currently selected:
    @Environment(\.dynamicTypeSize) var dynamicTypeSize
    
    /// An array of the sections with the news to display:
    let sections: [NT_NewsSection]
    
    // MARK: - Private properties:
    
    /// Namespace that is needed for the zoom transition:
    @Namespace private var namespace
    
    init(sections: [NT_NewsSection]) {
        
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
            sectionsContent
        }
    }
}

// MARK: - Sections:

private extension MainFourSectionsView {
    private var sectionsContent: some View {
        VStack(
            alignment: .leading,
            spacing: 48
        ) {
            sectionsItem
        }
    }
    
    private var sectionsItem: some View {
        ForEach(
            sections,
            content: section
        )
    }
    
    @ViewBuilder
    private func section(_ section: NT_NewsSection) -> some View {
        if !isEmpty(section) {
            sectionContent(section)
        }
    }
    
    private func sectionContent(_ section: NT_NewsSection) -> some View {
        VStack(
            alignment: .leading,
            spacing: sectionSpacing
        ) {
            sectionItem(section)
        }
    }
    
    @ViewBuilder
    private func sectionItem(_ section: NT_NewsSection) -> some View {
        sectionHeader(section)
        articlesContent(section)
    }
    
    @ViewBuilder
    private func sectionHeader(_ section: NT_NewsSection) -> some View {
        if !isToday(section) {
            sectionHeaderContent(section)
        }
    }
    
    private func sectionHeaderContent(_ section: NT_NewsSection) -> some View {
        SectionHeaderView(
            title: title(section),
            isTitleLocalized: false,
            titleFont: .title2.bold()
        )
    }
}

// MARK: - Articles:

private extension MainFourSectionsView {
    private func articlesContent(_ section: NT_NewsSection) -> some View {
        LazyVGrid(
            columns: columns,
            alignment: .leading,
            spacing: sectionSpacing
        ) {
            articlesItem(section)
        }
    }
    
    private func articlesItem(_ section: NT_NewsSection) -> some View {
        ForEach(
            articles(section),
            content: article
        )
    }
    
    private func article(_ article: NT_NewsArticle) -> some View {
        articleContent(article)
            .matchedTransitionSource(
                id: identifier(article),
                in: namespace
            )
    }
    
    private func articleContent(_ article: NT_NewsArticle) -> some View {
        NavigationLink {
            articleItem(article)
        } label: {
            articleLabel(article)
        }
    }
    
    private func articleItem(_ article: NT_NewsArticle) -> some View {
        PlaceholderView(title: title(article))
            .navigationTransition(
                .zoom(
                    sourceID: identifier(article),
                    in: namespace
                )
            )
    }
    
    private func articleLabel(_ article: NT_NewsArticle) -> some View {
        SubtitleTitleImageBackgroundView(
            subtitle: subtitle(article),
            title: title(article),
            image: image(article),
            imageHeight: imageHeight
        )
    }
}

// MARK: - Preview:

#Preview {
    ScrollView {
        MainFourSectionsView(sections: NT_NewsSection.example)
    }
    .safeAreaPadding(
        .all,
        16
    )
    .safeAreaPadding(
        .bottom,
        16
    )
    .localizedNavigationTitle(title: "News")
    .navigationStack()
}
