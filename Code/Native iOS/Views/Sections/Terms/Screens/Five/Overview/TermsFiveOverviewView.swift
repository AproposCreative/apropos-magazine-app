//
//  TermsFiveOverviewView.swift
//  Native
//

import SwiftUI

struct TermsFiveOverviewView: View {
    
    // MARK: - Properties:
    
    /// Size of the dynamic type that is currently selected:
    @Environment(\.dynamicTypeSize) var dynamicTypeSize
    
    /// An array of the overview items to display:
    let overviewItems: [NT_TermsOverview]
    
    init(overviewItems: [NT_TermsOverview]) {
        
        /// Properties initialization:
        self.overviewItems = overviewItems
    }
    
    // MARK: - View:
    
    var body: some View {
        content
    }
    
    private var content: some View {
        LazyVStack(
            alignment: .leading,
            spacing: 16
        ) {
            overviewItemsContent
        }
    }
}

// MARK: - Overview items:

private extension TermsFiveOverviewView {
    private var overviewItemsContent: some View {
        ForEach(
            overviewItems,
            content: overviewItem
        )
    }
    
    @ViewBuilder
    private func overviewItem(_ overviewItem: NT_TermsOverview) -> some View {
        if let url: URL = url(overviewItem) {
            overviewItemLink(
                overviewItem,
                forURL: url
            )
        } else {
            overviewLabel(overviewItem)
        }
    }
    
    private func overviewItemLink(
        _ overviewItem: NT_TermsOverview,
        forURL url: URL
    ) -> some View {
        Link(destination: url) {
            overviewLabel(overviewItem)
        }
    }
    
    private func overviewLabel(_ overviewItem: NT_TermsOverview) -> some View {
        IconBackgroundTitleSubtitleIconView(
            icon: icon(overviewItem),
            isIconColorGradient: true,
            isShowingIconBackground: false,
            iconSize: .twentyFourPixels,
            title: title(overviewItem),
            subtitle: value(overviewItem),
            isSubtitleLocalized: false,
            isShowingSecondIcon: doesHaveURL(overviewItem),
            secondIconFrame: secondIconFrame,
            titleSubtitleSecondIconAlignment: .center
        )
    }
}

// MARK: - Preview:

#Preview {
    ScrollView {
        TermsFiveOverviewView(overviewItems: NT_TermsOverview.example)
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
