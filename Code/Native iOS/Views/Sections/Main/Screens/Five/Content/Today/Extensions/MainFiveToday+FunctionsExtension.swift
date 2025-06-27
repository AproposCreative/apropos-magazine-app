//
//  MainFiveToday+FunctionsExtension.swift
//  Native
//

import SwiftUI

extension MainFiveTodayView {
    
    // MARK: - Functions:
    
    /// Returns the title of the given task:
    func title(_ task: NT_Task) -> String {
        task.title
    }
    
    /// Returns the notes of the given task:
    func notes(_ task: NT_Task) -> String {
        task.notes
    }
    
    /// Returns a 'Bool' value indicating whether or not the given task is already completed:
    func isCompleted(_ task: NT_Task) -> Bool {
        task.isCompleted
    }
    
    /// Returns an array of the badges that are based on the tags that are assigned to the given task:
    func tagBadges(_ task: NT_Task) -> [NT_Badge] {
        task.tags.map {
            NT_Badge(
                id: $0.id,
                isShowingIcon: false,
                icon: Icons.mailStack,
                iconSymbolVariant: .fill,
                iconColor: .white,
                iconGradientStart: .blueGradientStart,
                iconGradientEnd: .blueGradientEnd,
                isIconColorGradient: false,
                title: $0.title,
                isTitleLocalized: false,
                titleTextCase: .uppercase,
                titleAlignment: .center,
                titleColor: $0.color == .orange || $0.color == .yellow ? .black : .white,
                titleGradientStart: .blueGradientStart,
                titleGradientEnd: .blueGradientEnd,
                isTitleColorGradient: false,
                backgroundColor: $0.color,
                backgroundGradientStart: $0.gradientStart,
                backgroundGradientEnd: $0.gradientEnd,
                isBackgroundColorGradient: true,
                isShowingBorder: true,
                borderColor: .init(.secondarySystemGroupedBackground),
                size: .small
            )
        }
    }
    
    /// Lets the user mark or unmark the task as completed:
    func markAsCompleted() {
        
        /*
         
         NOTE: You can add your own logic for marking or unmarking the task as completed here.
         
         */
        
    }
}
