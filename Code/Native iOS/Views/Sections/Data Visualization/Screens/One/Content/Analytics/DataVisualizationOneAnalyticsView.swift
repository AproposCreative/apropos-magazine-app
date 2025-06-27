//
//  DataVisualizationOneAnalyticsView.swift
//  Native
//

import SwiftUI

struct DataVisualizationOneAnalyticsView: View {
    
    // MARK: - Properties:
    
    /// Size of the dynamic type that is currently selected:
    @Environment(\.dynamicTypeSize) var dynamicTypeSize
    
    /// An array of the data for the number of the active users to display:
    let activeUsersData: [NT_ActiveUsersData]
    
    /// An array of the data for the new downloads to display:
    let newDownloadsData: [NT_NewDownloadsData]
    
    /// An array of the data for the reviews to display:
    let reviewsData: [NT_ReviewsData]
    
    /// An array of the data for the total number of users to display:
    let totalUsersData: [NT_TotalUsersData]
    
    // MARK: - Private properties:
    
    /// Time period to filter the data by that is currently selected:
    @State private var timePeriod: NT_AnalyticsTimePeriod = .today
    
    init(
        activeUsersData: [NT_ActiveUsersData],
        newDownloadsData: [NT_NewDownloadsData],
        reviewsData: [NT_ReviewsData],
        totalUsersData: [NT_TotalUsersData]
    ) {
        
        /// Properties initialization:
        self.activeUsersData = activeUsersData
        self.newDownloadsData = newDownloadsData
        self.reviewsData = reviewsData
        self.totalUsersData = totalUsersData
    }
    
    // MARK: - View:
    
    var body: some View {
        content
    }
    
    private var content: some View {
        item
            .onChange(
                of: timePeriod,
                timePeriodOnChange
            )
    }
}

// MARK: - Item:

private extension DataVisualizationOneAnalyticsView {
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
        header
        analytics
    }
}

// MARK: - Header:

private extension DataVisualizationOneAnalyticsView {
    private var header: some View {
        VStack(
            alignment: .leading,
            spacing: 12
        ) {
            headerContent
        }
    }
    
    @ViewBuilder
    private var headerContent: some View {
        SectionHeaderView(title: "Analytics")
        timePeriodPicker
    }
}

// MARK: - Time period picker:

private extension DataVisualizationOneAnalyticsView {
    private var timePeriodPicker: some View {
        timePeriodPickerContent
            .pickerStyle(.segmented)
            .labelsHidden()
    }
    
    private var timePeriodPickerContent: some View {
        Picker(
            "Time Period",
            selection: $timePeriod
        ) {
            timePeriodsContent
        }
    }
    
    private var timePeriodsContent: some View {
        ForEach(
            timePeriods,
            content: timePeriod
        )
    }
    
    private func timePeriod(_ timePeriod: NT_AnalyticsTimePeriod) -> some View {
        Text(title(timePeriod))
            .tag(timePeriod)
    }
}

// MARK: - Analytics:

private extension DataVisualizationOneAnalyticsView {
    private var analytics: some View {
        VStack(
            alignment: .leading,
            spacing: spacing
        ) {
            analyticsContent
        }
    }
    
    @ViewBuilder
    private var analyticsContent: some View {
        activeUsersChart
        newDownloadsReviewsCharts
        totalUsersChart
    }
}

// MARK: - Charts:

private extension DataVisualizationOneAnalyticsView {
    private var activeUsersChart: some View {
        BarChartView(
            title: "Active Users",
            titleColor: analyticsTitleColor,
            valueType: analyticsValueType,
            bars: activeUsersBars,
            chartHeight: fullChartHeight,
            backgroundColor: analyticsBackgroundColor
        ) {
            
        }
    }
    
    @ViewBuilder
    private var newDownloadsReviewsCharts: some View {
        if shouldMoveContent {
            verticalNewDownloadsReviewsChartsContent
        } else {
            horizontalNewDownloadsReviewsChartsContent
        }
    }
    
    private var horizontalNewDownloadsReviewsChartsContent: some View {
        HStack(
            alignment: .top,
            spacing: spacing
        ) {
            newDownloadsReviewsChartsItem
        }
    }
    
    private var verticalNewDownloadsReviewsChartsContent: some View {
        VStack(
            alignment: .leading,
            spacing: spacing
        ) {
            newDownloadsReviewsChartsItem
        }
    }
    
    @ViewBuilder
    private var newDownloadsReviewsChartsItem: some View {
        newDownloadsChart
        reviewsChart
    }
    
    private var newDownloadsChart: some View {
        BarChartView(
            title: "New Downloads",
            titleColor: analyticsTitleColor,
            valueType: analyticsValueType,
            bars: newDownloadsBars,
            chartHeight: halfChartHeight,
            backgroundColor: analyticsBackgroundColor
        ) {
            
        }
    }
    
    private var reviewsChart: some View {
        BarChartView(
            title: "Reviews",
            titleColor: analyticsTitleColor,
            valueType: analyticsValueType,
            bars: reviewsBars,
            chartHeight: halfChartHeight,
            backgroundColor: analyticsBackgroundColor
        ) {
            
        }
    }
    
    private var totalUsersChart: some View {
        BarChartView(
            title: "Total Users",
            titleColor: analyticsTitleColor,
            valueType: analyticsValueType,
            bars: totalUsersBars,
            chartHeight: fullChartHeight,
            backgroundColor: analyticsBackgroundColor
        ) {
            
        }
    }
}

// MARK: - Preview:

#Preview {
    ScrollView {
        DataVisualizationOneAnalyticsView(
            activeUsersData: NT_ActiveUsersData.example,
            newDownloadsData: NT_NewDownloadsData.example,
            reviewsData: NT_ReviewsData.example,
            totalUsersData: NT_TotalUsersData.example
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
    .localizedNavigationTitle(title: "Overview")
    .navigationStack()
}
