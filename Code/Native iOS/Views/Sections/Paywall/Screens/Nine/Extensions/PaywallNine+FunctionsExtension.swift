//
//  PaywallNine+FunctionsExtension.swift
//  Native
//

import Foundation

extension PaywallNineView {
    
    // MARK: - Functions:
    
    /// Fetches the pro plans:
    func fetchPlans() async {
        
        /// Firstly making the async task sleep for one second that is transformed into nanoseconds to simulate a network call (Please remove this code in production):
        try? await Task.sleep(nanoseconds: UInt64(1 * 1_000_000_000))
        
        /// Then updating the UI on the main thread:
        await MainActor.run {
            
            /// Then getting an array of the pro plans based on an array of the example pro plans:
            let plans: [NT_ProPlan] = NT_ProPlan.examplePlans.filter { $0.type != .lifetime }
            
            /// Lastly assigning an array of the pro plans:
            self.plans = plans
        }
        
        /*
         
         NOTE: You can add your own logic for fetching the pro plans here.
         
         */
        
        /// Lastly setting the 'isFetching' property to 'false' to stop fetching the data:
        updateIsFetching(false)
    }
    
    /// Method that gets called whenever the level of the pro plan changes:
    func planLevelOnChange(
        _ previousLevel: NT_ProPlanLevel,
        _ newLevel: NT_ProPlanLevel
    ) {
        
        /// Triggering the selection changed haptic feedback indicating that there was a change:
        HapticFeedbacks.selectionChanged()
    }
    
    /// Lets the user start a free trial of the pro plan:
    func startFreeTrial() {
        
        /*
         
         NOTE: You can add your own logic for starting a free trial here.
         
         */
        
    }
    
    /// Lets the user restore their previously made purchase:
    func restore() {
        
        /*
         
         NOTE: You can add your own logic for restoring the previously made purchases here.
         
         */
        
    }
    
    // MARK: - Private functions:
    
    /// Updates the 'isFetching' property with the given value:
    @MainActor
    private func updateIsFetching(_ isFetching: Bool) {
        
        /// Firstly making sure that the 'isFetching' property isn't the same as the given value:
        if self.isFetching != isFetching {
            
            /// If yes, then updating the 'isFetching' property with the given value:
            self.isFetching = isFetching
        }
    }
}
