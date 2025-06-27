//
//  PaywallEightTimeline+FunctionsExtension.swift
//  Native
//

import Foundation

extension PaywallEightTimelineView {
    
    // MARK: - Functions:
    
    /// Returns the title of the given timeline item:
    func title(_ item: NT_Timeline) -> String {
        item.title
    }
    
    /// Returns the subtitle of the given timeline item:
    func subtitle(_ item: NT_Timeline) -> String {
        item.subtitle
    }
    
    /// Returns the icon of the given timeline item:
    func icon(_ item: NT_Timeline) -> String {
        item.icon
    }
}
