//
//  DataVisualizationOneContentView.swift
//  Native
//

import SwiftUI

struct DataVisualizationOneContentView: View {
    
    // MARK: - Properties:
    
    /// An array of the overview items to display:
    @State var overviewItems: [NT_Overview] = []
    
    /// An array of the data for the number of the active users to display:
    @State var activeUsersData: [NT_ActiveUsersData] = []
    
    /// An array of the data for the new downloads to display:
    @State var newDownloadsData: [NT_NewDownloadsData] = []
    
    /// An array of the data for the reviews to display:
    @State var reviewsData: [NT_ReviewsData] = []
    
    /// An array of the data for the total number of users to display:
    @State var totalUsersData: [NT_TotalUsersData] = []
    
    /// 'Bool' value indicating whether or not the data is currently being fetched:
    @State var isFetching: Bool = true
    
    // MARK: - View:
    
    var body: some View {
        content
    }
    
    private var content: some View {
        scroll
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
            .toolbarAvatar()
            .navigationDestination(
                for: NT_Overview.self,
                destination: overview
            )
            .animation(
                .default,
                value: overviewItems
            )
            .animation(
                .default,
                value: activeUsersData
            )
            .animation(
                .default,
                value: newDownloadsData
            )
            .animation(
                .default,
                value: reviewsData
            )
            .animation(
                .default,
                value: totalUsersData
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

private extension DataVisualizationOneContentView {
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
            overviewAnalytics
        }
    }
}

// MARK: - Empty states:

private extension DataVisualizationOneContentView {
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

// MARK: - Overview and analytics:

private extension DataVisualizationOneContentView {
    private var overviewAnalytics: some View {
        VStack(
            alignment: .leading,
            spacing: 32
        ) {
            overviewAnalyticsContent
        }
    }
    
    @ViewBuilder
    private var overviewAnalyticsContent: some View {
        DataVisualizationOneOverviewView(overviewItems: overviewItems)
        analytics
    }
    
    private var analytics: some View {
        DataVisualizationOneAnalyticsView(
            activeUsersData: activeUsersData,
            newDownloadsData: newDownloadsData,
            reviewsData: reviewsData,
            totalUsersData: totalUsersData
        )
    }
}

// MARK: - Overview:

private extension DataVisualizationOneContentView {
    private func overview(_ overview: NT_Overview) -> some View {
        PlaceholderView(title: title(overview))
    }
}

// MARK: - Preview:

#Preview {
    DataVisualizationOneContentView()
}
