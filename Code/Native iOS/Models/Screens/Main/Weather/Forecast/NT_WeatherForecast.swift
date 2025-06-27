//
//  NT_WeatherForecast.swift
//  Native
//

import Foundation

struct NT_WeatherForecast {
    
    // MARK: - Properties:
    
    /// Identifier of the forecast:
    let id: String
    
    /// Description of the forecast:
    let description: String
    
    /// Lowest temperature of the forecast:
    let lowestTemperature: Double
    
    /// Highest temperature of the forecast:
    let highestTemperature: Double
    
    /// Date of the forecast:
    let date: Date
    
    /// Condition of the forecast:
    let condition: NT_WeatherCondition
    
    init(
        id: String,
        description: String,
        lowestTemperature: Double,
        highestTemperature: Double,
        date: Date,
        condition: NT_WeatherCondition
    ) {
        
        /// Properties initialization:
        self.id = id
        self.description = description
        self.lowestTemperature = lowestTemperature
        self.highestTemperature = highestTemperature
        self.date = date
        self.condition = condition
    }
    
    // MARK: - Computed properties:
    
    /// Value of the lowest temperature of the forecast:
    var lowestTemperatureValue: Measurement<UnitTemperature> {
        .init(
            value: lowestTemperature,
            unit: .celsius
        )
    }
    
    /// Value of the highest temperature of the forecast:
    var highestTemperatureValue: Measurement<UnitTemperature> {
        .init(
            value: highestTemperature,
            unit: .celsius
        )
    }
}

// MARK: - Identifiable:

extension NT_WeatherForecast: Identifiable {  }

// MARK: - Equatable:

extension NT_WeatherForecast: Equatable {  }

// MARK: - Hashable:

extension NT_WeatherForecast: Hashable {  }

// MARK: - Example:

extension NT_WeatherForecast {
    
    // MARK: - Computed properties:
    
    /// An array of the example forecasts:
    static var example: [NT_WeatherForecast] {
        [
            .init(
                id: "Item.1",
                description: "Mostly sunny",
                lowestTemperature: 20.0,
                highestTemperature: 32.0,
                date: .dateWithComponents(
                    withYear: 2024,
                    withMonth: 8,
                    withDay: 1
                ),
                condition: .sunny
            ),
            .init(
                id: "Item.2",
                description: "50% chance of rain",
                lowestTemperature: 16.0,
                highestTemperature: 30.0,
                date: .dateWithComponents(
                    withYear: 2024,
                    withMonth: 8,
                    withDay: 2
                ),
                condition: .rainy
            ),
            .init(
                id: "Item.3",
                description: "Sunny",
                lowestTemperature: 22.0,
                highestTemperature: 32.0,
                date: .dateWithComponents(
                    withYear: 2024,
                    withMonth: 8,
                    withDay: 3
                ),
                condition: .sunny
            ),
            .init(
                id: "Item.4",
                description: "Windy conditions",
                lowestTemperature: 14.0,
                highestTemperature: 24.0,
                date: .dateWithComponents(
                    withYear: 2024,
                    withMonth: 8,
                    withDay: 4
                ),
                condition: .windy
            ),
            .init(
                id: "Item.5",
                description: "Mostly sunny",
                lowestTemperature: 18.0,
                highestTemperature: 26.0,
                date: .dateWithComponents(
                    withYear: 2024,
                    withMonth: 8,
                    withDay: 5
                ),
                condition: .sunny
            ),
            .init(
                id: "Item.6",
                description: "Partly sunny",
                lowestTemperature: 16.0,
                highestTemperature: 24.0,
                date: .dateWithComponents(
                    withYear: 2024,
                    withMonth: 8,
                    withDay: 6
                ),
                condition: .partlySunny
            )
        ]
    }
}
