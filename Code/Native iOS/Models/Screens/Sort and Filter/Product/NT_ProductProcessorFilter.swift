//
//  NT_ProductProcessorFilter.swift
//  Native
//

import Foundation

enum NT_ProductProcessorFilter: Int {
    
    // MARK: - Cases:
    
    case appleM1
    case appleM1Pro
    case appleM1Max
    case appleM1Ultra
    case appleM2
    case appleM2Pro
    case appleM2Max
    case appleM2Ultra
    case appleM3
    case appleM3Pro
    case appleM3Max
    
    // MARK: - Computed properties:
    
    /// Identifier of the filter:
    var id: Int {
        rawValue
    }
    
    /// Title of the filter:
    var title: String {
        switch self {
        case .appleM1: return "Apple M1"
        case .appleM1Pro: return "Apple M1 Pro"
        case .appleM1Max: return "Apple M1 Max"
        case .appleM1Ultra: return "Apple M1 Ultra"
        case .appleM2: return "Apple M2"
        case .appleM2Pro: return "Apple M2 Pro"
        case .appleM2Max: return "Apple M2 Max"
        case .appleM2Ultra: return "Apple M2 Ultra"
        case .appleM3: return "Apple M3"
        case .appleM3Pro: return "Apple M3 Pro"
        case .appleM3Max: return "Apple M3 Max"
        }
    }
}

// MARK: - Identifiable:

extension NT_ProductProcessorFilter: Identifiable {  }

// MARK: - CaseIterable:

extension NT_ProductProcessorFilter: CaseIterable {  }

// MARK: - Equatable:

extension NT_ProductProcessorFilter: Equatable {  }

// MARK: - Hashable:

extension NT_ProductProcessorFilter: Hashable {  }
