//
//  DataVisualizationFourActivityView.swift
//  Native
//

import SwiftUI

struct DataVisualizationFourActivityView: View {
    
    // MARK: - Properties:
    
    /// Size of the dynamic type that is currently selected:
    @Environment(\.dynamicTypeSize) var dynamicTypeSize
    
    /// An array of the activities to display:
    let activities: [NT_Activity]
    
    init(activities: [NT_Activity]) {
        
        /// Properties initialization:
        self.activities = activities
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

private extension DataVisualizationFourActivityView {
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
        SectionHeaderView(title: "Activity")
        activitiesContent
    }
}

// MARK: - Categories:

private extension DataVisualizationFourActivityView {
    private var activitiesContent: some View {
        LazyVGrid(
            columns: columns,
            alignment: .leading,
            spacing: spacing
        ) {
            activitiesItem
        }
    }
    
    private var activitiesItem: some View {
        ForEach(
            activities,
            content: activity
        )
    }
    
    private func activity(_ activity: NT_Activity) -> some View {
        IconBackgroundTitleSubtitleValueView(
            icon: icon(activity),
            iconBackgroundColor: color(activity),
            iconBackgroundGradientStart: gradientStart(activity),
            iconBackgroundGradientEnd: gradientEnd(activity),
            iconSize: .thirtyTwoPixels,
            title: title(activity),
            value: value(activity),
            valueFont: .title2.bold(),
            valueColor: color(activity),
            titleValueAlignment: .center,
            subtitle: description(activity),
            alignment: .vertical,
            maxHeight: .infinity,
            backgroundColor: .init(.secondarySystemBackground)
        )
    }
}

// MARK: - Preview:

#Preview {
    ScrollView {
        DataVisualizationFourActivityView(activities: NT_Activity.example)
    }
    .safeAreaPadding(
        .all,
        16
    )
    .safeAreaPadding(
        .bottom,
        16
    )
    .localizedNavigationTitle(title: "Analytics")
    .navigationStack()
}
