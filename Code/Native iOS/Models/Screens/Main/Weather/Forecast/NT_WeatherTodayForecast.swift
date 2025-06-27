//
//  NT_WeatherTodayForecast.swift
//  Native
//

import Foundation

struct NT_WeatherTodayForecast {
    
    // MARK: - Properties:
    
    /// Identifier of the forecast for today:
    let id: String
    
    /// Temperature of the forecast for today:
    let temperature: Double
    
    /// An hour of the day that the forecast is for:
    let hour: Int
    
    /// Condition of the forecast for today:
    let condition: NT_WeatherCondition
    
    init(
        id: String,
        temperature: Double,
        hour: Int,
        condition: NT_WeatherCondition
    ) {
        
        /// Properties initialization:
        self.id = id
        self.temperature = temperature
        self.hour = hour
        self.condition = condition
    }
    
    // MARK: - Computed properties:
    
    /// Value of the temperature of the forecast for today:
    var temperatureValue: Measurement<UnitTemperature> {
        .init(
            value: temperature,
            unit: .celsius
        )
    }
}

// MARK: - Identifiable:

extension NT_WeatherTodayForecast: Identifiable {  }

// MARK: - Equatable:

extension NT_WeatherTodayForecast: Equatable {  }

// MARK: - Hashable:

extension NT_WeatherTodayForecast: Hashable {  }

// MARK: - Example:

extension NT_WeatherTodayForecast {
    
    // MARK: - Computed properties:
    
    /// An array of the example forecasts for today:
    static var example: [NT_WeatherTodayForecast] {
        [
            .init(
                id: "Item.1",
                temperature: 24,
                hour: 12,
                condition: .sunny
            ),
            .init(
                id: "Item.2",
                temperature: 26,
                hour: 13,
                condition: .sunny
            ),
            .init(
                id: "Item.3",
                temperature: 28,
                hour: 14,
                condition: .sunny
            ),
            .init(
                id: "Item.4",
                temperature: 26,
                hour: 15,
                condition: .windy
            ),
            .init(
                id: "Item.5",
                temperature: 22,
                hour: 16,
                condition: .windy
            ),
            .init(
                id: "Item.6",
                temperature: 20,
                hour: 17,
                condition: .partlySunny
            )
        ]
    }
}
