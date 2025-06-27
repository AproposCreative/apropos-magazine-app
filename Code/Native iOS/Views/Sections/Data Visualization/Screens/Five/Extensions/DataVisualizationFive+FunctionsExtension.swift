//
//  DataVisualizationFive+FunctionsExtension.swift
//  Native
//

import Foundation

extension DataVisualizationFiveView {
    
    // MARK: - Functions:
    
    /// Returns the short title of the given time period:
    func shortTitle(_ timePeriod: NT_SummaryTimePeriod) -> String {
        timePeriod.shortTitle
    }
    
    /// Fetches the data to display:
    func fetchData() async {
        
        /// Firstly making the async task sleep for one second that is transformed into nanoseconds to simulate a network call (Please remove this code in production):
        try? await Task.sleep(nanoseconds: UInt64(1 * 1_000_000_000))
        
        /// Then updating the UI on the main thread:
        await MainActor.run {
            
            /// Then getting an array of the categories that are based on an array of the example categories:
            let categories: [NT_ExpenseCategory] = NT_ExpenseCategory.example2
            
            /// Then assigning an array of the categories to display:
            self.categories = categories
            
            /// Then also getting an array of the budgets that are based on an array of the example budgets:
            let budgets: [NT_Budget] = NT_Budget.example
            
            /// Then assigning an array of the budgets to display:
            self.budgets = budgets
        }
        
        /*
         
         NOTE: You can add your own logic for fetching the data here.
         
         */
        
        /// Lastly setting the 'isFetching' property to 'false' to stop fetching the data:
        updateIsFetching(false)
    }
    
    /// Shows the screen with the date picker to select the date to filter the data by:
    func showDatePicker() {
        
        
        /*
         
         NOTE: You can add your own logic for showing the date picker here.
         
         */
        
    }
    
    /// Method that gets called whenever the time period changes:
    func timePeriodOnChange(
        _ previousTimePeriod: NT_SummaryTimePeriod,
        _ newTimePeriod: NT_SummaryTimePeriod
    ) {
        
        /// Triggering the selection changed haptic feedback indicating that there was a change:
        HapticFeedbacks.selectionChanged()
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
