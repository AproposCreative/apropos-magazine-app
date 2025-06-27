//
//  MainTenLocations+FunctionsExtension.swift
//  Native
//

import SwiftUI

extension MainTenLocationsView {
    
    // MARK: - Functions:
    
    /// Returns the title of the given location:
    func title(_ location: NT_WeatherLocation) -> String {
        location.title
    }
    
    /// Returns the temperature of the weather of the given location as a string:
    func temperature(_ location: NT_WeatherLocation) -> String {
        location.temperatureValue.formatted(.measurement(width: .narrow))
    }
    
    /// Returns the description of the weather of the given location:
    func description(_ location: NT_WeatherLocation) -> String {
        location.description
    }
    
    /// Returns the color of the condition of the weather of the given location:
    func color(_ location: NT_WeatherLocation) -> Color {
        condition(location).color
    }
    
    /// Returns the starting color of the gradient of the condition of the weather of the given location:
    func gradientStart(_ location: NT_WeatherLocation) -> Color {
        condition(location).gradientStart
    }
    
    /// Returns the ending color of the gradient of the condition of the weather of the given location:
    func gradientEnd(_ location: NT_WeatherLocation) -> Color {
        condition(location).gradientEnd
    }
    
    /// Returns the icon of the condition of the weather of the given location:
    func icon(_ location: NT_WeatherLocation) -> String {
        condition(location).icon
    }
    
    // MARK: - Private functions:
    
    /// Returns the condition of the weather of the given location:
    private func condition(_ location: NT_WeatherLocation) -> NT_WeatherCondition {
        location.condition
    }
}
