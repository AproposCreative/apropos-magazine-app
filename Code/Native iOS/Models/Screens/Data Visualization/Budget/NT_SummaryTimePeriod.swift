//
//  NT_SummaryTimePeriod.swift
//  Native
//

import Foundation

enum NT_SummaryTimePeriod: Int {
    
    // MARK: - Cases:
    
    case day
    case week
    case month
    case year
    
    // MARK: - Computed properties:
    
    /// Identifier of the time period:
    var id: Int {
        rawValue
    }
    
    /// Title of the time period:
    var title: String {
        switch self {
        case .day: return String(localized: "Day")
        case .week: return String(localized: "Week")
        case .month: return String(localized: "Month")
        case .year: return String(localized: "Year")
        }
    }
    
    /// Shortened title of the time period:
    var shortTitle: String {
        switch self {
        case .day: return String(localized: "D")
        case .week: return String(localized: "W")
        case .month: return String(localized: "M")
        case .year: return String(localized: "Y")
        }
    }
}

// MARK: - Identifiable:

extension NT_SummaryTimePeriod: Identifiable {  }

// MARK: - CaseIterable:

extension NT_SummaryTimePeriod: CaseIterable {  }

// MARK: - Equatable:

extension NT_SummaryTimePeriod: Equatable {  }

// MARK: - Hashable:

extension NT_SummaryTimePeriod: Hashable {  }
