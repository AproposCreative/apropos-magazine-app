//
//  NT_UsageType.swift
//  Native
//

import Foundation

enum NT_UsageType {
    
    // MARK: - Cases:
    
    case storage (
        total: Int64,
        used: Int64
    )
    case value (
        total: Double,
        used: Double
    )
}
