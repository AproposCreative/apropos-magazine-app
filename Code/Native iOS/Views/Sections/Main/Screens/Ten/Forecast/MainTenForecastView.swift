//
//  MainTenForecastView.swift
//  Native
//

import SwiftUI

struct MainTenForecastView: View {
    
    // MARK: - Properties:
    
    /// An array of the forecasts to display:
    let forecasts: [NT_WeatherForecast]
    
    init(forecasts: [NT_WeatherForecast]) {
        
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

private extension MainTenForecastView {
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
        SectionHeaderView(title: "Forecast")
        forecastsContent
    }
}

// MARK: - Forecasts:

private extension MainTenForecastView {
    private var forecastsContent: some View {
        LazyVStack(
            alignment: .leading,
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
    
    private func forecast(_ forecast: NT_WeatherForecast) -> some View {
        IconBackgroundTitleSubtitleValueView(
            icon: icon(forecast),
            iconColor: color(forecast),
            iconGradientStart: gradientStart(forecast),
            iconGradientEnd: gradientEnd(forecast),
            isIconColorGradient: true,
            isShowingIconBackground: false,
            iconSize: .twentyFourPixels,
            title: weekdayTitle(forecast),
            value: temperaturesRange(forecast),
            subtitle: description(forecast)
        )
    }
}

// MARK: - Preview:

#Preview {
    ScrollView {
        MainTenForecastView(forecasts: NT_WeatherForecast.example)
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
