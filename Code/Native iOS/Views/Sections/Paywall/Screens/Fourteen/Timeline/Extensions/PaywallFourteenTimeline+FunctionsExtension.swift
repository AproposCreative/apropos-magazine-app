//
//  PaywallFourteenTimeline+FunctionsExtension.swift
//  Native
//

import Foundation

extension PaywallFourteenTimelineView {
    
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
    
    /// Returns the radius of the top rounded corners of the background of the icon of the given timeline item:
    func iconBackgroundTopCornerRadius(_ item: NT_Timeline) -> Double {
        timelineItems.first == item ? iconBackgroundCornerRadius : 0
    }
    
    /// Returns the radius of the bottom rounded corners of the background of the icon of the given timeline item:
    func iconBackgroundBottomCornerRadius(_ item: NT_Timeline) -> Double {
        timelineItems.last == item ? iconBackgroundCornerRadius : 0
    }
}
