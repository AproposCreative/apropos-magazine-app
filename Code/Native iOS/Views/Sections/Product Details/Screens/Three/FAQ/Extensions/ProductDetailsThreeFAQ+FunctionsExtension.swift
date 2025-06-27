//
//  ProductDetailsThreeFAQ+FunctionsExtension.swift
//  Native
//

import Foundation

extension ProductDetailsThreeFAQView {
    
    // MARK: - Functions:
    
    /// Returns the question of the given FAQ item:
    func question(_ faqItem: NT_ProductFAQ) -> String {
        faqItem.question
    }
    
    /// Returns the answer of the given FAQ item:
    func answer(_ faqItem: NT_ProductFAQ) -> String {
        faqItem.answer
    }
}
