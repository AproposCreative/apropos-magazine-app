//
//  DataVisualizationFourInterests+FunctionsExtension.swift
//  Native
//

import Foundation

extension DataVisualizationFourInterestsView {
    
    // MARK: - Functions:
    
    /// Returns the title of the given type of the interests:
    func title(_ type: NT_InterestType) -> String {
        type.title
    }
    
    /// Method that gets called whenever the type of the interests changes:
    func interestTypeOnChange(
        _ previousType: NT_InterestType,
        _ newType: NT_InterestType
    ) {
        
        /// Triggering the selection changed haptic feedback indicating that there was a change:
        HapticFeedbacks.selectionChanged()
    }
}
