//
//  NT_SocialProof.swift
//  Native
//

import Foundation

enum NT_SocialProof: Int {
    
    // MARK: - Cases:
    
    /// You can add more social proofs by adding more cases below:
    case first
    case second
    case third
    case fourth
    case fifth
    case sixth
    
    // MARK: - Computed properties:
    
    /// Identifier of the social proof:
    var id: Int {
        rawValue
    }
    
    /// Title of the social proof:
    var title: String {
        switch self {
        case .first: return "App of the Day"
        case .second: return "Top Free Apps"
        case .third: return "Best Apps for iOS"
        case .fourth: return "Popular Apps"
        case .fifth: return "Editors’ Choice"
        case .sixth: return "App of the Year"
        }
    }
}

// MARK: - Identifiable:

extension NT_SocialProof: Identifiable {  }

// MARK: - CaseIterable:

extension NT_SocialProof: CaseIterable {  }

// MARK: - Equatable:

extension NT_SocialProof: Equatable {  }

// MARK: - Hashable:

extension NT_SocialProof: Hashable {  }
