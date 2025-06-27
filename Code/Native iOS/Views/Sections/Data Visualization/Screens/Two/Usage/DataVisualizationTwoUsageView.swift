//
//  DataVisualizationTwoUsageView.swift
//  Native
//

import SwiftUI

struct DataVisualizationTwoUsageView: View {
    
    // MARK: - Properties:
    
    /// Size of the dynamic type that is currently selected:
    @Environment(\.dynamicTypeSize) var dynamicTypeSize
    
    /// An array of the usage items to display:
    let usageItems: [NT_Usage]
    
    init(usageItems: [NT_Usage]) {
        
        /// Properties initialization:
        self.usageItems = usageItems
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

private extension DataVisualizationTwoUsageView {
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
        SectionHeaderView(title: "Usage")
        usageItemsContent
    }
}

// MARK: - Usage items:

private extension DataVisualizationTwoUsageView {
    private var usageItemsContent: some View {
        LazyVGrid(
            columns: columns,
            alignment: .leading,
            spacing: spacing
        ) {
            usageItemsItem
        }
    }
    
    private var usageItemsItem: some View {
        ForEach(
            usageItems,
            content: usageItem
        )
    }
    
    private func usageItem(_ usageItem: NT_Usage) -> some View {
        IconBackgroundTitleSubtitleProgressView(
            icon: icon(usageItem),
            iconBackgroundColor: color(usageItem),
            iconBackgroundGradientStart: gradientStart(usageItem),
            iconBackgroundGradientEnd: gradientEnd(usageItem),
            title: title(usageItem),
            subtitle: totalValueString(usageItem),
            progressValue: usedValue(usageItem),
            progressTotal: totalValue(usageItem),
            isShowingProgressValueTitle: true,
            progressValueTitle: usedValueString(usageItem),
            progressColor: color(usageItem),
            alignment: .vertical,
            maxHeight: .infinity
        )
    }
}

// MARK: - Preview:

#Preview {
    ScrollView {
        DataVisualizationTwoUsageView(usageItems: NT_Usage.example)
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
    .localizedNavigationTitle(title: "Overview")
    .navigationStack()
}
