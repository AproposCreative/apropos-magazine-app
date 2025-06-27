//
//  NT_ProjectFilter.swift
//  Native
//

import Foundation

enum NT_ProjectFilter: Int {
    
    // MARK: - Cases:
    
    case work
    case meetingNotes
    case mobileAppDesign
    case ideasAndInspiration
    case personalTasks
    
    // MARK: - Computed properties:
    
    /// Identifier of the filter:
    var id: Int {
        rawValue
    }
    
    /// Title of the filter:
    var title: String {
        switch self {
        case .work: return .init(localized: "Work")
        case .meetingNotes: return .init(localized: "Meeting Notes")
        case .mobileAppDesign: return .init(localized: "Mobile App Design")
        case .ideasAndInspiration: return .init(localized: "Ideas and Inspiration")
        case .personalTasks: return .init(localized: "Personal Tasks")
        }
    }
    
    /// Description of the filter:
    var description: String {
        switch self {
        case .work: return .init(localized: "45 tasks")
        case .meetingNotes: return .init(localized: "3 tasks")
        case .mobileAppDesign: return .init(localized: "27 tasks")
        case .ideasAndInspiration: return .init(localized: "12 tasks")
        case .personalTasks: return .init(localized: "36 tasks")
        }
    }
}

// MARK: - Identifiable:

extension NT_ProjectFilter: Identifiable {  }

// MARK: - CaseIterable:

extension NT_ProjectFilter: CaseIterable {  }

// MARK: - Equatable:

extension NT_ProjectFilter: Equatable {  }

// MARK: - Hashable:

extension NT_ProjectFilter: Hashable {  }
