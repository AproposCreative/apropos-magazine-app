//
//  MainSixAccountsToFollow+ComputedPropertiesExtension.swift
//  Native
//

import Foundation

extension MainSixAccountsToFollowView {
    
    // MARK: - Computed properties:
    
    /// 'Bool' value indicating whether or not the content of the view should be shown at all:
    var isShowing: Bool {
        !accounts.isEmpty
    }
}
