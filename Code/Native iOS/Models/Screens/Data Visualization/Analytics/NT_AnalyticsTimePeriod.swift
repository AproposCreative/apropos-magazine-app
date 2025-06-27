//
//  NT_AnalyticsTimePeriod.swift
//  Native
//

import Foundation

enum NT_AnalyticsTimePeriod: Int {
    
    // MARK: - Cases:
    
    case today
    case thisWeek
    case thisMonth
    
    // MARK: - Computed properties:
    
    /// Identifier of the time period:
    var id: Int {
        rawValue
    }
    
    /// Title of the time period:
    var title: String {
        switch self {
        case .today: return .init(localized: "Today")
        case .thisWeek: return .init(localized: "This Week")
        case .thisMonth: return .init(localized: "This Month")
        }
    }
}

// MARK: - Identifiable:

extension NT_AnalyticsTimePeriod: Identifiable {  }

// MARK: - CaseIterable:

extension NT_AnalyticsTimePeriod: CaseIterable {  }

// MARK: - Equatable:

extension NT_AnalyticsTimePeriod: Equatable {  }

// MARK: - Hashable:

extension NT_AnalyticsTimePeriod: Hashable {  }
