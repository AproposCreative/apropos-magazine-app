//
//  TermsFiveOverview+FunctionsExtension.swift
//  Native
//

import Foundation

extension TermsFiveOverviewView {
    
    // MARK: - Functions:
    
    /// Returns a 'Bool' value indicating whether or not the given overview item has a URL:
    func doesHaveURL(_ overviewItem: NT_TermsOverview) -> Bool {
        overviewItem.doesHaveURL
    }
    
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
    
    /// Returns the URL of the given overview item if applicable:
    func url(_ overviewItem: NT_TermsOverview) -> URL? {
        overviewItem.url
    }
}
