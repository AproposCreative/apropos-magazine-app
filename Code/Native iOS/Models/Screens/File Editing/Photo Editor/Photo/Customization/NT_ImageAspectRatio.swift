//
//  NT_ImageAspectRatio.swift
//  Native
//

import Foundation

enum NT_ImageAspectRatio: Int {
    
    // MARK: - Cases:
    
    case sixteenByNine
    case fourByThree
    case threeByThree
    
    // MARK: - Computed properties:
    
    /// Identifier of the aspect ratio:
    var id: Int {
        rawValue
    }
    
    /// Title of the aspect ratio:
    var title: String {
        switch self {
        case .sixteenByNine: return "16:9"
        case .fourByThree: return "4:3"
        case .threeByThree: return "3:3"
        }
    }
}

// MARK: - Identifiable:

extension NT_ImageAspectRatio: Identifiable {  }

// MARK: - CaseIterable:

extension NT_ImageAspectRatio: CaseIterable {  }

// MARK: - Equatable:

extension NT_ImageAspectRatio: Equatable {  }

// MARK: - Hashable:

extension NT_ImageAspectRatio: Hashable {  }
