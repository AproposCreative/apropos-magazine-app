//
//  DataVisualizationOneAnalytics+ComputedPropertiesExtension.swift
//  Native
//

import SwiftUI

extension DataVisualizationOneAnalyticsView {
    
    // MARK: - Computed properties:
    
    /// 'Bool' value indicating whether or not the content of the view should be moved that is based on the size of the dynamic type that is currently selected:
    var shouldMoveContent: Bool {
        dynamicTypeSize >= .accessibility1
    }
    
    /// An array of the time periods to select from:
    var timePeriods: [NT_AnalyticsTimePeriod] {
        NT_AnalyticsTimePeriod.allCases
    }
    
    /// An array of the bars to display in the chart for the number of the active users:
    var activeUsersBars: [NT_ChartBar] {
        activeUsersData.map {
            .init(
                id: $0.id,
                title: $0.date.formatted(.dateTime.hour()),
                valueTitle: $0.value.formatted(.number),
                value: .init($0.value),
                color: .blue,
                gradientStart: .blueGradientStart,
                gradientEnd: .blueGradientEnd
            )
        }
    }
    
    /// An array of the bars to display in the chart for the new downloads:
    var newDownloadsBars: [NT_ChartBar] {
        newDownloadsData.map {
            .init(
                id: $0.id,
                title: $0.date.formatted(.dateTime.hour()),
                valueTitle: $0.value.formatted(.number),
                value: .init($0.value),
                color: .orange,
                gradientStart: .orangeGradientStart,
                gradientEnd: .orangeGradientEnd
            )
        }
    }
    
    /// An array of the bars to display in the chart for the reviews:
    var reviewsBars: [NT_ChartBar] {
        reviewsData.map {
            .init(
                id: $0.id,
                title: $0.date.formatted(.dateTime.hour()),
                valueTitle: $0.value.formatted(.number),
                value: .init($0.value),
                color: .purple,
                gradientStart: .purpleGradientStart,
                gradientEnd: .purpleGradientEnd
            )
        }
    }
    
    /// An array of the bars to display in the chart for the total number of the users:
    var totalUsersBars: [NT_ChartBar] {
        totalUsersData.map {
            .init(
                id: $0.id,
                title: $0.date.formatted(.dateTime.hour()),
                valueTitle: $0.value.formatted(.number),
                value: .init($0.value),
                color: .pink,
                gradientStart: .pinkGradientStart,
                gradientEnd: .pinkGradientEnd
            )
        }
    }
    
    /// Color of the title of the analytics:
    var analyticsTitleColor: Color {
        .secondary
    }
    
    /// Color of the background of the content of the analytics:
    var analyticsBackgroundColor: Color {
        .init(.secondarySystemBackground)
    }
    
    /// Spacing between the content of the view:
    var spacing: Double {
        16
    }
    
    /// Height of the chart that takes the full available width of the screen:
    var fullChartHeight: Double {
        200
    }
    
    /// Height of the chart that takes half of the available width of the screen:
    var halfChartHeight: Double {
        120
    }
    
    /// Type of the value of the analytics:
    var analyticsValueType: NT_ChartValueType {
        .number
    }
}
