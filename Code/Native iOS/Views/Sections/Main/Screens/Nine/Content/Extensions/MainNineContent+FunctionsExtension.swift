//
//  MainNineContent+FunctionsExtension.swift
//  Native
//

import Foundation

extension MainNineContentView {
    
    // MARK: - Functions:
    
    /// Returns the title of the given folder:
    func title(_ folder: NT_Folder) -> String {
        folder.title
    }
    
    /// Returns the title of the given drive:
    func title(_ drive: NT_Drive) -> String {
        drive.title
    }
    
    /// Fetches the data to display:
    func fetchData() async {
        
        /// Firstly making the async task sleep for one second that is transformed into nanoseconds to simulate a network call (Please remove this code in production):
        try? await Task.sleep(nanoseconds: UInt64(1 * 1_000_000_000))
        
        /// Then updating the UI on the main thread:
        await MainActor.run {
            
            /// Then getting an array of the folders that are based on an array of the example folders:
            let folders: [NT_Folder] = NT_Folder.example
            
            /// Then assigning an array of the folders to display:
            self.folders = folders
            
            /// Then also getting an array of the drives that are based on an array of the example drives:
            let drives: [NT_Drive] = NT_Drive.example
            
            /// Then assigning an array of the drives to display:
            self.drives = drives
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
    
    /// Lets the user edit the folders and the drives:
    func edit() {
        
        /*
         
         NOTE: You can add your own logic for editing the folders and the drives here.
         
         */
        
    }
    
    /// Lets the user filter the folders and the drives:
    func filter() {
        
        /*
         
         NOTE: You can add your own logic for filtering the folders and the drives here.
         
         */
        
    }
    
    /// Shows the settings screen:
    func showSettings() {
        
        /*
         
         NOTE: You can add your own logic for showing the settings here.
         
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
