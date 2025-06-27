//
//  DataVisualizationThreeContent+FunctionsExtension.swift
//  Native
//

import Foundation

extension DataVisualizationThreeContentView {
    
    // MARK: - Functions:
    
    /// Returns the title of the given time period:
    func title(_ timePeriod: NT_OverviewTimePeriod) -> String {
        timePeriod.title
    }
    
    /// Fetches the data to display:
    func fetchData() async {
        
        /// Firstly making the async task sleep for one second that is transformed into nanoseconds to simulate a network call (Please remove this code in production):
        try? await Task.sleep(nanoseconds: UInt64(1 * 1_000_000_000))
        
        /// Then updating the UI on the main thread:
        await MainActor.run {
            
            /// Then getting an array of the categories of the income that are based on an array of the example categories of the income:
            let incomeCategories: [NT_IncomeCategory] = NT_IncomeCategory.example
            
            /// Then assigning an array of the categories of the income to display:
            self.incomeCategories = incomeCategories
            
            /// Then also getting an array of the unpaid invoices that are based on an array of the example unpaid invoices:
            let unpaidInvoices: [NT_UnpaidInvoice] = NT_UnpaidInvoice.example
            
            /// Then assigning an array of the unpaid invoices to display:
            self.unpaidInvoices = unpaidInvoices
            
            /// Then also getting an array of the investments that are based on an array of the example investments:
            let investments: [NT_Investment] = NT_Investment.example
            
            /// Then assigning an array of the investments to display:
            self.investments = investments
            
            /// Then also getting an array of the categories of the expenses that are based on an array of the example categories of the expenses:
            let expenseCategories: [NT_ExpenseCategory] = NT_ExpenseCategory.example1.filter {
                $0.id != "Item.3"
                && $0.id != "Item.8"
                && $0.id != "Item.9"
            }
            
            /// Then assigning an array of the categories of the expenses to display:
            self.expenseCategories = expenseCategories
        }
        
        /*
         
         NOTE: You can add your own logic for fetching the data here.
         
         */
        
        /// Lastly setting the 'isFetching' property to 'false' to stop fetching the data:
        updateIsFetching(false)
    }
    
    /// Method that gets called whenever the time period changes:
    func timePeriodOnChange(
        _ previousTimePeriod: NT_OverviewTimePeriod,
        _ newTimePeriod: NT_OverviewTimePeriod
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
