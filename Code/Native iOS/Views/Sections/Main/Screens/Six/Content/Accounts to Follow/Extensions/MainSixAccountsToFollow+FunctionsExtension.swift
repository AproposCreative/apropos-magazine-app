//
//  MainSixAccountsToFollow+FunctionsExtension.swift
//  Native
//

import SwiftUI

extension MainSixAccountsToFollowView {
    
    // MARK: - Functions:
    
    /// Returns the name of the given account:
    func name(_ account: NT_Account) -> String {
        account.name
    }
    
    /// Returns the description of the given account:
    func description(_ account: NT_Account) -> String {
        account.description
    }
    
    /// Returns the image of the given account:
    func image(_ account: NT_Account) -> Image {
        .init(account.image)
    }
}
