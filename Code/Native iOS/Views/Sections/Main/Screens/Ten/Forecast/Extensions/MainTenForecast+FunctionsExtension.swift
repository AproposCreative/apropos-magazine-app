//
//  MainTenForecast+FunctionsExtension.swift
//  Native
//

import SwiftUI

extension MainTenForecastView {
    
    // MARK: - Functions:
    
    /// Returns the title of the day of the week that the given forecast is for:
    func weekdayTitle(_ forecast: NT_WeatherForecast) -> String {
        if forecast.date.isToday {
            return "Today"
        } else {
            return forecast.date.formatted(.dateTime.weekday(.wide))
        }
    }
    
    /// Returns the description of the weather of the given forecast:
    func description(_ forecast: NT_WeatherForecast) -> String {
        forecast.description
    }
    
    /// Returns the range of the temperatures of the weather of the given forecast as a string:
    func temperaturesRange(_ forecast: NT_WeatherForecast) -> String {
        "\(forecast.lowestTemperatureValue.formatted(.measurement(width: .narrow))) - \(forecast.highestTemperatureValue.formatted(.measurement(width: .narrow)))"
    }
    
    /// Returns the color of the condition of the weather of the given forecast:
    func color(_ forecast: NT_WeatherForecast) -> Color {
        condition(forecast).color
    }
    
    /// Returns the starting color of the gradient of the condition of the weather of the given forecast:
    func gradientStart(_ forecast: NT_WeatherForecast) -> Color {
        condition(forecast).gradientStart
    }
    
    /// Returns the ending color of the gradient of the condition of the weather of the given forecast:
    func gradientEnd(_ forecast: NT_WeatherForecast) -> Color {
        condition(forecast).gradientEnd
    }
    
    /// Returns the icon of the condition of the weather of the given forecast:
    func icon(_ forecast: NT_WeatherForecast) -> String {
        condition(forecast).icon
    }
    
    // MARK: - Private functions:
    
    /// Returns the condition of the weather of the given forecast:
    private func condition(_ forecast: NT_WeatherForecast) -> NT_WeatherCondition {
        forecast.condition
    }
}
