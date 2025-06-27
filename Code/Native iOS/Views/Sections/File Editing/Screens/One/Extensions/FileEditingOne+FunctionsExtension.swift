//
//  FileEditingOne+FunctionsExtension.swift
//  Native
//

import Foundation

extension FileEditingOneView {
    
    // MARK: - Functions:
    
    /// Fetches the data to display:
    func fetchData() async {
        
        /// Firstly making the async task sleep for one second that is transformed into nanoseconds to simulate a network call (Please remove this code in production):
        try? await Task.sleep(nanoseconds: UInt64(1 * 1_000_000_000))
        
        /// Then updating the UI on the main thread:
        await MainActor.run {
            
            /// Then getting an array of the sections that are based on an array of the example sections:
            let sections: [NT_DesignToolSection] = NT_DesignToolSection.example
            
            /// Then assigning an array of the sections to display:
            self.sections = sections
            
            /// Then also getting an array of the folders that are based on an array of the example folders:
            let folders: [NT_DesignToolFolder] = NT_DesignToolFolder.example
            
            /// Then assigning an array of the folders to display:
            self.folders = folders
            
            /// Then also getting an array of the tags that are based on an array of the example tags:
            let tags: [NT_DesignToolTag] = NT_DesignToolTag.example
            
            /// Then assigning an array of the tags to display:
            self.tags = tags
        }
        
        /*
         
         NOTE: You can add your own logic for fetching the data here.
         
         */
        
        /// Lastly setting the 'isFetching' property to 'false' to stop fetching the data:
        updateIsFetching(false)
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
