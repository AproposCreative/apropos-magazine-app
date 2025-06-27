//
//  NT_Timeline.swift
//  Native
//

import Foundation

enum NT_Timeline: Int {
    
    // MARK: - Cases:
    
    /// You can add more timeline items by adding more cases below:
    case today
    case in3Days
    case in5Days
    case in7Days
    
    // MARK: - Computed properties:
    
    /// Identifier of the timeline item:
    var id: Int {
        rawValue
    }
    
    /// Title of the timeline item:
    var title: String {
        switch self {
        case .today: return "Today"
        case .in3Days: return "In 3 Days"
        case .in5Days: return "In 5 Days"
        case .in7Days: return "In 7 Days"
        }
    }
    
    /// Subtitle of the timeline item:
    var subtitle: String {
        switch self {
        case .today: return "You will start your free trial and try out our app - you will be able to cancel your trial at any time."
        case .in3Days: return "You can continue enjoying your free trial and take advantage of all the wonderful features our app has on offer."
        case .in5Days: return "We will send you a reminder about the renewal of your subscription."
        case .in7Days: return "The first payment will be taken and your free trial will convert to a paid subscription."
        }
    }
    
    /// Icon of the timeline item:
    var icon: String {
        switch self {
        case .today: return Icons.oneCircle
        case .in3Days: return Icons.threeCircle
        case .in5Days: return Icons.fiveCircle
        case .in7Days: return Icons.sevenCircle
        }
    }
}

// MARK: - Identifiable:

extension NT_Timeline: Identifiable {  }

// MARK: - CaseIterable:

extension NT_Timeline: CaseIterable {  }

// MARK: - Equatable:

extension NT_Timeline: Equatable {  }

// MARK: - Hashable:

extension NT_Timeline: Hashable {  }
