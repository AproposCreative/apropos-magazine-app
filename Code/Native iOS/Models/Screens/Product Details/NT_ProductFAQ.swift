//
//  NT_ProductFAQ.swift
//  Native
//

import Foundation

struct NT_ProductFAQ {
    
    // MARK: - Properties:
    
    /// Identifier of the FAQ item:
    let id: String
    
    /// An actual question of the FAQ item:
    let question: String
    
    /// An answer to the question of the FAQ item:
    let answer: String
    
    init(
        id: String,
        question: String,
        answer: String
    ) {
        
        /// Properties initialization:
        self.id = id
        self.question = question
        self.answer = answer
    }
}

// MARK: - Identifiable:

extension NT_ProductFAQ: Identifiable {  }

// MARK: - Equatable:

extension NT_ProductFAQ: Equatable {  }

// MARK: - Hashable:

extension NT_ProductFAQ: Hashable {  }

// MARK: - Example:

extension NT_ProductFAQ {
    
    // MARK: - Computed properties:
    
    /// An array of the example FAQ items:
    static var example: [NT_ProductFAQ] {
        [
            .init(
                id: "Item.1",
                question: "Can I Upgrade the Device’s Storage Myself Later?",
                answer: "Unfortunately, it’s not possible."
            ),
            .init(
                id: "Item.2",
                question: "Does This Product Come with an Extended Warranty?",
                answer: "Yes, it does."
            ),
            .init(
                id: "Item.3",
                question: "Do You Offer Discounts?",
                answer: "Sadly, we don’t offer any discounts at the moment, but we might have a sale in the future. Please check back later."
            ),
            .init(
                id: "Item.4",
                question: "How Can I Return the Product?",
                answer: "You can just send us an email and we will handle the rest."
            ),
            .init(
                id: "Item.5",
                question: "Does This Product Have any Reviews?",
                answer: "Yes, it has a number of reviews from different customers. You can find the reviews on this screen."
            )
        ]
    }
}
