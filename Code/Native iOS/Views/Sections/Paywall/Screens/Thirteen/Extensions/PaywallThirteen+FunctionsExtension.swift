//
//  PaywallThirteen+FunctionsExtension.swift
//  Native
//

import Foundation

extension PaywallThirteenView {
    
    // MARK: - Functions:
    
    /// Fetches the pro plan:
    func fetchPlan() async {
        
        /// Firstly making the async task sleep for one second that is transformed into nanoseconds to simulate a network call (Please remove this code in production):
        try? await Task.sleep(nanoseconds: UInt64(1 * 1_000_000_000))
        
        /// Then making sure that we actually have the lifetime option of the pro plan:
        guard let plan: NT_ProPlan = NT_ProPlan.examplePlans.first(
            where: {
                $0.id == ProPlanIdentifiers.lifetime
            }
        ) else {
            
            /// If not, then simply returning out of this method:
            return
        }
        
        /// If yes, then updating the UI on the main thread:
        await MainActor.run {
            
            /// Lastly assigning the lifetime option of the pro plan:
            self.plan = plan
        }
        
        /*
         
         NOTE: You can add your own logic for fetching the pro plan here.
         
         */
        
        /// Lastly setting the 'isFetching' property to 'false' to stop fetching the data:
        updateIsFetching(false)
    }
    
    /// Lets the user purchase the pro plan:
    func purchase() {
        
        /*
         
         NOTE: You can add your own logic for making a purchase here.
         
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
