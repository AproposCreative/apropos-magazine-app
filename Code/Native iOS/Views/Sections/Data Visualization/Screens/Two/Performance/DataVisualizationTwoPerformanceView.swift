//
//  DataVisualizationTwoPerformanceView.swift
//  Native
//

import SwiftUI

struct DataVisualizationTwoPerformanceView: View {
    
    // MARK: - Properties:
    
    /// An array of the performance items to display:
    let performanceItems: [NT_Performance]
    
    // MARK: - Private properties:
    
    /// Performance item that is currently shown:
    @Binding private var currentPerformanceItem: NT_Performance?
    
    init(
        performanceItems: [NT_Performance],
        currentPerformanceItem: Binding<NT_Performance?>
    ) {
        
        /// Properties initialization:
        self.performanceItems = performanceItems
        _currentPerformanceItem = currentPerformanceItem
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

private extension DataVisualizationTwoPerformanceView {
    private var item: some View {
        VStack(
            alignment: .center,
            spacing: 16
        ) {
            itemContent
        }
    }
    
    @ViewBuilder
    private var itemContent: some View {
        SectionHeaderView(title: "Performance")
        scroll
        pagination
    }
}

// MARK: - Scroll:

private extension DataVisualizationTwoPerformanceView {
    private var scroll: some View {
        scrollContent
            .scrollIndicators(.hidden)
            .scrollTargetBehavior(.viewAligned)
            .scrollPosition(id: $currentPerformanceItem)
    }
    
    private var scrollContent: some View {
        ScrollView(.horizontal) {
            scrollItem
        }
    }
    
    private var scrollItem: some View {
        performanceItemsContent
            .scrollTargetLayout()
    }
}

// MARK: - Performance items:

private extension DataVisualizationTwoPerformanceView {
    private var performanceItemsContent: some View {
        LazyHStack(
            alignment: .top,
            spacing: 32
        ) {
            performanceItemsItem
        }
    }
    
    private var performanceItemsItem: some View {
        ForEach(
            performanceItems,
            content: performanceItem
        )
    }
    
    private func performanceItem(_ performanceItem: NT_Performance) -> some View {
        performanceItemContent(performanceItem)
            .containerRelativeFrame(.horizontal)
            .id(performanceItem)
    }
    
    private func performanceItemContent(_ performanceItem: NT_Performance) -> some View {
        BarChartView(
            isShowingHeader: false,
            bars: bars(performanceItem),
            chartAlignment: .vertical,
            chartHeight: 276
        ) {
            
        }
    }
}

// MARK: - Pagination:

private extension DataVisualizationTwoPerformanceView {
    private var pagination: some View {
        PaginationView(
            current: $currentPerformanceItem,
            all: performanceItems
        )
    }
}

// MARK: - Preview:

#Preview {
    @Previewable @State var currentPerformanceItem: NT_Performance? = .example.first
    
    ScrollView {
        DataVisualizationTwoPerformanceView(
            performanceItems: NT_Performance.example,
            currentPerformanceItem: $currentPerformanceItem
        )
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
