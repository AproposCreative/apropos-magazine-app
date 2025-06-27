//
//  ProductDetailsThreeFAQView.swift
//  Native
//

import SwiftUI

struct ProductDetailsThreeFAQView: View {
    
    // MARK: - Properties:
    
    /// An actual product to display the details for:
    let product: NT_Product
    
    init(product: NT_Product) {
        
        /// Properties initialization:
        self.product = product
    }
    
    // MARK: - View:
    
    var body: some View {
        content
    }
    
    @ViewBuilder
    private var content: some View {
        if isShowing {
            item
        }
    }
}

// MARK: - Item:

private extension ProductDetailsThreeFAQView {
    private var item: some View {
        VStack(
            alignment: .leading,
            spacing: spacing
        ) {
            itemContent
        }
    }
    
    @ViewBuilder
    private var itemContent: some View {
        SectionHeaderView(title: "FAQ")
        faqItemsContent
    }
}

// MARK: - FAQ items:

private extension ProductDetailsThreeFAQView {
    private var faqItemsContent: some View {
        VStack(
            alignment: .leading,
            spacing: spacing
        ) {
            faqItemsItem
        }
    }
    
    private var faqItemsItem: some View {
        ForEach(
            faqItems,
            content: faqItem
        )
    }
    
    private func faqItem(_ faqItem: NT_ProductFAQ) -> some View {
        TitleSubtitleExpandableView(
            title: question(faqItem),
            subtitle: answer(faqItem)
        )
    }
}

// MARK: - Preview:

#Preview {
    ScrollView {
        ProductDetailsThreeFAQView(product: .example.first!)
    }
    .safeAreaPadding(
        .all,
        16
    )
    .safeAreaPadding(
        .bottom,
        16
    )
    .localizedNavigationTitle(title: "Product Details")
    .navigationStack()
}
