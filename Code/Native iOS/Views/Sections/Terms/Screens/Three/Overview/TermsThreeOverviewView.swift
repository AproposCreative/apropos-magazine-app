//
//  TermsThreeOverviewView.swift
//  Native
//

import SwiftUI

struct TermsThreeOverviewView: View {
    
    // MARK: - Properties:
    
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
    
    @ViewBuilder
    private var content: some View {
        if isShowing {
            mainContent
        }
    }
    
    private var mainContent: some View {
        item
            .headerProminence(.increased)
    }
}

// MARK: - Item:

private extension TermsThreeOverviewView {
    private var item: some View {
        Section("Overview") {
            overviewItemsContent
        }
    }
}

// MARK: - Overview items:

private extension TermsThreeOverviewView {
    private var overviewItemsContent: some View {
        ForEach(
            overviewItems,
            content: overviewItem
        )
    }
    
    private func overviewItem(_ overviewItem: NT_TermsOverview) -> some View {
        LabelView(
            icon: icon(overviewItem),
            title: title(overviewItem),
            isShowingBadge: true,
            badge: value(overviewItem),
            isBadgeLocalized: false
        )
    }
}

// MARK: - Preview:

#Preview {
    List {
        TermsThreeOverviewView(overviewItems: NT_TermsOverview.example)
    }
    .listStyle(.insetGrouped)
    .localizedNavigationTitle(title: "Terms of Service")
    .navigationStack()
}
