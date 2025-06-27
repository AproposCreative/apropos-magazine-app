//
//  PaywallFourteenTimeline+ComputedPropertiesExtension.swift
//  Native
//

import SwiftUI

extension PaywallFourteenTimelineView {
    
    // MARK: - Computed properties:
    
    /// An array of the timeline items to display:
    var timelineItems: [NT_Timeline] {
        NT_Timeline.allCases
    }
    
    /// Color of the background of the icon of the view:
    var iconBackgroundColor: Color {
        .accent.opacity(iconBackgroundColorOpacity)
    }
    
    /// Radius of the rounded corners of the background of the icon of the view:
    var iconBackgroundCornerRadius: Double {
        20
    }
    
    /// Padding at the top of the timeline item that is based on the size of the dynamic type that is currently selected:
    var timelineItemTopPadding: Double {
        shouldMoveContent ? 0 : 9
    }
    
    /// Padding at the bottom of the timeline item that is based on the size of the dynamic type that is currently selected:
    var timelineItemBottomPadding: Double {
        shouldMoveContent ? 24 : 15
    }
    
    // MARK: - Private computed properties:
    
    /// 'Bool' value indicating whether or not the content of the view should be moved that is based on the size of the dynamic type that is currently selected:
    private var shouldMoveContent: Bool {
        dynamicTypeSize >= .accessibility1
    }
    
    /// Opacity of the color of the background of the icon:
    private var iconBackgroundColorOpacity: Double {
        colorScheme == .dark ? 0.16 : 0.08
    }
}
