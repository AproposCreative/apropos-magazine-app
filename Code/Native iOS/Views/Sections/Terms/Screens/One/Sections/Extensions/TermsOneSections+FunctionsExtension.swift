//
//  TermsOneSections+FunctionsExtension.swift
//  Native
//

import Foundation

extension TermsOneSectionsView {
    
    // MARK: - Functions:
    
    /// Returns the title of the given section:
    func title(_ section: NT_TermsSection) -> String {
        section.title
    }
    
    /// Returns the title of the given sub-section:
    func title(_ subsection: NT_TermsSubsection) -> String {
        subsection.title
    }
    
    /// Returns the content of the given sub-section:
    func content(_ subsection: NT_TermsSubsection) -> String {
        subsection.content
    }
    
    /// Returns an array of the sub-sections with the terms that are part of the given section to display:
    func subsections(_ section: NT_TermsSection) -> [NT_TermsSubsection] {
        section.subsections
    }
}
