//
//  MainThree+FunctionsExtension.swift
//  Native
//

import Foundation

extension MainThreeView {
    
    // MARK: - Functions:
    
    /// Returns the content of the given message:
    func content(_ message: NT_Message) -> String {
        message.content
    }
    
    /// Returns the title of the given group with the messages:
    func title(_ group: NT_MessagesGroup) -> String {
        group.title
    }
    
    /// Fetches the data to display:
    func fetchData() async {
        
        /// Firstly making the async task sleep for one second that is transformed into nanoseconds to simulate a network call (Please remove this code in production):
        try? await Task.sleep(nanoseconds: UInt64(1 * 1_000_000_000))
        
        /// Then updating the UI on the main thread:
        await MainActor.run {
            
            /// Then getting an array of the messages that are based on an array of the example messages:
            let messages: [NT_Message] = NT_Message.example
            
            /// Then assigning an array of the messages to display:
            self.messages = messages
            
            /// Then getting an array of the groups with the messages that are based on an array of the example groups with the messages:
            let groups: [NT_MessagesGroup] = NT_MessagesGroup.example
            
            /// Then assigning an array of the groups with the messages to display:
            self.groups = groups
        }
        
        /*
         
         NOTE: You can add your own logic for fetching the data here.
         
         */
        
        /// Lastly setting the 'isFetching' property to 'false' to stop fetching the data:
        updateIsFetching(false)
    }
    
    /// Lets the user send a new message:
    func newMessage() {
        
        /*
         
         NOTE: You can add your own logic for sending a new message here.
         
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
