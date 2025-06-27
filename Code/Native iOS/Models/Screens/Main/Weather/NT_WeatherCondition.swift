//
//  NT_WeatherCondition.swift
//  Native
//

import SwiftUI

enum NT_WeatherCondition: Int {
    
    // MARK: - Cases:
    
    case sunny
    case rainy
    case windy
    case partlySunny
    
    // MARK: - Computed properties:
    
    /// Identifier of the condition:
    var id: Int {
        rawValue
    }
    
    /// Icon of the condition:
    var icon: String {
        switch self {
        case .sunny: return Icons.sunMax
        case .rainy: return Icons.cloudRain
        case .windy: return Icons.wind
        case .partlySunny: return Icons.cloudSun
        }
    }
    
    /// Color of the condition:
    var color: Color {
        switch self {
        case .sunny: return .orange
        case .rainy: return .blue
        case .windy: return .blue
        case .partlySunny: return .blue
        }
    }
    
    /// Starting color of the gradient of the condition:
    var gradientStart: Color {
        switch self {
        case .sunny: return .orangeGradientStart
        case .rainy: return .blueGradientStart
        case .windy: return .blueGradientStart
        case .partlySunny: return .blueGradientStart
        }
    }
    
    /// Ending color of the gradient of the condition:
    var gradientEnd: Color {
        switch self {
        case .sunny: return .orangeGradientEnd
        case .rainy: return .blueGradientEnd
        case .windy: return .blueGradientEnd
        case .partlySunny: return .blueGradientEnd
        }
    }
}

// MARK: - Identifiable:

extension NT_WeatherCondition: Identifiable {  }

// MARK: - CaseIterable:

extension NT_WeatherCondition: CaseIterable {  }

// MARK: - Equatable:

extension NT_WeatherCondition: Equatable {  }

// MARK: - Hashable:

extension NT_WeatherCondition: Hashable {  }
