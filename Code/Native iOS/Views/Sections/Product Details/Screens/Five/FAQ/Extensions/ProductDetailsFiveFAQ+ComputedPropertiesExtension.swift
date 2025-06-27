//
//  ProductDetailsFiveFAQ+ComputedPropertiesExtension.swift
//  Native
//

import Foundation

extension ProductDetailsFiveFAQView {
    
    // MARK: - Computed properties:
    
    /// An array of the FAQ items to display:
    var faqItems: [NT_ProductFAQ] {
        product.faqItems
    }
    
    /// 'Bool' value indicating whether or not the content of the view should be shown at all:
    var isShowing: Bool {
        !faqItems.isEmpty
    }
    
    /// Spacing between the content of the view:
    var spacing: Double {
        16
    }
}
