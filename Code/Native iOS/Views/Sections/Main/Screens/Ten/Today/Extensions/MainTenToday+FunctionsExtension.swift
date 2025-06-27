//
//  MainTenToday+FunctionsExtension.swift
//  Native
//

import SwiftUI

extension MainTenTodayView {
    
    // MARK: - Functions:
    
    /// Returns the temperature of the weather of the given forecast for today as a string:
    func temperature(_ forecast: NT_WeatherTodayForecast) -> String {
        forecast.temperatureValue.formatted(.measurement(width: .narrow))
    }
    
    /// Returns an hour of the given forecast for today as a string:
    func hour(_ forecast: NT_WeatherTodayForecast) -> String {
        Date.dateWithComponents(
            withYear: 2024,
            withMonth: 8,
            withDay: 1,
            withHour: forecast.hour
        ).formatted(.dateTime.hour())
    }
    
    /// Returns the color of the condition of the weather of the given forecast for today:
    func color(_ forecast: NT_WeatherTodayForecast) -> Color {
        condition(forecast).color
    }
    
    /// Returns the starting color of the gradient of the condition of the weather of the given forecast for today:
    func gradientStart(_ forecast: NT_WeatherTodayForecast) -> Color {
        condition(forecast).gradientStart
    }
    
    /// Returns the ending color of the gradient of the condition of the weather of the given forecast for today:
    func gradientEnd(_ forecast: NT_WeatherTodayForecast) -> Color {
        condition(forecast).gradientEnd
    }
    
    /// Returns the icon of the condition of the weather of the given forecast for today:
    func icon(_ forecast: NT_WeatherTodayForecast) -> String {
        condition(forecast).icon
    }
    
    // MARK: - Private functions:
    
    /// Returns the condition of the weather of the given forecast for today:
    private func condition(_ forecast: NT_WeatherTodayForecast) -> NT_WeatherCondition {
        forecast.condition
    }
}
