//
//  TermsThreeSections+FunctionsExtension.swift
//  Native
//

import Foundation

extension TermsThreeSectionsView {
    
    // MARK: - Functions:
    
    /// Returns the title of the given section:
    func title(_ section: NT_TermsSection) -> String {
        section.title
    }
    
    /// Returns the content of the given section:
    func content(_ section: NT_TermsSection) -> String {
        section.content
    }
}
