//
//  TermsThreeOverview+FunctionsExtension.swift
//  Native
//

import Foundation

extension TermsThreeOverviewView {
    
    // MARK: - Functions:
    
    /// Returns the title of the given overview item:
    func title(_ overviewItem: NT_TermsOverview) -> String {
        overviewItem.title
    }
    
    /// Returns the value of the given overview item:
    func value(_ overviewItem: NT_TermsOverview) -> String {
        overviewItem.value
    }
    
    /// Returns the icon of the given overview item:
    func icon(_ overviewItem: NT_TermsOverview) -> String {
        overviewItem.icon
    }
}
