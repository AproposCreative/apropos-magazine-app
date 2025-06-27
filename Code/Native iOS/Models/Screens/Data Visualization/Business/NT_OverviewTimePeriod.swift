//
//  NT_OverviewTimePeriod.swift
//  Native
//

import Foundation

enum NT_OverviewTimePeriod: Int {
    
    // MARK: - Cases:
    
    case today
    case last7Days
    case last30Days
    
    // MARK: - Computed properties:
    
    /// Identifier of the time period:
    var id: Int {
        rawValue
    }
    
    /// Title of the time period:
    var title: String {
        switch self {
        case .today: return String(localized: "Today")
        case .last7Days: return String(localized: "Last 7 Days")
        case .last30Days: return String(localized: "Last 30 Days")
        }
    }
}

// MARK: - Identifiable:

extension NT_OverviewTimePeriod: Identifiable {  }

// MARK: - CaseIterable:

extension NT_OverviewTimePeriod: CaseIterable {  }

// MARK: - Equatable:

extension NT_OverviewTimePeriod: Equatable {  }

// MARK: - Hashable:

extension NT_OverviewTimePeriod: Hashable {  }
