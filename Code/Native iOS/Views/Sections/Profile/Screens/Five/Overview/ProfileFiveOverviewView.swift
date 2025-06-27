//
//  ProfileFiveOverviewView.swift
//  Native
//

import SwiftUI

struct ProfileFiveOverviewView: View {
    
    // MARK: - Properties:
    
    /// Size of the dynamic type that is currently selected:
    @Environment(\.dynamicTypeSize) var dynamicTypeSize
    
    /// Author to display the overview for:
    let author: NT_ProfileAuthor
    
    init(author: NT_ProfileAuthor) {
        
        /// Properties initialization:
        self.author = author
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

private extension ProfileFiveOverviewView {
    private var item: some View {
        VStack(
            alignment: .leading,
            spacing: spacing
        ) {
            itemContent
        }
    }
    
    @ViewBuilder
    private var itemContent: some View {
        SectionHeaderView(title: "Overview")
        overviewItemsContent
    }
}

// MARK: - Overview items:

private extension ProfileFiveOverviewView {
    private var overviewItemsContent: some View {
        LazyVGrid(
            columns: columns,
            alignment: .leading,
            spacing: spacing
        ) {
            overviewItemsItem
        }
    }
    
    private var overviewItemsItem: some View {
        ForEach(
            overviewItems,
            content: overviewItem
        )
    }
    
    private func overviewItem(_ overviewItem: NT_ProfileAuthorOverview) -> some View {
        IconBackgroundTitleSubtitleView(
            icon: icon(overviewItem),
            iconBackgroundColor: color(overviewItem),
            iconBackgroundGradientStart: gradientStart(overviewItem),
            iconBackgroundGradientEnd: gradientEnd(overviewItem),
            iconSize: .thirtyTwoPixels,
            title: value(overviewItem),
            isTitleLocalized: false,
            subtitle: title(overviewItem),
            alignment: .vertical,
            maxHeight: .infinity
        )
    }
}

// MARK: - Preview:

#Preview {
    ScrollView {
        ProfileFiveOverviewView(author: .example)
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
    .localizedNavigationTitle(title: "Profile")
    .navigationStack()
}
