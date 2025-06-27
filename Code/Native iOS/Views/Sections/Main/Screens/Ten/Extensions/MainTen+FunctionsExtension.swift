//
//  MainTen+FunctionsExtension.swift
//  Native
//

import Foundation

extension MainTenView {
    
    // MARK: - Functions:
    
    /// Fetches the data to display:
    func fetchData() async {
        
        /// Firstly making the async task sleep for one second that is transformed into nanoseconds to simulate a network call (Please remove this code in production):
        try? await Task.sleep(nanoseconds: UInt64(1 * 1_000_000_000))
        
        /// Then updating the UI on the main thread:
        await MainActor.run {
            
            /// Then getting an array of the locations that are based on an array of the example locations:
            let locations: [NT_WeatherLocation] = NT_WeatherLocation.example
            
            /// Then assigning an array of the locations to display:
            self.locations = locations
            
            /// Then assigning the location that should be shown currently:
            currentLocation = locations.first
            
            /// Then also getting an array of the forecasts for today that are based on an array of the example forecasts for today:
            let todayForecasts: [NT_WeatherTodayForecast] = NT_WeatherTodayForecast.example
            
            /// Then assigning an array of the forecasts for today to display:
            self.todayForecasts = todayForecasts
            
            /// Then also getting an array of the forecasts that are based on an array of the example forecasts:
            let forecasts: [NT_WeatherForecast] = NT_WeatherForecast.example
            
            /// Then assigning an array of the forecasts to display:
            self.forecasts = forecasts
        }
        
        /*
         
         NOTE: You can add your own logic for fetching the data here.
         
         */
        
        /// Lastly setting the 'isFetching' property to 'false' to stop fetching the data:
        updateIsFetching(false)
    }
    
    /// Lets the user add a new folder:
    func newFolder() {
        
        /*
         
         NOTE: You can add your own logic for adding a new folder here.
         
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
