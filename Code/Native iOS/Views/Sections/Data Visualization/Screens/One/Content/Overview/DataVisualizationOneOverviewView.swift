//
//  DataVisualizationOneOverviewView.swift
//  Native
//

import SwiftUI

struct DataVisualizationOneOverviewView: View {
    
    // MARK: - Properties:
    
    /// Size of the dynamic type that is currently selected:
    @Environment(\.dynamicTypeSize) var dynamicTypeSize
    
    /// An array of the overview items to display:
    let overviewItems: [NT_Overview]
    
    init(overviewItems: [NT_Overview]) {
        
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
            overviewItemsContent
        }
    }
}

// MARK: - Overview items:

private extension DataVisualizationOneOverviewView {
    private var overviewItemsContent: some View {
        VStack(
            alignment: .leading,
            spacing: 16
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
    
    private func overviewItem(_ overviewItem: NT_Overview) -> some View {
        NavigationLink(value: overviewItem) {
            overviewItemLabel(overviewItem)
        }
    }
    
    private func overviewItemLabel(_ overviewItem: NT_Overview) -> some View {
        IconBackgroundTitleSubtitleValueIconView(
            icon: icon(overviewItem),
            iconColor: color(overviewItem),
            iconGradientStart: gradientStart(overviewItem),
            iconGradientEnd: gradientEnd(overviewItem),
            isShowingIconBackground: false,
            iconSize: .twentyFourPixels,
            title: title(overviewItem),
            value: value(overviewItem),
            subtitle: description(overviewItem),
            secondIconFrame: secondIconFrame,
            backgroundColor: .init(.secondarySystemBackground)
        )
    }
}

// MARK: - Preview:

#Preview {
    ScrollView {
        DataVisualizationOneOverviewView(overviewItems: NT_Overview.example)
    }
    .safeAreaPadding(
        .all,
        16
    )
    .safeAreaPadding(
        .bottom,
        16
    )
    .localizedNavigationTitle(title: "Overview")
    .navigationDestination(for: NT_Overview.self) { overviewItem in
        PlaceholderView(title: overviewItem.title)
    }
    .navigationStack()
}
