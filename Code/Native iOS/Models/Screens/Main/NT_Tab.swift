//
//  NT_Tab.swift
//  Native
//

import Foundation

enum NT_Tab: Int {
    
    // MARK: - Cases:
    
    case first
    case second
    case third
    case fourth
    case fifth
    
    // MARK: - Computed properties:
    
    /// Identifier of the tab:
    var id: Int {
        rawValue
    }
}

// MARK: - Identifiable:

extension NT_Tab: Identifiable {  }

// MARK: - CaseIterable:

extension NT_Tab: CaseIterable {  }

// MARK: - Equatable:

extension NT_Tab: Equatable {  }

// MARK: - Hashable:

extension NT_Tab: Hashable {  }
