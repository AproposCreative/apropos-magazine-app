//
//  MainTenTodayView.swift
//  Native
//

import SwiftUI

struct MainTenTodayView: View {
    
    // MARK: - Properties:
    
    /// Size of the dynamic type that is currently selected:
    @Environment(\.dynamicTypeSize) var dynamicTypeSize
    
    /// An array of the forecasts for today to display:
    let forecasts: [NT_WeatherTodayForecast]
    
    init(forecasts: [NT_WeatherTodayForecast]) {
        
        /// Properties initialization:
        self.forecasts = forecasts
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

private extension MainTenTodayView {
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
        SectionHeaderView(title: "Today")
        scroll
    }
}

// MARK: - Scroll:

private extension MainTenTodayView {
    private var scroll: some View {
        scrollContent
            .scrollIndicators(.hidden)
            .scrollTargetBehavior(.viewAligned)
    }
    
    private var scrollContent: some View {
        ScrollView(.horizontal) {
            scrollItem
        }
    }
    
    private var scrollItem: some View {
        forecastsContent
            .scrollTargetLayout()
    }
}

// MARK: - Forecasts:

private extension MainTenTodayView {
    private var forecastsContent: some View {
        LazyHStack(
            alignment: .top,
            spacing: spacing
        ) {
            forecastsItem
        }
    }
    
    private var forecastsItem: some View {
        ForEach(
            forecasts,
            content: forecast
        )
    }
    
    private func forecast(_ forecast: NT_WeatherTodayForecast) -> some View {
        forecastContent(forecast)
            .frame(
                width: forecastWidth,
                alignment: .center
            )
    }
    
    private func forecastContent(_ forecast: NT_WeatherTodayForecast) -> some View {
        IconBackgroundTitleSubtitleView(
            icon: icon(forecast),
            iconColor: color(forecast),
            iconGradientStart: gradientStart(forecast),
            iconGradientEnd: gradientEnd(forecast),
            isIconColorGradient: true,
            isShowingIconBackground: false,
            iconSize: .thirtyTwoPixels,
            title: temperature(forecast),
            titleAlignment: .center,
            subtitle: hour(forecast),
            subtitleAlignment: .center,
            titleSubtitleAlignment: .center,
            titleSubtitleMaxWidthAlignment: .center,
            alignment: .vertical,
            horizontalAlignment: .center,
            spacing: 8,
            verticalPadding: forecastPadding,
            horizontalPadding: forecastPadding
        )
    }
}

// MARK: - Preview:

#Preview {
    ScrollView {
        MainTenTodayView(forecasts: NT_WeatherTodayForecast.example)
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
