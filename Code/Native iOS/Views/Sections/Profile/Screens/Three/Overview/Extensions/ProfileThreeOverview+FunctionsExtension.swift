//
//  ProfileThreeOverview+FunctionsExtension.swift
//  Native
//

import Foundation

extension ProfileThreeOverviewView {
    
    // MARK: - Functions:
    
    /// Returns the title of the given stat:
    func title(_ stat: NT_ProfileTaskStat) -> String {
        stat.title
    }
    
    /// Returns the value of the given stat as a string:
    func value(_ stat: NT_ProfileTaskStat) -> String {
        stat.value.formatted()
    }
}
