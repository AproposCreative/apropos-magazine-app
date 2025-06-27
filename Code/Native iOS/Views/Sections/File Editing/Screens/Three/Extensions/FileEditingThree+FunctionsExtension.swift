//
//  FileEditingThree+FunctionsExtension.swift
//  Native
//

import Foundation

extension FileEditingThreeView {
    
    // MARK: - Functions:
    
    /// Fetches the data to display:
    func fetchData() async {
        
        /// Firstly making the async task sleep for one second that is transformed into nanoseconds to simulate a network call (Please remove this code in production):
        try? await Task.sleep(nanoseconds: UInt64(1 * 1_000_000_000))
        
        /// Then updating the UI on the main thread:
        await MainActor.run {
            
            /// Then getting an array of the sections that are based on an array of the example sections:
            let sections: [NT_WhiteboardSection] = NT_WhiteboardSection.example
            
            /// Then assigning an array of the sections to display:
            self.sections = sections
            
            /// Then getting an array of the boards of the user that are based on an array of the example boards:
            let userBoards: [NT_WhiteboardBoard] = NT_WhiteboardBoard.example.filter { !$0.isTeam }
            
            /// Then assigning an array of the boards of the user to display:
            self.userBoards = userBoards
            
            /// Then getting an array of the boards of the team that are based on an array of the example boards:
            let teamBoards: [NT_WhiteboardBoard] = NT_WhiteboardBoard.example.filter { $0.isTeam }
            
            /// Then assigning an array of the boards of the team to display:
            self.teamBoards = teamBoards
        }
        
        /*
         
         NOTE: You can add your own logic for fetching the data here.
         
         */
        
        /// Lastly setting the 'isFetching' property to 'false' to stop fetching the data:
        updateIsFetching(false)
    }
    
    /// Lets the user add a new board:
    func newBoard() {
        
        /*
         
         NOTE: You can add your own logic for adding a new board here.
         
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
