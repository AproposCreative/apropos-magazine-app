//
//  PaywallEightTimeline+ComputedPropertiesExtension.swift
//  Native
//

import Foundation

extension PaywallEightTimelineView {
    
    // MARK: - Computed properties:
    
    /// An array of the timeline items to display:
    var timelineItems: [NT_Timeline] {
        NT_Timeline.allCases
    }
}
