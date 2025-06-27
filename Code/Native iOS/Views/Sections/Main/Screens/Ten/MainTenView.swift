//
//  MainTenView.swift
//  Native
//

import SwiftUI

struct MainTenView: View {
    
    // MARK: - Properties:
    
    /// An array of the locations to display:
    @State var locations: [NT_WeatherLocation] = []
    
    /// An array of the forecasts for today to display:
    @State var todayForecasts: [NT_WeatherTodayForecast] = []
    
    /// An array of the forecasts to display:
    @State var forecasts: [NT_WeatherForecast] = []
    
    /// Location that is currently shown:
    @State var currentLocation: NT_WeatherLocation? = nil
    
    /// 'Bool' value indicating whether or not the data is currently being fetched:
    @State var isFetching: Bool = true
    
    // MARK: - View:
    
    var body: some View {
        content
    }
    
    private var content: some View {
        scroll
            .background(Color(.systemGroupedBackground))
            .localizedNavigationTitle(title: "Weather")
            .animation(
                .default,
                value: locations
            )
            .animation(
                .default,
                value: todayForecasts
            )
            .animation(
                .default,
                value: forecasts
            )
            .animation(
                .default,
                value: currentLocation
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

private extension MainTenView {
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
            nothingHere
        } else {
            locationsTodayForecastNotice
        }
    }
}

// MARK: - Empty states:

private extension MainTenView {
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
    
    private var nothingHere: some View {
        nothingHereContent
            .frame(
                maxWidth: .infinity,
                alignment: .center
            )
            .containerRelativeFrame(
                .vertical,
                alignment: .center
            )
    }
    
    private var nothingHereContent: some View {
        EmptyStateView(
            title: "Nothing Here",
            subtitle: "We don't have anything to display here."
        )
    }
}

// MARK: - Locations, today, forecast, and notice:

private extension MainTenView {
    private var locationsTodayForecastNotice: some View {
        VStack(
            alignment: .leading,
            spacing: 32
        ) {
            locationsTodayForecastNoticeContent
        }
    }
    
    @ViewBuilder
    private var locationsTodayForecastNoticeContent: some View {
        locationsContent
        MainTenTodayView(forecasts: todayForecasts)
        MainTenForecastView(forecasts: forecasts)
        notice
    }
    
    private var locationsContent: some View {
        MainTenLocationsView(
            locations: locations,
            currentLocation: $currentLocation
        )
    }
    
    @ViewBuilder
    private var notice: some View {
        if !isFetching {
            noticeContent
        }
    }
    
    private var noticeContent: some View {
        noticeItem
            .font(.footnote)
            .multilineTextAlignment(.center)
            .foregroundStyle(.secondary)
            .frame(
                maxWidth: .infinity,
                alignment: .center
            )
    }
    
    private var noticeItem: some View {
        Text(
                                    """
                                    Last updated \(lastUpdated.formatted(.relative(presentation: .named))).
                                    Learn more about the weather data \(Text("[here](https://www.applayouts.com/terms-of-use)").underline().foregroundStyle(.accent)).
                                    """
        )
    }
}

// MARK: - Preview:

#Preview {
    MainTenView()
}
