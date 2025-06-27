//
//  ProductDetailsTwoView.swift
//  Native
//

import SwiftUI

struct ProductDetailsTwoView: View {
    
    // MARK: - Properties:
    
    /// An actual product to display the details for:
    let product: NT_Product
    
    // MARK: - Private properties:
    
    /// Dismisses the view:
    @Environment(\.dismiss) private var dismiss
    
    init(product: NT_Product) {
        
        /// Properties initialization:
        self.product = product
    }
    
    // MARK: - View:
    
    var body: some View {
        content
    }
    
    private var content: some View {
        item
            .background(Color(.systemGroupedBackground))
            .localizedNavigationTitle(title: "Product Details")
            .toolbarButton(
                title: "Done",
                action: dismiss.callAsFunction
            )
            .navigationStack()
    }
}

// MARK: - Item:

private extension ProductDetailsTwoView {
    private var item: some View {
        VStack(
            alignment: .leading,
            spacing: 0
        ) {
            itemContent
        }
    }
    
    @ViewBuilder
    private var itemContent: some View {
        scroll
        ProductDetailsTwoToolbarView(product: product)
    }
}

// MARK: - Scroll:

private extension ProductDetailsTwoView {
    private var scroll: some View {
        scrollContent
            .safeAreaPadding(
                .all,
                16
            )
            .safeAreaPadding(
                .bottom,
                16
            )
    }
    
    private var scrollContent: some View {
        ScrollView {
            scrollItem
        }
    }
    
    private var scrollItem: some View {
        VStack(
            alignment: .leading,
            spacing: 32
        ) {
            scrollItemContent
        }
    }
    
    @ViewBuilder
    private var scrollItemContent: some View {
        ProductDetailsTwoDetailsView(product: product)
        ProductDetailsTwoReviewsView(product: product)
        ProductDetailsTwoYouMayAlsoLikeView(product: product)
    }
}

// MARK: - Preview:

#Preview {
    ProductDetailsTwoView(product: .example.first!)
}
