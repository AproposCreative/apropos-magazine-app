//
//  NT_ProductRAMFilter.swift
//  Native
//

import Foundation

enum NT_ProductRAMFilter: Int {
    
    // MARK: - Cases:
    
    case eightGB
    case twelveGB
    case sixteenGB
    case twentyFourGB
    case thirtyTwoGB
    case thirtySixGB
    case fortyEightGB
    case sixtyFourGB
    case ninetySixGB
    case hundredTwentyEightGB
    case hundredNinetyTwoGB
    
    // MARK: - Computed properties:
    
    /// Identifier of the RAM option:
    var id: Int {
        rawValue
    }
    
    /// Title of the RAM option:
    var title: String {
        switch self {
        case .eightGB: return "8 GB"
        case .twelveGB: return "12 GB"
        case .sixteenGB: return "16 GB"
        case .twentyFourGB: return "24 GB"
        case .thirtyTwoGB: return "32 GB"
        case .thirtySixGB: return "36 GB"
        case .fortyEightGB: return "48 GB"
        case .sixtyFourGB: return "64 GB"
        case .ninetySixGB: return "96 GB"
        case .hundredTwentyEightGB: return "128 GB"
        case .hundredNinetyTwoGB: return "192 GB"
        }
    }
}

// MARK: - Identifiable:

extension NT_ProductRAMFilter: Identifiable {  }

// MARK: - CaseIterable:

extension NT_ProductRAMFilter: CaseIterable {  }

// MARK: - Equatable:

extension NT_ProductRAMFilter: Equatable {  }

// MARK: - Hashable:

extension NT_ProductRAMFilter: Hashable {  }
