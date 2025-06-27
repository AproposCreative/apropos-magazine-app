//
//  DataVisualizationFourContentView.swift
//  Native
//

import SwiftUI

struct DataVisualizationFourContentView: View {
    
    // MARK: - Properties:
    
    /// An array of the data for the number of the new followers to display:
    @State var newFollowersData: [NT_NewFollowersData] = []
    
    /// An array of the activities to display:
    @State var activities: [NT_Activity] = []
    
    /// An array of the interests to display:
    @State var interests: [NT_Interest] = []
    
    /// 'Bool' value indicating whether or not the data is currently being fetched:
    @State var isFetching: Bool = true
    
    // MARK: - View:
    
    var body: some View {
        content
    }
    
    private var content: some View {
        scroll
            .localizedNavigationTitle(title: "Analytics")
            .toolbarButton(
                title: "Settings",
                icon: Icons.gearshape,
                iconSymbolVariant: .none,
                font: toolbarFont,
                style: toolbarStyle,
                placement: .cancellationAction,
                action: showSettings
            )
            .toolbarButton(
                title: "New Item",
                icon: Icons.plusCircle,
                iconSymbolVariant: .fill,
                font: toolbarFont,
                style: toolbarStyle,
                action: newItem
            )
            .animation(
                .default,
                value: newFollowersData
            )
            .animation(
                .default,
                value: activities
            )
            .animation(
                .default,
                value: interests
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

private extension DataVisualizationFourContentView {
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
            newFollowersActivityInterests
        }
    }
}

// MARK: - Empty states:

private extension DataVisualizationFourContentView {
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

// MARK: - New followers, activity, and interests:

private extension DataVisualizationFourContentView {
    private var newFollowersActivityInterests: some View {
        VStack(
            alignment: .leading,
            spacing: 32
        ) {
            newFollowersActivityInterestsContent
        }
    }
    
    @ViewBuilder
    private var newFollowersActivityInterestsContent: some View {
        DataVisualizationFourNewFollowersView(newFollowersData: newFollowersData)
        DataVisualizationFourActivityView(activities: activities)
        DataVisualizationFourInterestsView(interests: interests)
    }
}

// MARK: - Preview:

#Preview {
    DataVisualizationFourContentView()
}
