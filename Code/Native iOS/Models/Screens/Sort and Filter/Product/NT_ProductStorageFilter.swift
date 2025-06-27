//
//  NT_ProductStorageFilter.swift
//  Native
//

import Foundation

enum NT_ProductStorageFilter: Int {
    
    // MARK: - Cases:
    
    case twoHundredFiftySixGB
    case fiveHundredTwelveGB
    case oneTB
    case twoTB
    case fourTB
    case eightTB
    
    // MARK: - Computed properties:
    
    /// Identifier of the storage option:
    var id: Int {
        rawValue
    }
    
    /// Title of the storage option:
    var title: String {
        switch self {
        case .twoHundredFiftySixGB: return "256 GB"
        case .fiveHundredTwelveGB: return "512 GB"
        case .oneTB: return "1 TB"
        case .twoTB: return "2 TB"
        case .fourTB: return "4 TB"
        case .eightTB: return "8 TB"
        }
    }
}

// MARK: - Identifiable:

extension NT_ProductStorageFilter: Identifiable {  }

// MARK: - CaseIterable:

extension NT_ProductStorageFilter: CaseIterable {  }

// MARK: - Equatable:

extension NT_ProductStorageFilter: Equatable {  }

// MARK: - Hashable:

extension NT_ProductStorageFilter: Hashable {  }
