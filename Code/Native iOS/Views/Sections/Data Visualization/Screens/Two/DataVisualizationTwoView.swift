//
//  DataVisualizationTwoView.swift
//  Native
//

import SwiftUI

struct DataVisualizationTwoView: View {
    
    // MARK: - Properties:
    
    /// An array of the usage items to display:
    @State var usageItems: [NT_Usage] = []
    
    /// An array of the performance items to display:
    @State var performanceItems: [NT_Performance] = []
    
    /// Performance item that is currently shown:
    @State var currentPerformanceItem: NT_Performance? = nil
    
    /// 'Bool' value indicating whether or not the data is currently being fetched:
    @State var isFetching: Bool = true
    
    // MARK: - View:
    
    var body: some View {
        content
    }
    
    private var content: some View {
        scroll
            .background(backgroundColor)
            .localizedNavigationTitle(title: "Overview")
            .toolbarButton(
                title: "Settings",
                icon: Icons.gearshape,
                iconSymbolVariant: .none,
                font: .body,
                style: .iconOnly,
                placement: .cancellationAction,
                action: showSettings
            )
            .toolbarAvatar(indicatorBorderColor: backgroundColor)
            .animation(
                .default,
                value: usageItems
            )
            .animation(
                .default,
                value: performanceItems
            )
            .animation(
                .default,
                value: currentPerformanceItem
            )
            .animation(
                .default,
                value: isFetching
            )
            .task {
                await fetchData()
            }
            .navigationStack()
    }
}

// MARK: - Scroll:

private extension DataVisualizationTwoView {
    private var scroll: some View {
        scrollContent
            .safeAreaPadding(
                .all,
                16
            )
            .safeAreaPadding(
                .bottom,
                16
            )
    }
    
    private var scrollContent: some View {
        ScrollView {
            scrollItem
        }
    }
    
    @ViewBuilder
    private var scrollItem: some View {
        if isFetching {
            loading
        } else if isEmpty {
            noData
        } else {
            overviewUsagePerformance
        }
    }
}

// MARK: - Empty states:

private extension DataVisualizationTwoView {
    private var loading: some View {
        loadingContent
            .frame(
                maxWidth: .infinity,
                alignment: .center
            )
            .containerRelativeFrame(
                .vertical,
                alignment: .center
            )
    }
    
    private var loadingContent: some View {
        LoadingView(
            isShowing: true,
            color: .secondary,
            scale: 1.5
        )
    }
    
    private var noData: some View {
        noDataContent
            .frame(
                maxWidth: .infinity,
                alignment: .center
            )
            .containerRelativeFrame(
                .vertical,
                alignment: .center
            )
    }
    
    private var noDataContent: some View {
        EmptyStateView(
            title: "No Data",
            subtitle: "We don't have any data to display here."
        )
    }
}

// MARK: - Overview, usage, and performance:

private extension DataVisualizationTwoView {
    private var overviewUsagePerformance: some View {
        VStack(
            alignment: .leading,
            spacing: 32
        ) {
            overviewUsagePerformanceContent
        }
    }
    
    @ViewBuilder
    private var overviewUsagePerformanceContent: some View {
        DataVisualizationTwoOverviewView()
        DataVisualizationTwoUsageView(usageItems: usageItems)
        performance
    }
    
    private var performance: some View {
        DataVisualizationTwoPerformanceView(
            performanceItems: performanceItems,
            currentPerformanceItem: $currentPerformanceItem
        )
    }
}

// MARK: - Preview:

#Preview {
    DataVisualizationTwoView()
}
