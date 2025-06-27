//
//  ProfileTwoAccount+FunctionsExtension.swift
//  Native
//

import Foundation

extension ProfileTwoAccountView {
    
    // MARK: - Functions:
    
    /// Returns the title of the given stat:
    func title(_ stat: NT_ProfileAccountStat) -> String {
        stat.title
    }
    
    /// Returns the value of the given stat as a string:
    func value(_ stat: NT_ProfileAccountStat) -> String {
        stat.value.formatted(.number.notation(.compactName))
    }
    
    /// Lets the user follow or unfollow the account:
    func follow() {
        
        /*
         
         NOTE: You can add your own logic for following or unfollowing the account here.
         
         */
        
    }
    
    /// Lets the user send a message to the account:
    func message() {
        
        /*
         
         NOTE: You can add your own logic for sending the message to the account here.
         
         */
        
    }
}
