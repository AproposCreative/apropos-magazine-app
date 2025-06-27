//
//  NT_WeatherLocation.swift
//  Native
//

import Foundation

struct NT_WeatherLocation {
    
    // MARK: - Properties:
    
    /// Identifier of the location:
    let id: String
    
    /// Title of the location:
    let title: String
    
    /// Description of the weather of the location:
    let description: String
    
    /// Temperature of the weather of the location:
    let temperature: Double
    
    /// Condition of the weather of the location:
    let condition: NT_WeatherCondition
    
    init(
        id: String,
        title: String,
        description: String,
        temperature: Double,
        condition: NT_WeatherCondition
    ) {
        
        /// Properties initialization:
        self.id = id
        self.title = title
        self.temperature = temperature
        self.description = description
        self.condition = condition
    }
    
    // MARK: - Computed properties:
    
    /// Value of the temperature of the weather of the location:
    var temperatureValue: Measurement<UnitTemperature> {
        .init(
            value: temperature,
            unit: .celsius
        )
    }
}

// MARK: - Identifiable:

extension NT_WeatherLocation: Identifiable {  }

// MARK: - Equatable:

extension NT_WeatherLocation: Equatable {  }

// MARK: - Hashable:

extension NT_WeatherLocation: Hashable {  }

// MARK: - Example:

extension NT_WeatherLocation {
    
    // MARK: - Computed properties:
    
    /// An array of the example locations:
    static var example: [NT_WeatherLocation] {
        [
            .init(
                id: "Item.1",
                title: "New York, NY",
                description: "Mostly sunny with windy conditions expected at around 4 PM.",
                temperature: 24.0,
                condition: .sunny
            ),
            .init(
                id: "Item.2",
                title: "Chicago, IL",
                description: "Partly cloudy with a chance of rain at around 6 PM.",
                temperature: 20.0,
                condition: .sunny
            ),
            .init(
                id: "Item.3",
                title: "Los Angeles, CA",
                description: "Sunny for the entire day with windy conditions expected at around 4 PM.",
                temperature: 32.0,
                condition: .sunny
            )
        ]
    }
}
