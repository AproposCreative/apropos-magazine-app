//
//  MainTenLocationsView.swift
//  Native
//

import SwiftUI

struct MainTenLocationsView: View {
    
    // MARK: - Properties:
    
    /// An array of the locations to display:
    let locations: [NT_WeatherLocation]
    
    // MARK: - Private properties:
    
    /// Location that is currently shown:
    @Binding private var currentLocation: NT_WeatherLocation?
    
    init(
        locations: [NT_WeatherLocation],
        currentLocation: Binding<NT_WeatherLocation?>
    ) {
        
        /// Properties initialization:
        self.locations = locations
        _currentLocation = currentLocation
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
            .contentBackground()
    }
}

// MARK: - Item:

private extension MainTenLocationsView {
    private var item: some View {
        VStack(
            alignment: .center,
            spacing: 24
        ) {
            itemContent
        }
    }
    
    @ViewBuilder
    private var itemContent: some View {
        scroll
        pagination
    }
}

// MARK: - Scroll:

private extension MainTenLocationsView {
    private var scroll: some View {
        scrollContent
            .scrollIndicators(.hidden)
            .scrollTargetBehavior(.viewAligned)
            .scrollPosition(id: $currentLocation)
    }
    
    private var scrollContent: some View {
        ScrollView(.horizontal) {
            scrollItem
        }
    }
    
    private var scrollItem: some View {
        locationsContent
            .scrollTargetLayout()
    }
}

// MARK: - Locations:

private extension MainTenLocationsView {
    private var locationsContent: some View {
        LazyHStack(
            alignment: .top,
            spacing: 32
        ) {
            locationsItem
        }
    }
    
    private var locationsItem: some View {
        ForEach(
            locations,
            content: location
        )
    }
    
    private func location(_ location: NT_WeatherLocation) -> some View {
        locationContent(location)
            .containerRelativeFrame(.horizontal)
            .id(location)
    }
    
    private func locationContent(_ location: NT_WeatherLocation) -> some View {
        IconBackgroundTitleValueBadgeSubtitleView(
            icon: icon(location),
            iconColor: color(location),
            iconGradientStart: gradientStart(location),
            iconGradientEnd: gradientEnd(location),
            isIconColorGradient: true,
            isShowingIconBackground: false,
            title: temperature(location),
            badgeIcon: Icons.location,
            badgeTitle: title(location),
            subtitle: description(location),
            verticalPadding: 0,
            horizontalPadding: 0,
            isShowingBackground: false,
            cornerRadius: 0
        )
    }
}

// MARK: - Pagination:

private extension MainTenLocationsView {
    private var pagination: some View {
        PaginationView(
            current: $currentLocation,
            all: locations
        )
    }
}

// MARK: - Preview:

#Preview {
    @Previewable @State var currentLocation: NT_WeatherLocation? = .example.first
    
    ScrollView {
        MainTenLocationsView(
            locations: NT_WeatherLocation.example,
            currentLocation: $currentLocation
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
    .localizedNavigationTitle(title: "Weather")
    .navigationStack()
}
