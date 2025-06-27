//
//  TermsFiveSections+FunctionsExtension.swift
//  Native
//

import Foundation

extension TermsFiveSectionsView {
    
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
