//
//  NT_ProfileAccountContentType.swift
//  Native
//

import Foundation

enum NT_ProfileAccountPostType: Int {
    
    // MARK: - Cases:
    
    case posts
    case likes
    case comments
    
    // MARK: - Computed properties:
    
    /// Identifier of the type:
    var id: Int {
        rawValue
    }
    
    /// Title of the type:
    var title: String {
        switch self {
        case .posts: return .init(localized: "Posts")
        case .likes: return .init(localized: "Likes")
        case .comments: return .init(localized: "Comments")
        }
    }
}

// MARK: - Identifiable:

extension NT_ProfileAccountPostType: Identifiable {  }

// MARK: - CaseIterable:

extension NT_ProfileAccountPostType: CaseIterable {  }

// MARK: - Equatable:

extension NT_ProfileAccountPostType: Equatable {  }

// MARK: - Hashable:

extension NT_ProfileAccountPostType: Hashable {  }
