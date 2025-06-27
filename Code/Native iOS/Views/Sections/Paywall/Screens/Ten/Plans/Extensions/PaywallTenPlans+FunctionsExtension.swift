//
//  PaywallTenPlans+FunctionsExtension.swift
//  Native
//

import SwiftUI

extension PaywallTenPlansView {
    
    // MARK: - Functions:
    
    /// Returns the title of the given pro plan:
    func title(_ plan: NT_ProPlan) -> String {
        plan.title
    }
    
    /// Returns the price of the given pro plan:
    func price(_ plan: NT_ProPlan) -> String {
        plan.price
    }
    
    /// Returns a 'Bool' value indicating whether or not the given pro plan is currently selected:
    func isSelected(_ plan: NT_ProPlan) -> Bool {
        selectedPlanIdentifier == identifier(plan)
    }
    
    /// Returns a 'Bool' value indicating whether or not the badge should be shown for the given pro plan:
    func isShowingBadge(_ plan: NT_ProPlan) -> Bool {
        plan.type == .monthly
    }
    
    /// Returns the color of the border of the given pro plan:
    func borderColor(_ plan: NT_ProPlan) -> Color {
        isSelected(plan) ? .accent : .init(.systemFill)
    }
    
    /// Returns the width of the border of the given pro plan that is based on whether or not it's currently selected:
    func borderWidth(_ plan: NT_ProPlan) -> Double {
        isSelected(plan) ? 2 : 1
    }
    
    /// Selects the given pro plan unless it's already selected:
    func select(_ plan: NT_ProPlan) {
        
        /// Firstly making sure that the given pro plan isn't already selected:
        if !isSelected(plan) {
            
            /// If yes, then selecting the given pro plan by updating the 'selectedPlanIdentifier' property with the identifier of the given pro plan:
            selectedPlanIdentifier = identifier(plan)
            
            /// Lastly triggering the selection changed haptic feedback indicating that there was a change:
            HapticFeedbacks.selectionChanged()
        }
    }
    
    // MARK: - Private functions:
    
    /// Returns the identifier of the given pro plan:
    private func identifier(_ plan: NT_ProPlan) -> String {
        plan.id
    }
}
