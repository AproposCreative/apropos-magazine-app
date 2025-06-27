//
//  PaywallTwelve+FunctionsExtension.swift
//  Native
//

import Foundation

extension PaywallTwelveView {
    
    // MARK: - Functions:
    
    /// Fetches the pro plans:
    func fetchPlans() async {
        
        /// Firstly making the async task sleep for one second that is transformed into nanoseconds to simulate a network call (Please remove this code in production):
        try? await Task.sleep(nanoseconds: UInt64(1 * 1_000_000_000))
        
        /// Then updating the UI on the main thread:
        await MainActor.run {
            
            /// Then getting an array of the pro plans based on an array of the example pro plans:
            let plans: [NT_ProPlan] = NT_ProPlan.examplePlans
            
            /// Lastly assigning an array of the pro plans:
            self.plans = plans
        }
        
        /*
         
         NOTE: You can add your own logic for fetching the pro plans here.
         
         */
        
        /// Lastly setting the 'isFetching' property to 'false' to stop fetching the data:
        updateIsFetching(false)
    }
    
    /// Lets the user start a free trial of the pro plan:
    func startFreeTrial() {
        
        /*
         
         NOTE: You can add your own logic for starting a free trial here.
         
         */
        
    }
    
    /// Shows the screen with all of the pro plans that are available for purchase:
    func showAllPlans() {
        
        /// Showing the screen with all of the pro plans that are available for purchase by setting the 'isAllPlansPresented' property to 'true':
        isAllPlansPresented = true
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
